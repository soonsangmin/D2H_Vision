`timescale 1ns / 1ps

// ============================================================================
// LOW-RESOURCE GLOBAL AVERAGE POOL - FINAL S8 VERSION + M10K ACCUMULATOR
//
// Input:
//   24 x 24 x 128 HWC stream
//
// Operation:
//   1) avg = floor(sum(pixel[0..575][ch]) / 576)
//   2) qgap = symmetric_round(avg * GAP_MULT_Q31 / 2^31)
//   3) saturate to S8 [-127,127]
//
// Resource optimizations:
//   1. NO '/' operator / no LPM divider.
//   2. NO final_sum[CHANNELS] array.
//   3. One serial binary divider is reused across all CHANNELS.
//   4. Per-channel accumulators are stored in a synchronous M10K RAM.
//   5. A 1-bit valid map replaces a full-array data clear at frame completion.
//   6. One pending-input register aligns the synchronous RAM read with the
//      accepted HWC input stream. MAC arithmetic and quantization are unchanged.
//
// Exact arithmetic:
//   final HEAD is ReLU6/S8, therefore pixel is 0..127.
//   sum <= 127*576 = 73152. 17 bits are sufficient.
//   576 is an exact integer divisor.
//
// Divider:
//   Restoring unsigned division, one quotient bit per clock.
//   SUM_BITS iterations are used for each channel.
//   Default WIDTH=HEIGHT=24, INPUT_MAX=127 gives SUM_BITS=17.
//   CHANNELS=256 then requires about 4352 divider cycles.
//
// External interface is unchanged.
// ============================================================================

module gap_avg_pool #(
    parameter WIDTH    = 24,
    parameter HEIGHT   = 24,
    parameter CHANNELS = 256,
    // Locked Python S8 reference: HEAD -> GAP Q31 multiplier
    parameter [31:0] GAP_MULT_Q31 = 32'h722F68A5,
    // HEAD clamps its S8/ReLU6 output to 0..127. Set to 255 only if GAP is
    // reused with a full-range unsigned U8 input stream.
    parameter integer INPUT_MAX = 127
)(
    input wire        clk,
    input wire        rst_n,

    // ========================================================================
    // INPUT HWC STREAM
    // ========================================================================

    input wire        in_valid,
    input wire [7:0]  pixel_in,
    input wire [7:0]  in_ch_idx,

    output reg        ready,
    input  wire       out_ready,

    // ========================================================================
    // OUTPUT
    // ========================================================================

    output reg [7:0]  gap_out,
    output reg [((CHANNELS <= 1) ? 1 : $clog2(CHANNELS))-1:0] out_ch_idx,
    output reg        out_valid,

    output reg        frame_done
);

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    localparam integer TOTAL_PIXELS =
        WIDTH * HEIGHT;

    localparam integer DIVISOR =
        TOTAL_PIXELS;

    // For the locked HEAD output, max accumulated value is 127*TOTAL_PIXELS.
    // With a 24x24 feature map this is 73152, so 17 bits are sufficient.
    // INPUT_MAX remains configurable for a general U8 source.
    localparam integer SUM_BITS = $clog2(INPUT_MAX*WIDTH*HEIGHT + 1);

    // DIV_CNT_BITS stores values 0..SUM_BITS-1 (5 bits for the default setup).
    localparam integer DIV_CNT_BITS = (SUM_BITS <= 1) ? 1 : $clog2(SUM_BITS);

    localparam signed [31:0] GAP_MULT_SIGNED = $signed(GAP_MULT_Q31);
    localparam signed [63:0] Q31_HALF = 64'sd1073741824; // 2^30

    // ========================================================================
    // STATES
    // ========================================================================

    localparam [2:0]
        ST_INPUT    = 3'd0,
        ST_PREP_DIV = 3'd1,
        ST_WAIT_DIV = 3'd2,
        ST_DIVIDE   = 3'd3,
        ST_OUTPUT   = 3'd4,
        ST_DRAIN    = 3'd5;

    reg [2:0] state;

    localparam integer CH_BITS = (CHANNELS <= 1) ? 1 : $clog2(CHANNELS);
    reg [CH_BITS-1:0] div_ch;

    // Synchronous single-read/single-write accumulator memory. Do NOT reset
    // this array: accum_valid[] masks stale RAM contents after reset/new frame.
    (* ramstyle = "M10K" *)
    reg [SUM_BITS-1:0] accum_mem [0:CHANNELS-1];
    reg [SUM_BITS-1:0] accum_rd_data;

    reg [CHANNELS-1:0] accum_valid;

    // The input stream is accepted HWC scalar-by-scalar. The RAM read result
    // belongs to this pending channel on the following clock edge.
    reg                  accum_pending_valid;
    reg [CH_BITS-1:0]    accum_pending_ch;
    reg [7:0]            accum_pending_pixel;

    wire input_fire = (state == ST_INPUT) && in_valid && ready &&
                      (in_ch_idx < CHANNELS);
    wire accum_rd_en = input_fire || (state == ST_DRAIN) ||
                       (state == ST_PREP_DIV);
    wire [CH_BITS-1:0] accum_rd_addr = input_fire ?
                       in_ch_idx[CH_BITS-1:0] : div_ch;

    wire [SUM_BITS-1:0] pending_pixel_ext =
                       {{(SUM_BITS-8){1'b0}}, accum_pending_pixel};
    wire [SUM_BITS-1:0] accum_write_value = accum_valid[accum_pending_ch] ?
                       (accum_rd_data + pending_pixel_ext) : pending_pixel_ext;

    // Separate clocked read/write processes encourage Quartus to infer a
    // simple dual-port M10K. In the required HWC stream, current read channel
    // differs from the previous cycle's pending write channel.
    always @(posedge clk) begin
        if (rst_n && accum_rd_en)
            accum_rd_data <= accum_mem[accum_rd_addr];
    end

    always @(posedge clk) begin
        if (rst_n && accum_pending_valid)
            accum_mem[accum_pending_ch] <= accum_write_value;
    end

    // Control/valid flags remain registers; only 256 bits are cleared at a
    // frame boundary instead of clearing all 256 x SUM_BITS accumulator bits.
    integer valid_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_pending_valid <= 1'b0;
            accum_pending_ch <= {CH_BITS{1'b0}};
            accum_pending_pixel <= 8'd0;
            accum_valid <= {CHANNELS{1'b0}};
        end else begin
            accum_pending_valid <= input_fire;
            if (input_fire) begin
                accum_pending_ch <= in_ch_idx[CH_BITS-1:0];
                accum_pending_pixel <= pixel_in;
            end

            if (accum_pending_valid)
                accum_valid[accum_pending_ch] <= 1'b1;

            // Clear only validity metadata; the RAM is intentionally not
            // cleared and its stale values are ignored until re-written.
            if ((state == ST_OUTPUT) && out_valid && out_ready &&
                (div_ch == CHANNELS-1)) begin
                for (valid_i = 0; valid_i < CHANNELS; valid_i = valid_i + 1)
                    accum_valid[valid_i] <= 1'b0;
            end
        end
    end

    // The per-channel sums live in accum_mem[] (synchronous M10K).

    // ========================================================================
    // INPUT PIXEL COUNTER
    //
    // 0..575
    // ========================================================================

    reg [9:0] pixel_count;

    // ========================================================================
    // OUTPUT CHANNEL COUNTER
    // ========================================================================

    reg [((CHANNELS <= 1) ? 1 : $clog2(CHANNELS))-1:0] out_cnt;

    // ========================================================================
    // SERIAL DIVIDER
    //
    // Unsigned restoring division:
    //
    // dividend = accum_mem[div_ch] (loaded through accum_rd_data)
    // divisor  = WIDTH * HEIGHT
    //
    // One quotient bit per clock.
    //
    // DIVIDE_BITS = 18
    // ========================================================================

    reg [SUM_BITS-1:0] div_quotient;
    reg [SUM_BITS-1:0] div_remainder;
    reg [SUM_BITS-1:0] div_dividend;

    reg [SUM_BITS-1:0] div_shift;
    reg [DIV_CNT_BITS-1:0] div_count;

    reg signed [63:0] gap_num;
    reg signed [63:0] gap_q_s8;

    // ========================================================================
    // FINAL S8 Q31 REQUANTIZATION
    // Symmetric rounding, exactly matching Python reference.
    // ========================================================================

    function signed [63:0] q31_round_sym;
        input signed [63:0] num;
        begin
            // Exact symmetric Q31 rounding without a 64-bit absolute-value
            // negate and post-round negate. For negative integer num:
            // -floor((abs(num)+2^30)/2^31)
            //   = floor((num + 2^30 - 1)/2^31).
            // gap_num is a bounded pooled-activation x Q31 multiplier product;
            // it cannot reach the signed-64 minimum where unary negation wraps.
            if (num[63])
                q31_round_sym = (num + (Q31_HALF - 64'sd1)) >>> 31;
            else
                q31_round_sym = (num + Q31_HALF) >>> 31;
        end
    endfunction

    // ========================================================================
    // MAIN FSM
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_INPUT;

            ready <= 1'b1;

            gap_out <= 8'd0;
            out_ch_idx <= 8'd0;
            out_valid <= 1'b0;
            frame_done <= 1'b0;

            pixel_count <= 10'd0;
            out_cnt <= 8'd0;

            div_quotient <= {SUM_BITS{1'b0}};
            div_remainder <= {SUM_BITS{1'b0}};
            div_dividend <= {SUM_BITS{1'b0}};
            div_shift <= {SUM_BITS{1'b0}};
            div_count <= {DIV_CNT_BITS{1'b0}};
            div_ch <= {CH_BITS{1'b0}};

            gap_num <= 64'sd0;
            gap_q_s8 <= 64'sd0;

        end

        else begin

            out_valid <= 1'b0;
            frame_done <= 1'b0;

            case (state)

                // =================================================================
                // RECEIVE HWC STREAM
                // =================================================================

                ST_INPUT: begin

                    ready <= 1'b1;

                    if (input_fire) begin

                        // The synchronous accumulator read is issued in parallel
                        // with acceptance. The pending-input pipeline writes the
                        // sum back on the next clock, without changing input order.

                        if (
                            in_ch_idx ==
                            CHANNELS-1
                        ) begin

                            // Last channel of the last spatial position. The
                            // accepted sample is committed by the pending-write
                            // pipeline during ST_DRAIN before divider channel 0 is
                            // consumed.

                            if (
                                pixel_count ==
                                TOTAL_PIXELS-1
                            ) begin

                                div_ch <=
                                    {CH_BITS{1'b0}};

                                state <=
                                    ST_DRAIN;

                                ready <=
                                    1'b0;

                            end

                            else begin

                                pixel_count <=
                                    pixel_count
                                    +
                                    1'b1;

                            end

                        end

                    end

                end

                // =====================================================================
                // PREPARE SERIAL DIVIDER FOR CURRENT CHANNEL
                // =====================================================================

                ST_DRAIN: begin
                    // Flush the final accepted input through the pending write
                    // pipeline while starting the synchronous read for channel 0.
                    ready <= 1'b0;
                    div_ch <= {CH_BITS{1'b0}};
                    state <= ST_WAIT_DIV;
                end

                ST_PREP_DIV: begin
                    // Issue a synchronous RAM read for the next output channel.
                    ready <= 1'b0;
                    state <= ST_WAIT_DIV;
                end

                ST_WAIT_DIV: begin
                    // accum_rd_data was registered by the preceding ST_DRAIN
                    // or ST_PREP_DIV edge. Load divider registers exactly as the
                    // reference implementation did from the register accumulator array.
                    ready <= 1'b0;
                    div_dividend <= accum_rd_data;
                    div_shift <= accum_rd_data;
                    div_remainder <= {SUM_BITS{1'b0}};
                    div_quotient <= {SUM_BITS{1'b0}};
                    div_count <= {DIV_CNT_BITS{1'b0}};
                    state <= ST_DIVIDE;
                end

                // =====================================================================
                // SERIAL RESTORING DIVISION
                //
                // quotient = dividend / 576
                //
                // Process MSB -> LSB.
                // =====================================================================

                ST_DIVIDE: begin

                    ready <= 1'b0;

                    // ------------------------------------------------------------
                    // Shift remainder left and bring in current dividend bit.
                    //
                    // div_count = 0 ... 17
                    // Current source bit:
                    //   SUM_BITS-1-div_count
                    // ------------------------------------------------------------

                    if (
                        (
                            (div_remainder << 1)
                            |
                            div_shift[SUM_BITS-1]
                        )
                        >=
                        DIVISOR
                    ) begin

                        div_remainder <=
                            (
                                (
                                    div_remainder << 1
                                )
                                |
                                div_shift[SUM_BITS-1]
                            )
                            -
                            DIVISOR;

                        div_quotient <=
                            (
                                div_quotient << 1
                            )
                            |
                            1'b1;

                    end

                    else begin

                        div_remainder <=
                            (
                                div_remainder << 1
                            )
                            |
                            div_shift[SUM_BITS-1];

                        div_quotient <=
                            (
                                div_quotient << 1
                            );

                    end

                    div_shift <=
                        div_shift << 1;

                    // ------------------------------------------------------------
                    // Last of 18 quotient bits.
                    // ------------------------------------------------------------

                    if (
                        div_count ==
                        SUM_BITS-1
                    ) begin

                 

                        state <=
                            ST_OUTPUT;

                    end
                    else begin

                        div_count <=
                            div_count
                            +
                            1'b1;

                    end

                end

                // =====================================================================
                // OUTPUT ONE GAP CHANNEL
                // =====================================================================

                ST_OUTPUT: begin

                    // Hold VALID/DATA until FC accepts this GAP vector entry.
                    // The GAP average is followed by the locked HEAD->GAP Q31
                    // requantization and S8 saturation.
                    ready      <= 1'b0;
                    out_valid  <= 1'b1;
                    out_ch_idx <= div_ch;

                    gap_num   = $signed({1'b0, div_quotient}) * GAP_MULT_SIGNED;
                    gap_q_s8  = q31_round_sym(gap_num);

                    if (gap_q_s8 < -64'sd127)
                        gap_out <= 8'h81;
                    else if (gap_q_s8 > 64'sd127)
                        gap_out <= 8'h7F;
                    else
                        gap_out <= gap_q_s8[7:0];

                    if (out_valid && out_ready) begin

                        if (div_ch == CHANNELS-1) begin

                            out_cnt     <= 7'd0;
                            ready       <= 1'b1;
                            out_valid   <= 1'b0;
                            frame_done  <= 1'b1;
                            state       <= ST_INPUT;
                            pixel_count <= 10'd0;

                        end
                        else begin

                            // Keep the established one-cycle bubble between
                            // successive GAP channels.  Handshake behavior is
                            // intentionally unchanged from the working version.
                            out_valid <= 1'b0;

                            div_ch <= div_ch + 1'b1;
                            state  <= ST_PREP_DIV;

                        end
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

endmodule
