module pw_engine_expand #(
    // FINAL LOCKED MODEL: RAW U8 input -> downstream S8, Q31=31, ReLU6 clamp 0..127.
    // Handshake/FSM is intentionally unchanged.
    // Candidate: 6 output lanes x 2 input channels/cycle, 48-bit packed synchronous weight ROM, split Q31.
    // Requires exp_weight_packed48.hex generated from b*_exp_weight.hex by pack_exp_weight_packed48.py.

    // --- FINAL FLAT HEX: b{1..7}_exp_{weight,bias,mult}.hex ---
    parameter B1_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b1_exp_weight.hex",
    parameter B1_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b1_exp_bias_s16.hex",
    parameter B1_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b1_exp_mult.hex",

    parameter B2_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b2_exp_weight.hex",
    parameter B2_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b2_exp_bias_s16.hex",
    parameter B2_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b2_exp_mult.hex",

    parameter B3_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b3_exp_weight.hex",
    parameter B3_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b3_exp_bias_s16.hex",
    parameter B3_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b3_exp_mult.hex",

    parameter B4_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b4_exp_weight.hex",
    parameter B4_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b4_exp_bias_s16.hex",
    parameter B4_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b4_exp_mult.hex",

    parameter B5_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b5_exp_weight.hex",
    parameter B5_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b5_exp_bias_s16.hex",
    parameter B5_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b5_exp_mult.hex",

    parameter B6_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b6_exp_weight.hex",
    parameter B6_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b6_exp_bias_s16.hex",
    parameter B6_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b6_exp_mult.hex",

    parameter B7_EXP_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b7_exp_weight.hex",
    parameter B7_EXP_BIAS_FILE =
        "rtl/classifier/hex_weights/b7_exp_bias_s16.hex",
    parameter B7_EXP_MULT_FILE =
        "rtl/classifier/hex_weights/b7_exp_mult.hex",

    
    parameter QSHIFT             = 31,
    parameter PARALLEL_OUT       = 6
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [2:0]  block_sel, // 0=B1, 1=B2, 2=B3, 3=B4, 4=B5, 5=B6, 6=B7

    input  wire        in_valid,
    input  wire [7:0]  pixel_in,
    input  wire [7:0]  in_ch_idx,
    
    input  wire        window_ready,

    output reg         ready,
    output reg [7:0]   pw_out,
    output reg [7:0]   out_ch_idx,
    output reg         out_valid,
    output reg         busy
);

    localparam integer MAX_IN_CH  = 128;
    localparam integer MAX_OUT_CH = 256;

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
    reg [7:0] group_index;
    reg [7:0] quant_index;

    localparam integer EXP_WEIGHT_WORDS = 9408;
    localparam integer EXP_WEIGHT_PAIRS = EXP_WEIGHT_WORDS / 2;
    // Synchronous dual-read ROM. This format makes the coefficient lookup
    // infer embedded M10K memory rather than a large asynchronous mux network.
    // Bit-exact optimization: one ROM word holds the consecutive channel
    // weights at addresses (2*k, 2*k+1). No arithmetic changes.
    // Physically banked ROM; equivalent data and one-cycle synchronous latency.
    wire [95:0] exp_weight_pair_q;
    classifier_weight_rom96_banked #(
        .ROM_KIND(0),
        .BANK_COUNT(5)
    ) u_exp_rom_banked (
        .clk(clk),
        .rd_en(rst_n && exp_weight_rd_en),
        .rd_addr(exp_weight_rd_addr0[13:1]),
        .rd_data(exp_weight_pair_q)
    );
    wire [47:0] exp_weight_q0 = exp_weight_pair_q[47:0];
    wire [47:0] exp_weight_q1 = exp_weight_pair_q[95:48];

    reg signed [15:0] b1_bias [0:47];   reg signed [31:0] b1_mult [0:0];
    reg signed [15:0] b2_bias [0:47];   reg signed [31:0] b2_mult [0:0];
    reg signed [15:0] b3_bias [0:63];   reg signed [31:0] b3_mult [0:0];
    reg signed [15:0] b4_bias [0:63];   reg signed [31:0] b4_mult [0:0];
    reg signed [15:0] b5_bias [0:127];  reg signed [31:0] b5_mult [0:0];
    reg signed [15:0] b6_bias [0:127];  reg signed [31:0] b6_mult [0:0];
    reg signed [15:0] b7_bias [0:255];  reg signed [31:0] b7_mult [0:0];

    // Pack each consecutive input-channel pair into one 16-bit RAM word.
    // The RAM has one synchronous read port and one synchronous write port,
    // which is substantially easier for Quartus to infer as embedded memory
    // than two independent variable-index byte reads from a 128x8 array.
    localparam integer INPUT_PAIR_DEPTH = MAX_IN_CH / 2;
    (* ramstyle = "M10K" *) reg [15:0] input_pair_buf [0:INPUT_PAIR_DEPTH-1];
    reg [7:0]  input_first_q;
    reg [15:0] input_pair_q;

    // Keep only one PARALLEL_OUT-sized group of quantized results.
    // This replaces the full MAX_OUT_CH byte output buffer.
    localparam integer OUT_LANE_W = (PARALLEL_OUT <= 2) ? 1 : $clog2(PARALLEL_OUT);
    reg [7:0]         group_output_buf [0:PARALLEL_OUT-1];
    reg [OUT_LANE_W-1:0] output_lane;
    // Locked model bound: |input|<=128, |weight|<=128, <=128 channels,
    // |bias|<=4166. Therefore |sum|<=128*128*128+4166=2,101,318,
    // which fits signed 23-bit range. V18 keeps the split Q31-product datapath
    // at the exact 23x17 partial-product width and 23x32 full-product width.
    reg signed [22:0] group_accum [0:PARALLEL_OUT-1];
    reg signed [22:0] group_next_accum [0:PARALLEL_OUT-1];

    reg signed [7:0]  current_weight0;
    reg signed [7:0]  current_weight1;
    reg signed [39:0] quant_partial_lo;
    reg signed [54:0] quant_full_product;
    reg signed [31:0] selected_quant_mult;
    reg signed [31:0] current_quant_mult;

    // Stage 14 timing retime: register the shared multiplier output every clock
    // so Quartus can consider the DSP's internal output registers. The existing
    // QUANT/QUANT_HI schedule overlaps low/high products and requantization.
    reg signed [22:0] quant_operand_q;
    reg [OUT_LANE_W-1:0] quant_lane;
    reg [OUT_LANE_W-1:0] quant_high_lane_q;
    reg [OUT_LANE_W-1:0] quant_full_lane_q;
    reg quant_high_valid_q;
    reg quant_full_valid_q;
    reg signed [39:0] quant_mul_product_q;

    reg [8:0] selected_in_ch;
    integer i, j;
    integer dbg_vector_count;
    integer dbg_output_fire_count;
    // Maximum legal candidate index is 256 + PARALLEL_OUT - 1 (< 512).
    // A 9-bit unsigned temporary is sufficient; avoid a 32-bit integer datapath.
    reg [8:0] out_index;

    // Exact signed 8x8 product, sign-extended only after the 16-bit result.
    // This avoids expressing each MAC as a sign-extended 32x32 multiply.
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
            // Exact sum width: signed 17-bit for two signed 8x8 products.
            sum_two_s8_products = $signed({p0[15], p0}) + $signed({p1[15], p1});
        end
    endfunction

    // Area-optimized, bit-exact Q31 requantization for the existing ReLU clamp
    // [0,127]. Negative products always clamp to zero, so do not build a wide
    // absolute-value/negative-rounding datapath. Saturation is detected before
    // the rounding adder; only the low QSHIFT+7 bits are needed in the
    // unsaturated range. QSHIFT=31 in this locked model.
    localparam integer REQUANT_HIGH_BIT = QSHIFT + 7;

    function [7:0] quantize_expand_relu6;
        input signed [54:0] product_in;
        reg [QSHIFT+6:0] rounded_positive;
        reg [QSHIFT+6:0] half_q;
        begin
            half_q = {{(QSHIFT+6){1'b0}}, 1'b1} << (QSHIFT-1);

            if (product_in[54]) begin
                quantize_expand_relu6 = 8'd0;
            end else if ((|product_in[53:REQUANT_HIGH_BIT]) ||
                         (product_in[QSHIFT+6:QSHIFT] == 7'd127) ||
                         ((product_in[QSHIFT+6:QSHIFT] == 7'd126) &&
                          product_in[QSHIFT-1])) begin
                quantize_expand_relu6 = 8'd127;
            end else begin
                rounded_positive = product_in[QSHIFT+6:0] + half_q;
                quantize_expand_relu6 = {1'b0, rounded_positive[QSHIFT+6:QSHIFT]};
            end
        end
    endfunction

    // Nạp dữ liệu Hex vào ROM
    initial begin
        $readmemh(B1_EXP_BIAS_FILE, b1_bias); $readmemh(B1_EXP_MULT_FILE, b1_mult, 0, 0);
        $readmemh(B2_EXP_BIAS_FILE, b2_bias); $readmemh(B2_EXP_MULT_FILE, b2_mult, 0, 0);
        $readmemh(B3_EXP_BIAS_FILE, b3_bias); $readmemh(B3_EXP_MULT_FILE, b3_mult, 0, 0);
        $readmemh(B4_EXP_BIAS_FILE, b4_bias); $readmemh(B4_EXP_MULT_FILE, b4_mult, 0, 0);
        $readmemh(B5_EXP_BIAS_FILE, b5_bias); $readmemh(B5_EXP_MULT_FILE, b5_mult, 0, 0);
        $readmemh(B6_EXP_BIAS_FILE, b6_bias); $readmemh(B6_EXP_MULT_FILE, b6_mult, 0, 0);
        $readmemh(B7_EXP_BIAS_FILE, b7_bias); $readmemh(B7_EXP_MULT_FILE, b7_mult, 0, 0);

    end

    always @(*) begin
        case (block_sel)
            3'd0: begin selected_in_ch=24;  end
            3'd1: begin selected_in_ch=24;  end
            3'd2: begin selected_in_ch=32;  end
            3'd3: begin selected_in_ch=32;  end
            3'd4: begin selected_in_ch=64;  end
            3'd5: begin selected_in_ch=64;  end
            3'd6: begin selected_in_ch=128; end
            default: begin selected_in_ch=24; end
        endcase
    end

    always @(*) begin
        case (active_block)
            3'd0: begin active_in_ch=24;  active_out_ch=48;  end
            3'd1: begin active_in_ch=24;  active_out_ch=48;  end
            3'd2: begin active_in_ch=32;  active_out_ch=64;  end
            3'd3: begin active_in_ch=32;  active_out_ch=64;  end
            3'd4: begin active_in_ch=64;  active_out_ch=128; end
            3'd5: begin active_in_ch=64;  active_out_ch=128; end
            3'd6: begin active_in_ch=128; active_out_ch=256; end
            default: begin active_in_ch=24; active_out_ch=48; end
        endcase
    end

    // Packed 48-bit ROM: six adjacent output-channel weights per input channel.
    // Address is indexed by group_index so no variable division is in the ROM path.
    function [13:0] exp_weight_address;
        input [2:0] block_id;
        input [7:0] weight_group;
        input [7:0] in_ch;
        begin
            case (block_id)
                3'd0: exp_weight_address = 14'd0    + (weight_group * 14'd24)  + in_ch;
                3'd1: exp_weight_address = 14'd192  + (weight_group * 14'd24)  + in_ch;
                3'd2: exp_weight_address = 14'd384  + (weight_group * 14'd32)  + in_ch;
                3'd3: exp_weight_address = 14'd736  + (weight_group * 14'd32)  + in_ch;
                3'd4: exp_weight_address = 14'd1088 + (weight_group * 14'd64)  + in_ch;
                3'd5: exp_weight_address = 14'd2496 + (weight_group * 14'd64)  + in_ch;
                3'd6: exp_weight_address = 14'd3904 + (weight_group * 14'd128) + in_ch;
                default: exp_weight_address = 14'd0;
            endcase
        end
    endfunction

    reg        exp_weight_rd_en;
    reg [2:0]  exp_weight_rd_block;
    reg [7:0]  exp_weight_rd_group;
    reg [7:0]  exp_weight_rd_ch0;
    reg [7:0]  exp_weight_rd_ch1;
    reg [13:0] exp_weight_rd_addr0;
    reg [13:0] exp_weight_rd_addr1;

    wire rx_last_channel =
        (state == ST_RX) && ready &&
        ({1'b0,in_ch_idx} == (selected_in_ch - 1'b1));

    // Reuse the input-pair RAM for every output-channel group. All output
    // groups consume the same input vector, so pair 0 must be prefetched again
    // on the cycle the previous group is accepted and the FSM returns to ST_MAC.
    // This is concurrent with the existing next-group weight-ROM prefetch and
    // does not add a state or a cycle.
    wire output_preload_next_group =
        (state == ST_OUTPUT) && out_valid && window_ready &&
        ((output_lane == PARALLEL_OUT-1) ||
         ((group_base_out + output_lane + 1'b1) >= active_out_ch)) &&
        ((group_base_out + PARALLEL_OUT) < active_out_ch);

    // current_in_ch is the first channel of a pair: (k,k+1).
    wire mac_has_next_pair =
        (state == ST_MAC) &&
        ({1'b0,current_in_ch} < (active_in_ch - 9'd2));

    // Read pair 0 after the final input channel is accepted, and again at every
    // output-group restart. During MAC, read one pair ahead while consuming the
    // current input_pair_q. Without the group-restart read, group 1+ begins with
    // the stale last pair from the preceding group and corrupts EXP activations.
    wire input_pair_rd_en = (rx_last_channel && in_valid) ||
                            mac_has_next_pair ||
                            output_preload_next_group;
    wire [5:0] input_pair_rd_addr =
        ((rx_last_channel && in_valid) || output_preload_next_group)
            ? 6'd0
            : (current_in_ch[6:1] + 6'd1);

    always @* begin
        exp_weight_rd_en    = (rx_last_channel && in_valid) ||
                              mac_has_next_pair ||
                              output_preload_next_group;
        exp_weight_rd_block = active_block;
        exp_weight_rd_group = group_index;
        exp_weight_rd_ch0   = current_in_ch;
        exp_weight_rd_ch1   = current_in_ch + 1'b1;

        if (rx_last_channel) begin
            exp_weight_rd_block = block_sel;
            exp_weight_rd_group = 8'd0;
            exp_weight_rd_ch0   = 8'd0;
            exp_weight_rd_ch1   = 8'd1;
        end else if ((state == ST_MAC) && mac_has_next_pair) begin
            exp_weight_rd_ch0 = current_in_ch + 2'd2;
            exp_weight_rd_ch1 = current_in_ch + 2'd3;
        end else if (output_preload_next_group) begin
            exp_weight_rd_group = group_index + 1'b1;
            exp_weight_rd_ch0   = 8'd0;
            exp_weight_rd_ch1   = 8'd1;
        end

        exp_weight_rd_addr0 = exp_weight_address(exp_weight_rd_block,
                                                  exp_weight_rd_group,
                                                  exp_weight_rd_ch0);
        exp_weight_rd_addr1 = exp_weight_address(exp_weight_rd_block,
                                                  exp_weight_rd_group,
                                                  exp_weight_rd_ch1);
    end

    // Simulation-only guard: the packing is correct ONLY for consecutive
    // even/odd addresses. This preserves the original dual-read semantics.
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && exp_weight_rd_en &&
            ((exp_weight_rd_addr0[0] !== 1'b0) ||
             (exp_weight_rd_addr1 !== (exp_weight_rd_addr0 + 14'd1)))) begin
            $display("[V6.1.5][FATAL] EXP ROM reads are not an even/odd pair: %d, %d",
                exp_weight_rd_addr0, exp_weight_rd_addr1);
            $finish;
        end
    end
`endif

    // Two synchronous read ports fetch two input-channel weight words each MAC cycle.
    // The memory is read-only after initialization; Quartus may map the ports to
    // true dual-port M10K blocks. Verify RAM inference in the Fitter report.
    // The output of u_exp_rom_banked replaces this read exactly, with one clock of latency.

    // Shared split Q31 multiplier. ST_QUANT computes the unsigned low half;
    // ST_QUANT_HI computes the signed high half and combines both exactly.
    // V18 uses 23-bit accumulator operands (not sign-extended 32-bit copies),
    // 40-bit partial products (23x17), and a 55-bit full product (23x32).
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
    wire signed [16:0] exp_quant_mul_b =
        (state == ST_QUANT)
            ? $signed({1'b0, selected_quant_mult[15:0]})
            : $signed({selected_quant_mult[31], selected_quant_mult[31:16]});
    // Use the registered lane operand: keep group_base_out subtraction and the
    // dynamic group_accum mux out of the DSP-to-output critical path.
    wire signed [39:0] exp_quant_mul_product =
        $signed(quant_operand_q) * $signed(exp_quant_mul_b);

    // Intentionally free-running/no reset/no enable: this shape is friendlier to
    // DSP output-register packing than a state-enabled register in the FSM.
    always @(posedge clk)
        quant_mul_product_q <= exp_quant_mul_product;

    // At ST_OUTPUT entry the final lane's low product and high product are both
    // registered. This expression is only used to flush that final lane.
    wire signed [54:0] quant_pending_full_product =
        {{15{quant_partial_lo[39]}}, quant_partial_lo} +
        ({{15{quant_mul_product_q[39]}}, quant_mul_product_q} <<< 16);

    // Share one requantization/clamp network for ordinary lanes and the final
    // flush lane to limit ALM growth. The data-select is outside the DSP path.
    wire quant_flush_final = (state == ST_OUTPUT) && !out_valid && quant_high_valid_q;
    wire signed [54:0] quant_product_to_clip =
        quant_flush_final ? quant_pending_full_product : quant_full_product;
    wire [7:0] quantized_product_to_clip = quantize_expand_relu6(quant_product_to_clip);

    // Synchronous write port for the packed input staging RAM.
    // Input channels arrive sequentially in HWC order. Save each even channel,
    // then commit {odd,even} as one 16-bit word when its odd channel is accepted.
    // All model input-channel counts are even, so every pair is committed before
    // ST_MAC begins.
    always @(posedge clk) begin
        if (rst_n && state == ST_RX && in_valid && ready && (in_ch_idx < MAX_IN_CH)) begin
            if (!in_ch_idx[0]) begin
                input_first_q <= pixel_in;
            end else begin
                input_pair_buf[in_ch_idx[6:1]] <= {pixel_in, input_first_q};
            end
        end
    end

    // One-clock synchronous RAM read. While the final input channel is accepted,
    // prefetch pair 0 so the first ST_MAC cycle is unchanged. While processing a
    // pair, prefetch the next pair in parallel with the next weight-ROM read.
    always @(posedge clk) begin
        if (rst_n && input_pair_rd_en)
            input_pair_q <= input_pair_buf[input_pair_rd_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RX;
            dbg_vector_count <= 0;
            dbg_output_fire_count <= 0;
            active_block <= 3'd0;
            ready <= 1'b1;
            busy <= 1'b0;
            out_valid <= 1'b0;
            pw_out <= 8'd0;
            out_ch_idx <= 8'd0;
            current_in_ch <= 8'd0;
            group_base_out <= 9'd0;
            group_index <= 8'd0;
            quant_index <= 8'd0;
            for (i=0;i<PARALLEL_OUT;i=i+1) begin
                group_accum[i] <= 23'sd0;
                group_next_accum[i] = 23'sd0;
            end
            quant_partial_lo <= 40'sd0;
            quant_full_product <= 55'sd0;
            quant_operand_q <= 23'sd0;
            quant_lane <= {OUT_LANE_W{1'b0}};
            quant_high_lane_q <= {OUT_LANE_W{1'b0}};
            quant_full_lane_q <= {OUT_LANE_W{1'b0}};
            quant_high_valid_q <= 1'b0;
            quant_full_valid_q <= 1'b0;
            output_lane <= {OUT_LANE_W{1'b0}};
            // input_pair_buf/input_first_q/input_pair_q/group_output_buf are not
            // reset. Every pair word is committed before the first ST_MAC read.
        end else begin
            case (state)
                ST_RX: begin
                    ready <= 1'b1;
                    busy <= 1'b0;
                    out_valid <= 1'b0;

                    if (in_valid && ready) begin
                        if (in_ch_idx == 8'd0)
                            active_block <= block_sel;


                        if ({1'b0,in_ch_idx} == (active_in_ch - 1'b1)) begin
                            if (block_sel == 3'd0) begin
                                if ((dbg_vector_count < 3) || ((dbg_vector_count % 1024) == 0) ||
                                    (dbg_vector_count == 9215))
                                dbg_vector_count <= dbg_vector_count + 1;
                            end
                            group_base_out <= 9'd0;
                            group_index <= 8'd0;
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
                                        default: group_accum[j] <= 23'sd0;
                                    endcase
                                end else begin
                                    group_accum[j] <= 23'sd0;
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

                    // Six output channels times two input channels each cycle.
                    for (j=0;j<PARALLEL_OUT;j=j+1) begin
                        out_index = group_base_out + j;
                        if (out_index < active_out_ch) begin
                            current_weight0 = $signed(exp_weight_q0[(j*8) +: 8]);
                            current_weight1 = $signed(exp_weight_q1[(j*8) +: 8]);
                            group_next_accum[j] = group_accum[j]
                                + sum_two_s8_products($signed(input_pair_q[7:0]),
                                                      $signed(current_weight0),
                                                      $signed(input_pair_q[15:8]),
                                                      $signed(current_weight1));
                        end else begin
                            group_next_accum[j] = group_accum[j];
                        end
                    end

                    for (j=0;j<PARALLEL_OUT;j=j+1)
                        group_accum[j] <= group_next_accum[j];

                    if ({1'b0,current_in_ch} == (active_in_ch - 9'd2)) begin
                        quant_index <= group_base_out[7:0];
                        quant_lane <= {OUT_LANE_W{1'b0}};
                        // group_next_accum contains the final MAC update in this cycle.
                        quant_operand_q <= group_next_accum[0];
                        quant_high_valid_q <= 1'b0;
                        quant_full_valid_q <= 1'b0;
                        state <= ST_QUANT;
                    end else begin
                        current_in_ch <= current_in_ch + 2'd2;
                    end
                end

                ST_QUANT: begin
                    ready <= 1'b0;
                    busy <= 1'b1;

                    // The DSP output register currently contains the previous lane's
                    // signed-high-half product. Combine it with that lane's low-half
                    // partial product while the DSP computes this lane's low half.
                    if (quant_high_valid_q) begin
                        quant_full_product <=
                            {{15{quant_partial_lo[39]}}, quant_partial_lo} +
                            ({{15{quant_mul_product_q[39]}}, quant_mul_product_q} <<< 16);
                        quant_full_lane_q <= quant_high_lane_q;
                        quant_full_valid_q <= 1'b1;
                    end else begin
                        quant_full_valid_q <= 1'b0;
                    end
                    state <= ST_QUANT_HI;
                end

                ST_QUANT_HI: begin : do_expand_quant_hi
                    ready <= 1'b0;
                    busy <= 1'b1;

                    // At the start of ST_QUANT_HI, the free-running DSP output
                    // register contains this lane's low-half product. Capture it;
                    // the multiplier register receives the high-half product at
                    // this edge. Both paths now end at registers before requantize.
                    quant_partial_lo <= quant_mul_product_q;
                    quant_high_lane_q <= quant_lane;
                    quant_high_valid_q <= 1'b1;

                    // Requantize the preceding lane's already-registered full product.
                    if (quant_full_valid_q) begin
                        group_output_buf[quant_full_lane_q] <= quantized_product_to_clip;

                        if ((active_block == 3'd0) && (dbg_vector_count <= 1) &&
                            ((group_base_out + quant_full_lane_q) < 4)) begin
                            $display("[PWEXP QDBG S14] ch=%0d lane=%0d acc=%0d mult=%08h full_product=%0d qbyte=%0d",
                                     group_base_out + quant_full_lane_q,
                                     quant_full_lane_q,
                                     group_accum[quant_full_lane_q],
                                     selected_quant_mult,
                                     quant_full_product,
                                     quantized_product_to_clip);
                        end
                    end
                    quant_full_valid_q <= 1'b0;

                    if ((quant_index + 1) >= (group_base_out + PARALLEL_OUT) ||
                        (quant_index + 1) >= active_out_ch) begin
                        if ((group_base_out + PARALLEL_OUT) >= active_out_ch) begin
                            if (active_block == 3'd0) begin
                                if ((dbg_vector_count <= 3) || ((dbg_vector_count % 1024) == 0) ||
                                    (dbg_vector_count == 9215))
                                    $display("[PWEXP-GROUP-STREAM] FINAL GROUP READY vector=%0d base=%0d",
                                             dbg_vector_count, group_base_out);
                            end
                        end
                        output_lane <= {OUT_LANE_W{1'b0}};
                        out_valid <= 1'b0;
                        state <= ST_OUTPUT;
                    end else begin
                        quant_index <= quant_index + 1'b1;
                        quant_lane <= quant_lane + 1'b1;
                        // Group accumulators are final by the time quantization starts.
                        quant_operand_q <= group_accum[quant_lane + 1'b1];
                        state <= ST_QUANT;
                    end
                end

                ST_OUTPUT: begin
                    ready <= 1'b0;
                    busy <= 1'b1;

                    // Load a packet from the small group buffer. When stalled,
                    // keep out_valid/out_ch_idx/pw_out stable.
                    if (!out_valid) begin
                        // The final lane has no subsequent ST_QUANT cycle in which
                        // to consume its full product. Flush it here from registered
                        // low/high products, while loading lane 0 for output. The
                        // architecture's output widths leave at least two lanes in
                        // every partial group, so lane 0 is already committed.
                        if (quant_high_valid_q) begin
                            group_output_buf[quant_high_lane_q] <= quantized_product_to_clip;
                            quant_high_valid_q <= 1'b0;
                            quant_full_valid_q <= 1'b0;
                        end
                        output_lane <= {OUT_LANE_W{1'b0}};
                        out_ch_idx <= group_base_out[7:0];
                        pw_out <= group_output_buf[0];
                        out_valid <= 1'b1;
                    end else if (out_valid && window_ready) begin
                        if (active_block == 3'd0) begin
                            if ((dbg_output_fire_count < 4) ||
                                ((dbg_output_fire_count % 4096) == 0) ||
                                (out_ch_idx == active_out_ch-1))
                                dbg_output_fire_count <= dbg_output_fire_count + 1;
                        end

                        // More channels remain in the current PARALLEL_OUT group.
                        if (((output_lane + 1) < PARALLEL_OUT) &&
                            ((group_base_out + output_lane + 1) < active_out_ch)) begin
                            output_lane <= output_lane + 1'b1;
                            out_ch_idx <= group_base_out + output_lane + 1'b1;
                            pw_out <= group_output_buf[output_lane + 1'b1];
                            out_valid <= 1'b1;
                        end else if ((group_base_out + PARALLEL_OUT) >= active_out_ch) begin
                            // Last channel in the complete output vector accepted.
                            group_base_out <= 9'd0;
                            group_index <= 8'd0;
                            current_in_ch <= 8'd0;
                            output_lane <= {OUT_LANE_W{1'b0}};
                            out_valid <= 1'b0;
                            ready <= 1'b1;
                            busy <= 1'b0;
                            state <= ST_RX;
                        end else begin
                            // Current group accepted: initialize the next group's
                            // accumulators, then compute that group from input_buf.
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
                                        default: group_accum[j] <= 23'sd0;
                                    endcase
                                end else begin
                                    group_accum[j] <= 23'sd0;
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
