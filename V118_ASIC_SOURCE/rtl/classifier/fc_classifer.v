`timescale 1ns / 1ps
// V12 area optimization: model bias values are verified to fit signed 16-bit.

// ============================================================================
// PARAMETRIC FC CLASSIFIER
//
// One GAP frame = IN_CH uint8 values.
// NUM_CLASSES = 7.
//
// PARALLEL_CLASS controls the number of class MAC lanes:
//
//   1 -> 1 class MAC/cycle
//   2 -> 2 class MACs/cycle
//   4 -> 4 class MACs/cycle
//   7 -> original 7-class parallel architecture
//
// The GAP producer in the current CNN sends one channel per clock and does
// not expose a separate FC-ready handshake. Therefore this implementation
// first buffers the complete GAP vector, then performs the FC calculation.
//
// This keeps the external FC interface unchanged.
//
// Numerical operation remains exact:
//
//   logit[c] = bias[c] + Σ GAP[ch] * weight[ch][c]
//
// Weight layout:
//   Python / final HEX: [class][channel]
//   weight[class * IN_CH + channel]
//
// GAP values are final S8 representation. In the locked reference
// they are non-negative after GAP, so 0..127 is numerically identical
// whether the byte is viewed as U8 or S8.
// Weight is signed S8.
// No Q31 requantization is applied after FC.
// ============================================================================

module fc_classifier #(
    parameter IN_CH = 256,
    parameter NUM_CLASSES = 7,

    parameter HEX_WEIGHT_FILE =
        "rtl/classifier/hex_weights/fc_weight.hex",

    parameter HEX_BIAS_FILE =
        "rtl/classifier/hex_weights/fc_bias_s16.hex",

    parameter PARALLEL_CLASS = 2
)(
    input wire clk,
    input wire rst_n,

    input wire in_valid,
    input wire [7:0] gap_in,
    input wire [((IN_CH <= 1) ? 1 : $clog2(IN_CH))-1:0] in_ch_idx,

    output reg ready,

    output reg signed [31:0] fc_out,
    output reg [2:0] class_idx,
    output reg out_valid,

    output reg frame_done
);

    localparam integer NUM_WEIGHTS =
        IN_CH * NUM_CLASSES;

    localparam integer NUM_GROUPS =
        (NUM_CLASSES + PARALLEL_CLASS - 1)
        /
        PARALLEL_CLASS;

    localparam integer GROUP_CNT_WIDTH =
        (NUM_GROUPS <= 1)
        ? 1
        : $clog2(NUM_GROUPS);

    localparam integer CH_CNT_WIDTH =
        (IN_CH <= 1)
        ? 1
        : $clog2(IN_CH);

    // ========================================================================
    // STATES
    // ========================================================================

    localparam [2:0]
        ST_INPUT   = 3'd0,
        ST_MAC     = 3'd1,
        ST_DRAIN   = 3'd2;

    reg [2:0] state;

    // ========================================================================
    // FC PARAMETERS
    // ========================================================================

    reg signed [7:0]
        fc_weights [0:NUM_WEIGHTS-1];

    reg signed [15:0]
        fc_bias [0:NUM_CLASSES-1];

    // ========================================================================
    // GAP FRAME BUFFER
    // ========================================================================

    reg [7:0]
        gap_buf [0:IN_CH-1];

    // ========================================================================
    // ACCUMULATORS
    //
    // One accumulator per class.
    // Only PARALLEL_CLASS accumulators are updated per MAC cycle.
    // ========================================================================

    // Worst case for U8 GAP x S8 weight over 256 channels plus locked FC bias
    // is <8.36M, within signed 24-bit range. Output is sign-extended to 32 bits.
    reg signed [23:0]
        accum [0:NUM_CLASSES-1];

    // ========================================================================
    // MAC GROUP CONTROL
    // ========================================================================

    reg [((IN_CH <= 1) ? 1 : $clog2(IN_CH))-1:0] mac_input_ch;

    reg [2:0] group_base;

    reg [2:0] drain_cnt;

    // ========================================================================
    // PARALLEL TEMPORARY VALUES
    // ========================================================================

    // U8 x S8 fits exactly in signed 16 bits: min=0xFF*(-128)=-32640,
    // max=0xFF*127=32385. Keep only the mathematically sufficient product width.
    reg signed [15:0]
        product [0:PARALLEL_CLASS-1];

    reg signed [23:0]
        accum_next [0:PARALLEL_CLASS-1];

    integer lane;
    reg [2:0] cls;
    localparam integer WEIGHT_INDEX_WIDTH =
        (NUM_WEIGHTS <= 1) ? 1 : $clog2(NUM_WEIGHTS);
    reg [WEIGHT_INDEX_WIDTH-1:0] weight_index;
    integer i;

    // ========================================================================
    // GAP is S8, but final GAP output is non-negative (0..127).
    // Therefore U8 interpretation is numerically identical here.
    // Keep the function name to preserve the existing datapath structure.
    // ========================================================================

    function signed [15:0] mul_gap_s8;

        input [7:0] pixel;
        input signed [7:0] weight;

        // Sign-extend both operands to the product width. Synthesis can trim
        // constant/sign-extension bits, while the product remains bit-exact.
        reg signed [15:0] pixel_ext16;
        reg signed [15:0] weight_ext16;

        begin
            pixel_ext16  = {8'd0, pixel};
            weight_ext16 = {{8{weight[7]}}, weight};
            mul_gap_s8 = pixel_ext16 * weight_ext16;
        end

    endfunction
    
    // ========================================================================
    // LOAD PARAMETERS
    // ========================================================================

    initial begin

        $readmemh(
            HEX_WEIGHT_FILE,
            fc_weights
        );

        $readmemh(
            HEX_BIAS_FILE,
            fc_bias
        );

    end

    // ========================================================================
    // MAIN
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_INPUT;

            ready <= 1'b1;

            fc_out <= 32'sd0;
            class_idx <= 3'd0;
            out_valid <= 1'b0;
            frame_done <= 1'b0;

            mac_input_ch <= 7'd0;
            group_base <= 3'd0;
            drain_cnt <= 3'd0;

            for (
                i = 0;
                i < IN_CH;
                i = i + 1
            ) begin
                gap_buf[i] <= 8'd0;
            end

            for (
                i = 0;
                i < NUM_CLASSES;
                i = i + 1
            ) begin
                accum[i] <= 32'sd0;
            end

        end

        else begin

            out_valid <= 1'b0;
            frame_done <= 1'b0;

            case (state)

                // ============================================================
                // INPUT
                //
                // Store one GAP channel each cycle.
                // ============================================================

                ST_INPUT: begin

                    ready <= 1'b1;

                    if (
                        in_valid &&
                        ready
                    ) begin

                        gap_buf[in_ch_idx] <=
                            gap_in;

                        if (
                            in_ch_idx ==
                            IN_CH-1
                        ) begin

                            // ------------------------------------------------
                            // Start FC MAC pass.
                            // All classes are initialized with bias.
                            // ------------------------------------------------

                            for (
                                i = 0;
                                i < NUM_CLASSES;
                                i = i + 1
                            ) begin

                                accum[i] <=
                                    fc_bias[i];

                            end

                            mac_input_ch <=
                                7'd0;

                            group_base <=
                                3'd0;

                            ready <=
                                1'b0;

                            state <=
                                ST_MAC;

                        end

                    end

                end

                // ============================================================
                // FC MAC
                //
                // For each input channel:
                //
                //   process PARALLEL_CLASS output classes.
                //
                // Then move to the next class group.
                //
                // Once all class groups are complete, move to next input
                // channel.
                // ============================================================

                ST_MAC: begin

                    ready <=
                        1'b0;

                    for (
                        lane = 0;
                        lane < PARALLEL_CLASS;
                        lane = lane + 1
                    ) begin

                        cls =
                            group_base
                            +
                            lane;

                        if (
                            cls <
                            NUM_CLASSES
                        ) begin

                            // Final HEX is PyTorch FC weight layout:
                            //   [class][input_channel]
                            // therefore: class * IN_CH + input_channel
                            weight_index =
                                cls
                                * IN_CH
                                +
                                mac_input_ch;

                            product[lane] =
                                mul_gap_s8(
                                    gap_buf[
                                        mac_input_ch
                                    ],
                                    fc_weights[
                                        weight_index
                                    ]
                                );

                            accum_next[lane] =
                                accum[cls]
                                +
                                $signed(product[lane]);

                        end

                    end

                    // --------------------------------------------------------
                    // Commit parallel accumulator updates.
                    // --------------------------------------------------------

                    for (
                        lane = 0;
                        lane < PARALLEL_CLASS;
                        lane = lane + 1
                    ) begin

                        cls =
                            group_base
                            +
                            lane;

                        if (
                            cls <
                            NUM_CLASSES
                        ) begin

                            accum[cls] <=
                                accum_next[lane];

                        end

                    end

                    // --------------------------------------------------------
                    // Last class group?
                    // --------------------------------------------------------

                    if (
                        group_base
                        +
                        PARALLEL_CLASS
                        >=
                        NUM_CLASSES
                    ) begin

                        // ----------------------------------------------------
                        // Last input channel?
                        // ----------------------------------------------------

                        if (
                            mac_input_ch
                            ==
                            IN_CH-1
                        ) begin

                            drain_cnt <=
                                3'd0;

                            state <=
                                ST_DRAIN;

                        end
                        else begin

                            mac_input_ch <=
                                mac_input_ch
                                +
                                1'b1;

                            group_base <=
                                3'd0;

                        end

                    end
                    else begin

                        group_base <=
                            group_base
                            +
                            PARALLEL_CLASS;

                    end

                end

                // ============================================================
                // DRAIN 7 LOGITS
                // ============================================================

                ST_DRAIN: begin

                    ready <=
                        1'b0;

                    out_valid <=
                        1'b1;

                    class_idx <=
                        drain_cnt;

                    fc_out <=
                        {{8{accum[drain_cnt][23]}}, accum[drain_cnt]};

                    if (
                        drain_cnt
                        ==
                        NUM_CLASSES-1
                    ) begin

                        frame_done <=
                            1'b1;

                        drain_cnt <=
                            3'd0;

                        ready <=
                            1'b1;

                        state <=
                            ST_INPUT;

                    end
                    else begin

                        drain_cnt <=
                            drain_cnt
                            +
                            1'b1;

                    end

                end

                default: begin

                    state <=
                        ST_INPUT;

                    ready <=
                        1'b1;

                end

            endcase

        end

    end

    // ========================================================================
    // DEBUG
    // ========================================================================

    integer debug_input_count;

    initial begin
        debug_input_count = 0;
    end

    always @(negedge clk) begin

        if (
            rst_n &&
            in_valid &&
            ready
        ) begin

            if (
                debug_input_count < 2
            ) begin

            end

            debug_input_count =
                debug_input_count + 1;

        end

    end

    always @(negedge clk) begin

        if (
            rst_n &&
            out_valid
        ) begin

        end

    end

endmodule
