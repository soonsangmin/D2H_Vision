`timescale 1ns/1ps
// V12 area optimization: model bias values are verified to fit signed 16-bit.
module pw_engine_project #(
    // --- Đường dẫn file Hex cho các Block Project ($C_{exp} \to C_{out}$) ---
    parameter B1_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b1_proj_weight.hex",
    parameter B1_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b1_proj_bias_s16.hex",
    parameter B1_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b1_proj_mult.hex",

    parameter B2_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b2_proj_weight.hex",
    parameter B2_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b2_proj_bias_s16.hex",
    parameter B2_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b2_proj_mult.hex",

    parameter B3_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b3_proj_weight.hex",
    parameter B3_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b3_proj_bias_s16.hex",
    parameter B3_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b3_proj_mult.hex",

    parameter B4_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b4_proj_weight.hex",
    parameter B4_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b4_proj_bias_s16.hex",
    parameter B4_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b4_proj_mult.hex",

    parameter B5_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b5_proj_weight.hex",
    parameter B5_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b5_proj_bias_s16.hex",
    parameter B5_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b5_proj_mult.hex",

    parameter B6_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b6_proj_weight.hex",
    parameter B6_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b6_proj_bias_s16.hex",
    parameter B6_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b6_proj_mult.hex",

    parameter B7_PROJ_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b7_proj_weight.hex",
    parameter B7_PROJ_BIAS_FILE =
        "rtl/classifier/hex_weights/b7_proj_bias_s16.hex",
    parameter B7_PROJ_MULT_FILE =
        "rtl/classifier/hex_weights/b7_proj_mult.hex",

    parameter QSHIFT              = 31,
    parameter PARALLEL_OUT        = 6
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [2:0]  block_sel,

    input  wire        in_valid,
    input  wire [7:0]  pixel_in,
    input  wire [7:0]  in_ch_idx, // C_exp từ DW trả về

    output reg         ready,
    output reg [7:0]   pw_out,       // signed S8 bit-pattern [-127..127]
    output reg [7:0]   out_ch_idx, // C_out
    output reg         out_valid,
    input  wire        out_ready,
    output reg         busy
);

    localparam integer MAX_IN_CH  = 256;
    localparam integer MAX_OUT_CH = 128;
    localparam integer OUT_LANE_W = (PARALLEL_OUT <= 2) ? 1 : $clog2(PARALLEL_OUT);

    localparam [2:0]
        ST_RX      = 3'd0,
        ST_MAC     = 3'd1,
        ST_QUANT   = 3'd2,
        ST_OUTPUT  = 3'd3,
        ST_QUANT_HI = 3'd4;

    reg [2:0] state;
    reg [2:0] active_block;
    reg [8:0] active_in_ch;
    reg [8:0] active_out_ch;
    reg [7:0] current_in_ch;
    reg [8:0] group_base_out;
    reg [7:0] quant_index;

    // Stage 11 v4: pipeline requantization over the already-existing
    // ST_QUANT / ST_QUANT_HI / ST_OUTPUT schedule, without adding FSM cycles.
    reg [OUT_LANE_W-1:0] quant_lane;
    reg [OUT_LANE_W-1:0] quant_full_lane_q;
    reg quant_product_valid;

    localparam integer PROJ_WEIGHT_WORDS = 11424;
    localparam integer PROJ_WEIGHT_PAIRS = PROJ_WEIGHT_WORDS / 2; // ceil(OUT_CH/6)*IN_CH for all seven projections
    // Bit-exact optimization: one ROM word holds the consecutive channel
    // weights at addresses (2*k, 2*k+1). No arithmetic changes.
    // Physically banked ROM; equivalent data and one-cycle synchronous latency.
    wire [95:0] proj_weight_pair_q;
    classifier_weight_rom96_banked #(
        .ROM_KIND(1),
        .BANK_COUNT(6)
    ) u_proj_rom_banked (
        .clk(clk),
        .rd_en(rst_n && proj_weight_rd_en),
        .rd_addr(proj_weight_rd_addr0[13:1]),
        .rd_data(proj_weight_pair_q)
    );
    wire [47:0] proj_weight_q0 = proj_weight_pair_q[47:0];
    wire [47:0] proj_weight_q1 = proj_weight_pair_q[95:48];
    reg [8:0] group_index; // output group ordinal (group_base_out / 6)

    reg signed [15:0] b1_bias [0:23];  reg signed [31:0] b1_mult [0:0];  // B1: 24 outputs
    reg signed [15:0] b2_bias [0:31];  reg signed [31:0] b2_mult [0:0];  // B2: 32 outputs
    reg signed [15:0] b3_bias [0:31];  reg signed [31:0] b3_mult [0:0];  // B3: 32 outputs

    reg signed [15:0] b4_bias [0:63];  reg signed [31:0] b4_mult [0:0];  // B4: 64 outputs
    reg signed [15:0] b5_bias [0:63];  reg signed [31:0] b5_mult [0:0];  // B5: 64 outputs
    reg signed [15:0] b6_bias [0:127]; reg signed [31:0] b6_mult [0:0]; // B6: 128 outputs
    reg signed [15:0] b7_bias [0:127]; reg signed [31:0] b7_mult [0:0]; // B7: 128 outputs

    // Keep input/output staging vectors out of the async-reset FSM process so
    // Quartus can infer small embedded/distributed RAM instead of thousands of FFs.
    (* ramstyle = "MLAB" *) reg [7:0] input_buf [0:MAX_IN_CH-1];
    // Only one output group is buffered; the full output vector is streamed
    // as each group completes instead of being retained in MAX_OUT_CH bytes.
    reg [7:0] group_output_buf [0:PARALLEL_OUT-1];
    reg [OUT_LANE_W-1:0] output_lane;
    // Locked-model bound: even for signed-byte inputs, <=256 channels,
    // |weight|<=128 and |bias|<=10965 imply |sum|<4.21M, within signed 24 bits.
    // The multiplier operand is sign-extended back to 32 bits below so the
    // Q31 product datapath retains its original width/resource mapping.
    reg signed [23:0] group_accum [0:PARALLEL_OUT-1];
    reg signed [23:0] group_next_accum [0:PARALLEL_OUT-1];

    reg signed [48:0] quant_partial_lo;
    reg signed [63:0] quant_full_product;
    reg signed [7:0] current_weight0 [0:PARALLEL_OUT-1];
    reg signed [7:0] current_weight1 [0:PARALLEL_OUT-1];
    reg signed [31:0] current_quant_mult;
    reg signed [31:0] selected_quant_mult;
    always @* begin
        case (active_block)
            3'd0: selected_quant_mult = b1_mult[0];
            3'd1: selected_quant_mult = b2_mult[0];
            3'd2: selected_quant_mult = b3_mult[0];
            3'd3: selected_quant_mult = b4_mult[0];
            3'd4: selected_quant_mult = b5_mult[0];
            3'd5: selected_quant_mult = b6_mult[0];
            3'd6: selected_quant_mult = b7_mult[0];
            default: selected_quant_mult = 32'sd0;
        endcase
    end
    wire signed [16:0] quant_mul_b =
        (state == ST_QUANT)
            ? $signed({1'b0, selected_quant_mult[15:0]})
            : $signed({selected_quant_mult[31], selected_quant_mult[31:16]});
    wire signed [23:0] quant_accum_narrow =
        group_accum[quant_index - group_base_out[7:0]];
    wire signed [31:0] quant_accum_operand =
        {{8{quant_accum_narrow[23]}}, quant_accum_narrow};
    wire signed [48:0] quant_mul_product =
        $signed(quant_accum_operand) * $signed(quant_mul_b);

    // V17: exact saturated signed Q31 requantization with a 39-bit datapath.
    // Since outputs are clamped to [-127,127], products outside
    // [-127*2^QSHIFT, +127*2^QSHIFT] already map to the corresponding rail.
    // For the remaining interval, product_in fits exactly in signed 39 bits
    // when QSHIFT=31. The rounding rule is unchanged from the previous version:
    // positive: (x + 2^(QSHIFT-1)) >>> QSHIFT
    // negative: (x + 2^(QSHIFT-1)-1) >>> QSHIFT.
    localparam signed [63:0] PROJ_CLIP_LIMIT = (64'sd127 <<< QSHIFT);

    function [7:0] quantize_proj_s8;
        input signed [63:0] product_in;
        reg signed [38:0] scaled_narrow;
        reg signed [38:0] rounded_narrow;
        reg signed [38:0] positive_half_narrow;
        reg signed [38:0] negative_bias_narrow;
        begin
            positive_half_narrow = (39'sd1 <<< (QSHIFT-1));
            negative_bias_narrow = positive_half_narrow - 39'sd1;

            if (product_in >= PROJ_CLIP_LIMIT) begin
                quantize_proj_s8 = 8'h7f;
            end else if (product_in <= -PROJ_CLIP_LIMIT) begin
                quantize_proj_s8 = 8'h81;
            end else begin
                // With the saturated extremes removed, this truncation is exact:
                // the live interval is contained in signed 39-bit range.
                scaled_narrow = $signed(product_in[38:0]);
                if (scaled_narrow[38])
                    rounded_narrow = (scaled_narrow + negative_bias_narrow) >>> QSHIFT;
                else
                    rounded_narrow = (scaled_narrow + positive_half_narrow) >>> QSHIFT;
                quantize_proj_s8 = rounded_narrow[7:0];
            end
        end
    endfunction
    reg [8:0] selected_in_ch;
    reg [8:0] selected_out_ch;

    integer i, j;
    // Maximum candidate output index is below 256 for this model.
    // Keep the address/compare temporary at the architectural 9-bit width.
    reg [8:0] out_index;

    // Exact signed 8x8 product, sign-extended only after the 16-bit result.
    function signed [16:0] sum_two_s8_products;
        input signed [7:0] a0;
        input signed [7:0] b0;
        input signed [7:0] a1;
        input signed [7:0] b1;
        reg signed [15:0] p0;
        reg signed [15:0] p1;
        begin
            // Prefer Cyclone V dedicated DSP for the two independent signed 8x8 products.
            // This is a mapping hint only: operand widths, sign extension, sum width,
            // FSM schedule, and accumulator updates are unchanged.
            p0 = a0 * b0;
            p1 = a1 * b1;
            // Exact range of the sum of two signed 8x8 products is 17 bits.
            sum_two_s8_products = $signed({p0[15], p0}) + $signed({p1[15], p1});
        end
    endfunction

    // Nạp file Hex cho lớp Project
    initial begin
        $display("[FILECHECK] PW_PROJECT_BUILD=20261026_BIAS_DEPTH_FIX PARALLEL_OUT=%0d", PARALLEL_OUT);
        $readmemh(B1_PROJ_BIAS_FILE, b1_bias, 0, 23); $readmemh(B1_PROJ_MULT_FILE, b1_mult, 0, 0);
        $readmemh(B2_PROJ_BIAS_FILE, b2_bias, 0, 31); $readmemh(B2_PROJ_MULT_FILE, b2_mult, 0, 0);
        $readmemh(B3_PROJ_BIAS_FILE, b3_bias, 0, 31); $readmemh(B3_PROJ_MULT_FILE, b3_mult, 0, 0);
        $readmemh(B4_PROJ_BIAS_FILE, b4_bias, 0, 63); $readmemh(B4_PROJ_MULT_FILE, b4_mult, 0, 0);
        $readmemh(B5_PROJ_BIAS_FILE, b5_bias, 0, 63); $readmemh(B5_PROJ_MULT_FILE, b5_mult, 0, 0);
        $readmemh(B6_PROJ_BIAS_FILE, b6_bias, 0, 127); $readmemh(B6_PROJ_MULT_FILE, b6_mult, 0, 0);
        $readmemh(B7_PROJ_BIAS_FILE, b7_bias, 0, 127); $readmemh(B7_PROJ_MULT_FILE, b7_mult, 0, 0);

    end


    always @(*) begin
        case (block_sel)
            3'd0: begin selected_in_ch=48;  selected_out_ch=24;  end
            3'd1: begin selected_in_ch=48;  selected_out_ch=32;  end
            3'd2: begin selected_in_ch=64;  selected_out_ch=32;  end
            3'd3: begin selected_in_ch=64;  selected_out_ch=64;  end
            3'd4: begin selected_in_ch=128; selected_out_ch=64;  end
            3'd5: begin selected_in_ch=128; selected_out_ch=128; end
            3'd6: begin selected_in_ch=256; selected_out_ch=128; end
            default: begin selected_in_ch=48; selected_out_ch=24; end
        endcase
    end

    always @(*) begin
        case (active_block)
            3'd0: begin active_in_ch=48;  active_out_ch=24;  end
            3'd1: begin active_in_ch=48;  active_out_ch=32;  end
            3'd2: begin active_in_ch=64;  active_out_ch=32;  end
            3'd3: begin active_in_ch=64;  active_out_ch=64;  end
            3'd4: begin active_in_ch=128; active_out_ch=64;  end
            3'd5: begin active_in_ch=128; active_out_ch=128; end
            3'd6: begin active_in_ch=256; active_out_ch=128; end
            default: begin active_in_ch=48; active_out_ch=24; end
        endcase
    end

    // Packed48 ROM: six output-channel weights per input channel.
    // Group ordinal avoids division in the timing-critical address path.
    function [13:0] proj_weight_address;
        input [2:0] block_id;
        input [8:0] weight_group;
        input [7:0] in_ch;
        reg [13:0] group_offset;
        begin
            case (block_id)
                3'd0: group_offset = 14'd0    + weight_group * 14'd48;
                3'd1: group_offset = 14'd192  + weight_group * 14'd48;
                3'd2: group_offset = 14'd480  + weight_group * 14'd64;
                3'd3: group_offset = 14'd864  + weight_group * 14'd64;
                3'd4: group_offset = 14'd1568 + weight_group * 14'd128;
                3'd5: group_offset = 14'd2976 + weight_group * 14'd128;
                3'd6: group_offset = 14'd5792 + weight_group * 14'd256;
                default: group_offset = 14'd0;
            endcase
            proj_weight_address = group_offset + in_ch;
        end
    endfunction

    reg        proj_weight_rd_en;
    reg [2:0]  proj_weight_rd_block;
    reg [8:0]  proj_weight_rd_group;
    reg [7:0]  proj_weight_rd_ch0;
    reg [7:0]  proj_weight_rd_ch1;
    reg [13:0] proj_weight_rd_addr0;
    reg [13:0] proj_weight_rd_addr1;

    wire proj_rx_last_channel =
        (state == ST_RX) && in_valid && ready &&
        ({1'b0,in_ch_idx} == (selected_in_ch - 1'b1));
    wire proj_mac_has_next_pair =
        (state == ST_MAC) &&
        ({1'b0,current_in_ch} < (active_in_ch - 9'd2));
    wire proj_output_preload_next_group =
        (state == ST_OUTPUT) && out_valid && out_ready &&
        ((output_lane == PARALLEL_OUT-1) ||
         ((group_base_out + output_lane + 1'b1) >= active_out_ch)) &&
        ((group_base_out + PARALLEL_OUT) < active_out_ch);

    always @* begin
        proj_weight_rd_en = proj_rx_last_channel || proj_mac_has_next_pair ||
                            proj_output_preload_next_group;
        proj_weight_rd_block = active_block;
        proj_weight_rd_group = group_index;
        proj_weight_rd_ch0 = current_in_ch;
        proj_weight_rd_ch1 = current_in_ch + 1'b1;

        if (proj_rx_last_channel) begin
            proj_weight_rd_block = block_sel;
            proj_weight_rd_group = 9'd0;
            proj_weight_rd_ch0 = 8'd0;
            proj_weight_rd_ch1 = 8'd1;
        end else if ((state == ST_MAC) && proj_mac_has_next_pair) begin
            proj_weight_rd_ch0 = current_in_ch + 2'd2;
            proj_weight_rd_ch1 = current_in_ch + 2'd3;
        end else if (proj_output_preload_next_group) begin
            proj_weight_rd_group = group_index + 1'b1;
            proj_weight_rd_ch0 = 8'd0;
            proj_weight_rd_ch1 = 8'd1;
        end

        proj_weight_rd_addr0 = proj_weight_address(proj_weight_rd_block,
                                                    proj_weight_rd_group,
                                                    proj_weight_rd_ch0);
        proj_weight_rd_addr1 = proj_weight_address(proj_weight_rd_block,
                                                    proj_weight_rd_group,
                                                    proj_weight_rd_ch1);
    end

    // Simulation-only guard: the packing is correct ONLY for consecutive
    // even/odd addresses. This preserves the original dual-read semantics.
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && proj_weight_rd_en &&
            ((proj_weight_rd_addr0[0] !== 1'b0) ||
             (proj_weight_rd_addr1 !== (proj_weight_rd_addr0 + 14'd1)))) begin
            $display("[V6.1.5][FATAL] PROJ ROM reads are not an even/odd pair: %d, %d",
                proj_weight_rd_addr0, proj_weight_rd_addr1);
            $finish;
        end
    end
`endif

    // Two synchronous ROM read ports fetch the weight rows for input channels k and k+1.
    // The output of u_proj_rom_banked replaces this read exactly, with one clock of latency.

    // Dedicated synchronous write port for the input staging RAM.
    always @(posedge clk) begin
        if (rst_n && state == ST_RX && in_valid && ready && (in_ch_idx < MAX_IN_CH)) begin
            input_buf[in_ch_idx] <= pixel_in;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RX;
            active_block <= 3'd0;
            ready <= 1'b1;
            busy <= 1'b0;
            out_valid <= 1'b0;
            pw_out <= 8'd0;
            out_ch_idx <= 8'd0;
            current_in_ch <= 8'd0;
            group_base_out <= 9'd0;
            quant_index <= 8'd0;
            quant_lane <= {OUT_LANE_W{1'b0}};
            quant_full_lane_q <= {OUT_LANE_W{1'b0}};
            quant_product_valid <= 1'b0;
            output_lane <= {OUT_LANE_W{1'b0}};
            for (i=0;i<PARALLEL_OUT;i=i+1) begin
                group_accum[i] <= 24'sd0;
                group_next_accum[i] = 24'sd0;
                current_weight0[i] = 8'sd0;
                current_weight1[i] = 8'sd0;
            end
            // input_buf/group_output_buf are intentionally not reset. Input entries
            // are written before ST_MAC, and each output group before it is streamed.
            current_quant_mult <= 32'sd0;
            group_index <= 9'd0;
            quant_partial_lo <= 49'sd0;
            quant_full_product <= 64'sd0;
        end else begin
            case (state)
                ST_RX: begin
                    ready <= 1'b1;
                    busy <= 1'b0;
                    out_valid <= 1'b0;

                    if (in_valid && ready) begin
                        if (in_ch_idx == 8'd0)
                            active_block <= block_sel;

                        // input_buf is written by a separate synchronous memory process.

                        if ({1'b0,in_ch_idx} == (active_in_ch - 1'b1)) begin
                            group_base_out <= 9'd0;
                            group_index <= 9'd0;
                            current_in_ch <= 8'd0;

                            for (j=0;j<PARALLEL_OUT;j=j+1) begin
                                if (j < active_out_ch) begin
                                    case (active_block)
                                        3'd0: group_accum[j] <= b1_bias[j];
                                        3'd1: group_accum[j] <= b2_bias[j];
                                        3'd2: group_accum[j] <= b3_bias[j];
                                        3'd3: group_accum[j] <= b4_bias[j];
                                        3'd4: group_accum[j] <= b5_bias[j];
                                        3'd5: group_accum[j] <= b6_bias[j];
                                        3'd6: group_accum[j] <= b7_bias[j];
                                        default: group_accum[j] <= 24'sd0;
                                    endcase
                                end else begin
                                    group_accum[j] <= 24'sd0;
                                end
                            end
                            ready <= 1'b0;
                            busy <= 1'b1;
                            state <= ST_MAC;
                        end
                    end
                end

                ST_MAC: begin
                    ready <= 1'b0;
                    busy <= 1'b1;

                    // Six output channels times two input channels per cycle.
                    for (j=0;j<PARALLEL_OUT;j=j+1) begin
                        out_index = group_base_out + j;
                        if (out_index < active_out_ch) begin
                            current_weight0[j] = $signed(proj_weight_q0[(j*8) +: 8]);
                            current_weight1[j] = $signed(proj_weight_q1[(j*8) +: 8]);
                            group_next_accum[j] = group_accum[j]
                                + sum_two_s8_products($signed(input_buf[current_in_ch]),
                                                      $signed(current_weight0[j]),
                                                      $signed(input_buf[current_in_ch + 1'b1]),
                                                      $signed(current_weight1[j]));
                        end else begin
                            group_next_accum[j] = group_accum[j];
                        end
                    end

                    for (j=0;j<PARALLEL_OUT;j=j+1)
                        group_accum[j] <= group_next_accum[j];

                    if ({1'b0,current_in_ch} == (active_in_ch - 9'd2)) begin
                        quant_index <= group_base_out[7:0];
                        quant_lane <= {OUT_LANE_W{1'b0}};
                        quant_product_valid <= 1'b0;
                        state <= ST_QUANT;
                    end else begin
                        current_in_ch <= current_in_ch + 2'd2;
                    end
                end

                ST_QUANT: begin
                    // Compute the low multiplier half for the current lane.
                    // In parallel, requantize the previously registered full product.
                    // This splits DSP/add logic from rounding/saturation without an
                    // extra state or an extra cycle per output channel.
                    ready <= 1'b0;
                    busy <= 1'b1;
                    current_quant_mult = selected_quant_mult; // debug visibility only
                    quant_partial_lo <= quant_mul_product;
                    if (quant_product_valid)
                        group_output_buf[quant_full_lane_q] <= quantize_proj_s8(quant_full_product);
                    state <= ST_QUANT_HI;
                end

                ST_QUANT_HI: begin : do_project_quant_hi
                    // Register the full signed multiplier result. The rounding,
                    // shift and saturation are performed in the next ST_QUANT cycle
                    // (or drained in ST_OUTPUT for the final lane).
                    ready <= 1'b0;
                    busy <= 1'b1;
                    quant_full_product <=
                        {{15{quant_partial_lo[48]}}, quant_partial_lo} +
                        ({{15{quant_mul_product[48]}}, quant_mul_product} <<< 16);
                    quant_full_lane_q <= quant_lane;
                    quant_product_valid <= 1'b1;

                    if ((quant_index + 1) >= (group_base_out + PARALLEL_OUT) ||
                        (quant_index + 1) >= active_out_ch) begin
                        output_lane <= {OUT_LANE_W{1'b0}};
                        out_valid <= 1'b0;
                        state <= ST_OUTPUT;
                    end else begin
                        quant_index <= quant_index + 1'b1;
                        quant_lane <= quant_lane + 1'b1;
                        state <= ST_QUANT;
                    end
                end

                ST_OUTPUT: begin
                    ready <= 1'b0;
                    busy <= 1'b1;

                    // Load the first packet of this group. Keep the packet stable
                    // while downstream backpressure is asserted.
                    if (!out_valid) begin
                        // Drain the last registered quantization result before it can
                        // be requested; the final lane is > 0 for this model's 6-lane groups.
                        if (quant_product_valid)
                            group_output_buf[quant_full_lane_q] <= quantize_proj_s8(quant_full_product);
                        output_lane <= {OUT_LANE_W{1'b0}};
                        out_ch_idx <= group_base_out[7:0];
                        pw_out <= group_output_buf[0];
                        out_valid <= 1'b1;
                    end else if (out_valid && out_ready) begin
                        if (((output_lane + 1) < PARALLEL_OUT) &&
                            ((group_base_out + output_lane + 1) < active_out_ch)) begin
                            output_lane <= output_lane + 1'b1;
                            out_ch_idx <= group_base_out + output_lane + 1'b1;
                            pw_out <= group_output_buf[output_lane + 1'b1];
                            out_valid <= 1'b1;
                        end else if ((group_base_out + PARALLEL_OUT) >= active_out_ch) begin
                            // Final output channel for this spatial vector accepted.
                            group_base_out <= 9'd0;
                            group_index <= 9'd0;
                            current_in_ch <= 8'd0;
                            output_lane <= {OUT_LANE_W{1'b0}};
                            out_valid <= 1'b0;
                            ready <= 1'b1;
                            busy <= 1'b0;
                            state <= ST_RX;
                        end else begin
                            // Advance to the next output-channel group only after
                            // all channels of the current group were consumed.
                            group_base_out <= group_base_out + PARALLEL_OUT;
                            group_index <= group_index + 1'b1;
                            current_in_ch <= 8'd0;
                            output_lane <= {OUT_LANE_W{1'b0}};
                            out_valid <= 1'b0;
                            for (j=0;j<PARALLEL_OUT;j=j+1) begin
                                if ((group_base_out + PARALLEL_OUT + j) < active_out_ch) begin
                                    case (active_block)
                                        3'd0: group_accum[j] <= b1_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd1: group_accum[j] <= b2_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd2: group_accum[j] <= b3_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd3: group_accum[j] <= b4_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd4: group_accum[j] <= b5_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd5: group_accum[j] <= b6_bias[group_base_out + PARALLEL_OUT + j];
                                        3'd6: group_accum[j] <= b7_bias[group_base_out + PARALLEL_OUT + j];
                                        default: group_accum[j] <= 24'sd0;
                                    endcase
                                end else begin
                                    group_accum[j] <= 24'sd0;
                                end
                            end
                            state <= ST_MAC;
                        end
                    end
                end

                default: state <= ST_RX;
            endcase
        end
    end
endmodule
