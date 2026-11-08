`timescale 1ns/1ps
// V12 area optimization: model bias values are verified to fit signed 16-bit.
`default_nettype none

// ============================================================================
// HEAD 8-MAC / packed synchronous weight ROM / explicit logic multipliers
//
// Changes versus the known-good 2-MAC retimed head:
//   - Eight input-channel products are accumulated each MAC clock.
//   - Eight adjacent signed INT8 weights are packed into one 64-bit ROM word.
//   - Weights are read synchronously from M10K; next group is prefetched while
//     the current group is being accumulated.
//   - Input activations are stored as 16 groups of 64 bits and read as one
//     synchronous word per MAC clock. The input buffer is deliberately not
//     reset; every byte is overwritten before computation starts.
//   - Eight 8x8 multiplies are directed to logic (not DSP) so the design can
//     trade ALUTs freed by the packed weight ROM for throughput while staying
//     at or below the existing DSP budget. Confirm this in Quartus.
//
// Numerical policy retained: 32-bit signed accumulator, two-pass Q31
// requantization, symmetric round-to-nearest, ReLU6/S8 clipping to [0,127],
// output channels emitted in ascending order, ready/valid hold behavior.
// This is an unverified candidate until simulation and Quartus reports pass.
// ============================================================================
module mobilenet_head #(
    parameter HEAD_PACKED_WEIGHT_FILE =
        "rtl/classifier/hex_weights/head_weight_packed64.hex",
    parameter HEAD_BIAS_FILE =
        "rtl/classifier/hex_weights/head_bias_s16.hex",
    parameter HEAD_MULT_FILE =
        "rtl/classifier/hex_weights/head_mult.hex",
    parameter integer QSHIFT = 31
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_valid,
    input  wire [7:0] in_pixel,
    input  wire [7:0] in_ch_idx,
    output wire       ready,
    input  wire       out_ready,
    output reg [7:0]  out_pixel,
    output reg [7:0]  out_ch_idx,
    output reg        out_valid,
    output reg        busy
);
    localparam integer IN_CH = 128;
    localparam integer OUT_CH = 256;
    localparam integer GROUPS_IN = IN_CH / 8;
    localparam integer WEIGHT_WORDS = OUT_CH * GROUPS_IN;
    localparam integer REQUANT_HIGH_BIT = QSHIFT + 7;

    localparam [2:0]
        ST_WAIT        = 3'd0,
        ST_MAC         = 3'd1,
        ST_REQUANT_LO  = 3'd2,
        ST_OUTPUT      = 3'd3,
        ST_REQUANT_HI  = 3'd4,
        ST_MAC_PRIME   = 3'd5;

    reg [2:0] state;
    reg [7:0] active_in_ch;     // 128,120,...,8
    reg [8:0] active_out_ch;    // 0..255

    // 4096 x 64 bits; synchronous read is intentional for M10K inference.
    (* ramstyle = "M10K" *) reg [63:0] head_weight_rom [0:WEIGHT_WORDS-1];
    reg [63:0] head_weight_q;

    // Two banks of 16 x 64-bit activations. While compute reads one bank,
    // ingress can fill the other bank with the next 128-channel spatial vector.
    // This is a bounded ping-pong buffer; it does not change arithmetic.
    (* ramstyle = "MLAB" *) reg [63:0] input_group_buf [0:(2*GROUPS_IN)-1];
    reg [63:0] input_group_q;
    reg [1:0] buffer_full;
    reg       capture_bank;
    reg       compute_bank;
    // Number of accepted input bytes while MAC/requant/output is active.
    // Exposed as a simulation-visible counter for proving that overlap occurs.
    reg [31:0] input_during_compute_count;
    assign ready = !buffer_full[capture_bank];

    reg signed [15:0] bias_mem [0:OUT_CH-1];
    reg signed [31:0] mult_mem [0:OUT_CH-1];

    // For 128 signed-byte inputs and signed-byte weights, plus locked bias
    // |bias|<=2778, the accumulator magnitude is <2.101M: 23 bits suffice.
    // Q31 multiplication below explicitly sign-extends back to 32 bits.
    reg signed [22:0] accum;
    reg signed [22:0] accum_next;
    reg signed [48:0] quant_partial_lo;

    // Address for the group used by the *next* ST_MAC cycle. The output
    // handshake also prefetches group 15 of the next output channel, avoiding
    // an extra prime cycle for output channels 1..255.
    reg [11:0] weight_rd_addr;
    reg [3:0]  input_rd_addr;
    always @* begin
        weight_rd_addr = 12'd0;
        input_rd_addr  = 4'd0;

        if (state == ST_WAIT) begin
            // Prime group 15 of output channel 0 for the next complete vector.
            weight_rd_addr = 12'd15;
            input_rd_addr  = 4'd15;
        end
        else if (state == ST_MAC_PRIME) begin
            weight_rd_addr = {active_out_ch[7:0], 4'd0} + 12'd15;
            input_rd_addr  = 4'd15;
        end
        else if (state == ST_MAC) begin
            if (active_in_ch > 8) begin
                weight_rd_addr = {active_out_ch[7:0], 4'd0} +
                                 ((active_in_ch >> 3) - 8'd2);
                input_rd_addr = (active_in_ch >> 3) - 8'd2;
            end
            else begin
                weight_rd_addr = {active_out_ch[7:0], 4'd0};
                input_rd_addr  = 4'd0;
            end
        end
        else if (state == ST_OUTPUT && out_valid && out_ready &&
                 active_out_ch != OUT_CH-1) begin
            weight_rd_addr = {(active_out_ch[7:0] + 8'd1), 4'd0} + 12'd15;
            input_rd_addr  = 4'd15;
        end
        else begin
            weight_rd_addr = {active_out_ch[7:0], 4'd0} +
                             ((active_in_ch >> 3) - 8'd1);
            input_rd_addr = (active_in_ch >> 3) - 8'd1;
        end
    end

    // Sync read ports: one read per clock, plus a byte-enabled write port for
    // the incoming activation group. No reset loop is applied to RAM contents.
    always @(posedge clk) begin
        head_weight_q <= head_weight_rom[weight_rd_addr];
        input_group_q <= input_group_buf[{compute_bank, input_rd_addr}];
    end

    always @(posedge clk) begin
        if (rst_n && ready && in_valid && in_ch_idx < IN_CH) begin
            case (in_ch_idx[2:0])
                3'd0: input_group_buf[{capture_bank, in_ch_idx[6:3]}][ 7: 0] <= in_pixel;
                3'd1: input_group_buf[{capture_bank, in_ch_idx[6:3]}][15: 8] <= in_pixel;
                3'd2: input_group_buf[{capture_bank, in_ch_idx[6:3]}][23:16] <= in_pixel;
                3'd3: input_group_buf[{capture_bank, in_ch_idx[6:3]}][31:24] <= in_pixel;
                3'd4: input_group_buf[{capture_bank, in_ch_idx[6:3]}][39:32] <= in_pixel;
                3'd5: input_group_buf[{capture_bank, in_ch_idx[6:3]}][47:40] <= in_pixel;
                3'd6: input_group_buf[{capture_bank, in_ch_idx[6:3]}][55:48] <= in_pixel;
                3'd7: input_group_buf[{capture_bank, in_ch_idx[6:3]}][63:56] <= in_pixel;
                default: begin end
            endcase
        end
    end

    initial begin
        $display("[HEAD-8MAC-PACKED-STAGE10-PINGPONG] ROM=%s", HEAD_PACKED_WEIGHT_FILE);
        $readmemh(HEAD_PACKED_WEIGHT_FILE, head_weight_rom, 0, WEIGHT_WORDS-1);
        $readmemh(HEAD_BIAS_FILE, bias_mem, 0, OUT_CH-1);
        $readmemh(HEAD_MULT_FILE, mult_mem, 0, OUT_CH-1);
    end

    // V5 experiment: encourage dedicated DSP mapping for the eight 8x8
    // activation/weight products. The multiplication expressions, widths,
    // signed casts, adder tree, registers, FSM and handshakes are unchanged.
    // This can reduce ALUT/ALM pressure at the expense of DSP blocks; verify
    // the mapped DSP count, timing, and full regression in Quartus.
    (* multstyle = "dsp" *) wire signed [15:0] prod7;
    (* multstyle = "dsp" *) wire signed [15:0] prod6;
    (* multstyle = "dsp" *) wire signed [15:0] prod5;
    (* multstyle = "dsp" *) wire signed [15:0] prod4;
    (* multstyle = "dsp" *) wire signed [15:0] prod3;
    (* multstyle = "dsp" *) wire signed [15:0] prod2;
    (* multstyle = "dsp" *) wire signed [15:0] prod1;
    (* multstyle = "dsp" *) wire signed [15:0] prod0;


    wire signed [7:0] wt7 = $signed(head_weight_q[63:56]);
    wire signed [7:0] wt6 = $signed(head_weight_q[55:48]);
    wire signed [7:0] wt5 = $signed(head_weight_q[47:40]);
    wire signed [7:0] wt4 = $signed(head_weight_q[39:32]);
    wire signed [7:0] wt3 = $signed(head_weight_q[31:24]);
    wire signed [7:0] wt2 = $signed(head_weight_q[23:16]);
    wire signed [7:0] wt1 = $signed(head_weight_q[15:8]);
    wire signed [7:0] wt0 = $signed(head_weight_q[7:0]);

    wire [7:0] ac7 = input_group_q[63:56];
    wire [7:0] ac6 = input_group_q[55:48];
    wire [7:0] ac5 = input_group_q[47:40];
    wire [7:0] ac4 = input_group_q[39:32];
    wire [7:0] ac3 = input_group_q[31:24];
    wire [7:0] ac2 = input_group_q[23:16];
    wire [7:0] ac1 = input_group_q[15:8];
    wire [7:0] ac0 = input_group_q[7:0];

    // Shared 32x17 multiplier for two-pass Q31 requantization.
    wire signed [16:0] quant_mul_b =
        (state == ST_REQUANT_LO)
          ? $signed({1'b0, mult_mem[active_out_ch][15:0]})
          : $signed({mult_mem[active_out_ch][31], mult_mem[active_out_ch][31:16]});
    wire signed [31:0] accum_q31_operand = {{9{accum[22]}}, accum};
    wire signed [48:0] quant_mul_product = $signed(accum_q31_operand) * quant_mul_b;

    assign prod7 = $signed(ac7) * $signed(wt7);
    assign prod6 = $signed(ac6) * $signed(wt6);
    assign prod5 = $signed(ac5) * $signed(wt5);
    assign prod4 = $signed(ac4) * $signed(wt4);
    assign prod3 = $signed(ac3) * $signed(wt3);
    assign prod2 = $signed(ac2) * $signed(wt2);
    assign prod1 = $signed(ac1) * $signed(wt1);
    assign prod0 = $signed(ac0) * $signed(wt0);

    // Balanced narrow adder tree for the eight 16-bit products. The direct
    // accumulator-plus-seven-products expression creates a long chain of
    // 32-bit adders. Pair sums need 17 bits, groups of four 18 bits, and all
    // eight products 19 bits. No cycle or handshake is added.
    wire signed [16:0] pair01 = $signed({prod0[15], prod0}) + $signed({prod1[15], prod1});
    wire signed [16:0] pair23 = $signed({prod2[15], prod2}) + $signed({prod3[15], prod3});
    wire signed [16:0] pair45 = $signed({prod4[15], prod4}) + $signed({prod5[15], prod5});
    wire signed [16:0] pair67 = $signed({prod6[15], prod6}) + $signed({prod7[15], prod7});
    wire signed [17:0] quad0123 = $signed({pair01[16], pair01}) + $signed({pair23[16], pair23});
    wire signed [17:0] quad4567 = $signed({pair45[16], pair45}) + $signed({pair67[16], pair67});
    wire signed [18:0] prod_sum8 = $signed({quad0123[17], quad0123}) + $signed({quad4567[17], quad4567});

    // Bit-exact Q31 + ReLU clamp [0,127]. Since all negative products clamp
    // to zero, omit the 64-bit absolute-value and negative-rounding path.
    // In the unsaturated range, only QSHIFT+7 low bits are required.
    function [7:0] quantize_head_relu6;
        input signed [63:0] product_in;
        reg [QSHIFT+6:0] rounded_positive;
        reg [QSHIFT+6:0] half_q;
        begin
            half_q = {{(QSHIFT+6){1'b0}}, 1'b1} << (QSHIFT-1);

            if (product_in[63]) begin
                quantize_head_relu6 = 8'd0;
            end else if ((|product_in[62:REQUANT_HIGH_BIT]) ||
                         (product_in[QSHIFT+6:QSHIFT] == 7'd127) ||
                         ((product_in[QSHIFT+6:QSHIFT] == 7'd126) &&
                          product_in[QSHIFT-1])) begin
                quantize_head_relu6 = 8'd127;
            end else begin
                rounded_positive = product_in[QSHIFT+6:0] + half_q;
                quantize_head_relu6 = {1'b0, rounded_positive[QSHIFT+6:QSHIFT]};
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            out_valid <= 1'b0;
            out_pixel <= 8'd0;
            out_ch_idx <= 8'd0;
            state <= ST_WAIT;
            buffer_full <= 2'b00;
            capture_bank <= 1'b0;
            compute_bank <= 1'b0;
            input_during_compute_count <= 32'd0;
            active_in_ch <= IN_CH;
            active_out_ch <= 9'd0;
            accum <= 23'sd0;
            accum_next <= 23'sd0;
            quant_partial_lo <= 49'sd0;
        end
        else begin
            out_valid <= 1'b0;

            // Capture completion is independent of the compute FSM. Because
            // ready is low whenever capture_bank is full, a locked/processing
            // bank can never be overwritten. If capture and compute finish on
            // the same edge, the two updated bank_full bits are distinct.
            if (in_valid && ready && state != ST_WAIT)
                input_during_compute_count <= input_during_compute_count + 1'b1;

            if (in_valid && ready && in_ch_idx == IN_CH-1) begin
                buffer_full[capture_bank] <= 1'b1;
                capture_bank <= ~capture_bank;
            end

            case (state)
                ST_WAIT: begin
                    busy <= 1'b0;
                    if (buffer_full[compute_bank]) begin
                        active_in_ch <= IN_CH;
                        active_out_ch <= 9'd0;
                        accum <= bias_mem[0];
                        busy <= 1'b1;
                        state <= ST_MAC_PRIME;
                    end
                end

                ST_MAC_PRIME: begin
                    busy <= 1'b1;
                    // The previous clock registered group 15 from the sync ROM.
                    state <= ST_MAC;
                end

                ST_MAC: begin
                    busy <= 1'b1;
                    // Products are computed in logic, not DSP blocks.
                    accum_next = accum + prod_sum8;
                    accum <= accum_next;

                    if (active_in_ch == 8) begin
                        state <= ST_REQUANT_LO;
                    end
                    else begin
                        active_in_ch <= active_in_ch - 8'd8;
                    end
                end

                ST_REQUANT_LO: begin
                    busy <= 1'b1;
                    quant_partial_lo <= quant_mul_product;
                    state <= ST_REQUANT_HI;
                end

                ST_REQUANT_HI: begin : do_requant_hi
                    reg signed [63:0] full_product;
                    busy <= 1'b1;
                    full_product =
                        {{15{quant_partial_lo[48]}}, quant_partial_lo} +
                        ({{15{quant_mul_product[48]}}, quant_mul_product} <<< 16);
                    out_pixel <= quantize_head_relu6(full_product);
                    out_ch_idx <= active_out_ch[7:0];
                    state <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    busy <= 1'b1;
                    out_valid <= 1'b1;
                    if (out_valid && out_ready) begin
                        if (active_out_ch == OUT_CH-1) begin
                            active_in_ch <= IN_CH;
                            active_out_ch <= 9'd0;
                            accum <= bias_mem[0];
                            buffer_full[compute_bank] <= 1'b0;
                            compute_bank <= ~compute_bank;
                            busy <= 1'b0;
                            out_valid <= 1'b0;
                            state <= ST_WAIT;
                        end
                        else begin
                            out_valid <= 1'b0;
                            active_in_ch <= IN_CH;
                            active_out_ch <= active_out_ch + 1'b1;
                            accum <= bias_mem[active_out_ch + 1'b1];
                            // The same edge prefetches group 15 for next output
                            // channel through the combinational read address.
                            state <= ST_MAC;
                        end
                    end
                end

                default: begin
                    state <= ST_WAIT;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
`default_nettype wire