`timescale 1ns / 1ps
// V12 area optimization: model bias values are verified to fit signed 16-bit.

// ============================================================================
// DUAL-INPUT STEM CONVOLUTION (Gray + Sobel)
//
// Input: 16-bit pixel window (8-bit Gray + 8-bit Sobel)
// Output: 24 channels Serial Stream (ch0-11 for Gray, ch12-23 for Sobel).
//
// Architecture:
//   - Tách 16-bit input thành 2 mảng 3x3 độc lập.
//   - Gray/Sobel MACs remain parallel; Q31 requantization multiplier is shared.
//   - Lưu kết quả vào 24 kênh xuất.
//   - Xuất nối tiếp (Serial) từng kênh qua giao thức handshake ready/valid.
// ============================================================================

module stem_conv3x3_dual #(
    parameter HEX_WEIGHT_GRAY_FILE  = "rtl/classifier/hex_weights/stem_gray_weight.hex",
    parameter HEX_BIAS_GRAY_FILE    = "rtl/classifier/hex_weights/stem_gray_bias_s16.hex",
    parameter HEX_MULT_GRAY_FILE    = "rtl/classifier/hex_weights/stem_gray_mult.hex",

    parameter HEX_WEIGHT_SOBEL_FILE = "rtl/classifier/hex_weights/stem_sobel_weight.hex",
    parameter HEX_BIAS_SOBEL_FILE   = "rtl/classifier/hex_weights/stem_sobel_bias_s16.hex",
    parameter HEX_MULT_SOBEL_FILE   = "rtl/classifier/hex_weights/stem_sobel_mult.hex",

    parameter QSHIFT = 31
)(
    input  wire        clk,
    input  wire        rst_n,

    // ============================================================
    // INPUT WINDOW (16-bit: [15:8] Sobel, [7:0] Gray)
    // ============================================================
    input  wire        in_valid,
    output wire        in_ready,

    input  wire [15:0] p00, p01, p02,
    input  wire [15:0] p10, p11, p12,
    input  wire [15:0] p20, p21, p22,

    // ============================================================
    // OUTPUT SERIAL STREAM (Nối thẳng vào PW Expand của Block 1)
    // ============================================================
    output reg [7:0]   stem_out_pixel,
    output reg [7:0]   stem_out_ch_idx,
    output reg         out_valid,
    input  wire        out_ready
);
    localparam ST_IDLE     = 3'd0;
    localparam ST_MAC      = 3'd1;
    localparam ST_Q_GRAY   = 3'd2;
    localparam ST_OUT      = 3'd3;
    localparam ST_Q_SOBEL  = 3'd4;
    localparam integer REQUANT_HIGH_BIT = QSHIFT + 7;

    reg [2:0] state;

    // Bộ đệm cho Gray và Sobel riêng biệt
    reg [7:0] pix_gray  [0:8];
    reg [7:0] pix_sobel [0:8];

    // ROM chứa trọng số cho 12 kênh đầu ra (12 * 9 = 108 giá trị)
    reg signed [7:0]  weight_gray [0:107];
    reg signed [7:0]  weight_sobel[0:107];

    reg signed [15:0] bias_gray   [0:11];
    reg signed [15:0] bias_sobel  [0:11];

    reg signed [31:0] mult_gray   [0:11];
    reg signed [31:0] mult_sobel  [0:11];

    // Bộ đệm kênh ra: 24 kênh
    reg [7:0] channel_out [0:23];

    reg [3:0] ch_idx;   // Đếm từ 0 đến 11
    reg [3:0] tap_idx;  // Đếm từ 0 đến 8
    reg [4:0] send_idx; // Đếm từ 0 đến 23 cho đầu ra nối tiếp

    // Accumulators đôi
    // U8 input x S8 weight over 9 taps plus locked bias is <302k; 20-bit
    // signed accumulators suffice. q31_acc_mux remains 32-bit sign-extended.
    reg signed [19:0] acc_gray, acc_gray_next;
    reg signed [19:0] acc_sobel, acc_sobel_next;

    wire signed [31:0] gray_tap_product_full =
        $signed({24'd0, pix_gray[tap_idx]}) *
        $signed({{24{weight_gray[ch_idx*9 + tap_idx][7]}}, weight_gray[ch_idx*9 + tap_idx]});
    wire signed [31:0] sobel_tap_product_full =
        $signed({24'd0, pix_sobel[tap_idx]}) *
        $signed({{24{weight_sobel[ch_idx*9 + tap_idx][7]}}, weight_sobel[ch_idx*9 + tap_idx]});
    wire signed [19:0] gray_tap_product = gray_tap_product_full[19:0];
    wire signed [19:0] sobel_tap_product = sobel_tap_product_full[19:0];

    // A single shared Q31 multiplier is time-multiplexed between Gray and Sobel.
    // The state selects the corresponding accumulator and per-channel multiplier.
    reg signed [31:0] q31_acc_mux;
    reg signed [31:0] q31_mult_mux;
    wire signed [64:0] scaled_acc_shared;

    integer i;

    // Sẵn sàng nhận dữ liệu khi ở trạng thái nghỉ
    assign in_ready = (state == ST_IDLE);

    // ============================================================
    // KHỞI TẠO ROM (Tách biệt biến đếm để tránh xung đột 'X')
    // ============================================================
    initial begin : INIT_ROM
        // Load the LOCKED final Python INT8/S8 export.
        // Weight layout: [out_ch][3][3].
        // Bias/multiplier: one entry per output channel.
        $readmemh(HEX_WEIGHT_GRAY_FILE,  weight_gray);
        $readmemh(HEX_BIAS_GRAY_FILE,    bias_gray);
        $readmemh(HEX_MULT_GRAY_FILE,    mult_gray);
        $readmemh(HEX_WEIGHT_SOBEL_FILE, weight_sobel);
        $readmemh(HEX_BIAS_SOBEL_FILE,   bias_sobel);
        $readmemh(HEX_MULT_SOBEL_FILE,   mult_sobel);
    end

    // Bit-exact Q31 requantization for the existing ReLU clamp [0,127].
    // Negative products are immediately zeroed. Positive values at/above the
    // rounding-to-127 threshold saturate before the adder; otherwise only the
    // low QSHIFT+7 bits participate in rounding. QSHIFT=31 in this model.
    function [7:0] quantize_stem_relu6;
        input signed [64:0] product_in;
        reg [QSHIFT+6:0] rounded_positive;
        reg [QSHIFT+6:0] half_q;
        begin
            half_q = {{(QSHIFT+6){1'b0}}, 1'b1} << (QSHIFT-1);

            if (product_in[64]) begin
                quantize_stem_relu6 = 8'd0;
            end else if ((|product_in[63:REQUANT_HIGH_BIT]) ||
                         (product_in[QSHIFT+6:QSHIFT] == 7'd127) ||
                         ((product_in[QSHIFT+6:QSHIFT] == 7'd126) &&
                          product_in[QSHIFT-1])) begin
                quantize_stem_relu6 = 8'd127;
            end else begin
                rounded_positive = product_in[QSHIFT+6:0] + half_q;
                quantize_stem_relu6 = {1'b0, rounded_positive[QSHIFT+6:QSHIFT]};
            end
        end
    endfunction

    // Mux before the multiplier (not after it) so synthesis can share one
    // signed 32-bit x 32-bit Q31 product operator across the two channels.
    always @(*) begin
        if (state == ST_Q_SOBEL) begin
            q31_acc_mux  = acc_sobel;
            q31_mult_mux = mult_sobel[ch_idx];
        end else begin
            q31_acc_mux  = acc_gray;
            q31_mult_mux = mult_gray[ch_idx];
        end
    end

    assign scaled_acc_shared = $signed(q31_acc_mux) * $signed(q31_mult_mux);

    // ============================================================
    // MÁY TRẠNG THÁI (FSM)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            out_valid <= 1'b0;
            stem_out_pixel <= 8'd0;
            stem_out_ch_idx <= 7'd0;

            ch_idx <= 4'd0;
            tap_idx <= 4'd0;
            send_idx <= 5'd0;

            acc_gray <= 20'sd0; acc_gray_next <= 20'sd0;
            acc_sobel <= 20'sd0; acc_sobel_next <= 20'sd0;

            i = 0;
            for (i = 0; i < 24; i = i + 1) channel_out[i] <= 8'd0;
            for (i = 0; i < 9; i = i + 1) begin
                pix_gray[i] <= 8'd0;
                pix_sobel[i] <= 8'd0;
            end
        end else begin
            case (state)
                ST_IDLE: begin
                    if (in_valid && in_ready) begin
                        // Tách dữ liệu: 8 bit thấp là Gray, 8 bit cao là Sobel
                        pix_gray[0] <= p00[7:0]; pix_sobel[0] <= p00[15:8];
                        pix_gray[1] <= p01[7:0]; pix_sobel[1] <= p01[15:8];
                        pix_gray[2] <= p02[7:0]; pix_sobel[2] <= p02[15:8];
                        pix_gray[3] <= p10[7:0]; pix_sobel[3] <= p10[15:8];
                        pix_gray[4] <= p11[7:0]; pix_sobel[4] <= p11[15:8];
                        pix_gray[5] <= p12[7:0]; pix_sobel[5] <= p12[15:8];
                        pix_gray[6] <= p20[7:0]; pix_sobel[6] <= p20[15:8];
                        pix_gray[7] <= p21[7:0]; pix_sobel[7] <= p21[15:8];
                        pix_gray[8] <= p22[7:0]; pix_sobel[8] <= p22[15:8];

                        ch_idx <= 4'd0;
                        tap_idx <= 4'd0;
                        send_idx <= 5'd0;
                        
                        acc_gray  <= bias_gray[0];
                        acc_sobel <= bias_sobel[0];
                        state <= ST_MAC;
                    end
                end

                ST_MAC: begin
                    // Tính toán song song 2 bộ MAC
                    acc_gray_next = acc_gray + gray_tap_product;
                    acc_sobel_next = acc_sobel + sobel_tap_product;

                    if (tap_idx == 4'd8) begin
                        acc_gray <= acc_gray_next;
                        acc_sobel <= acc_sobel_next;
                        state <= ST_Q_GRAY;
                    end else begin
                        tap_idx <= tap_idx + 1'b1;
                        acc_gray <= acc_gray_next;
                        acc_sobel <= acc_sobel_next;
                    end
                end

                ST_Q_GRAY: begin
                    // Shared Q31 multiplier processes Gray during this cycle.
                    channel_out[ch_idx] <= quantize_stem_relu6(scaled_acc_shared);

                    // Next cycle reuses the same multiplier for Sobel.
                    state <= ST_Q_SOBEL;
                end

                ST_Q_SOBEL: begin
                    // Same multiplier, now selected to use acc_sobel and mult_sobel.
                    channel_out[ch_idx + 12] <= quantize_stem_relu6(scaled_acc_shared);

                    if (ch_idx == 4'd11) begin
                        // All 24 channel values are now stored; start serial output.
                        state <= ST_OUT;
                        send_idx <= 5'd0;
                        stem_out_pixel <= channel_out[0];
                        stem_out_ch_idx <= 7'd0;
                        out_valid <= 1'b1;
                    end else begin
                        ch_idx <= ch_idx + 1'b1;
                        tap_idx <= 4'd0;
                        acc_gray <= bias_gray[ch_idx + 1'b1];
                        acc_sobel <= bias_sobel[ch_idx + 1'b1];
                        state <= ST_MAC;
                    end
                end

                ST_OUT: begin
                    out_valid <= 1'b1;

                    // Khối này chỉ đẩy dữ liệu đi khi ngõ nhận (PW Expand) sẵn sàng
                    if (out_ready) begin
                        if (send_idx == 5'd23) begin
                            out_valid <= 1'b0;
                            state <= ST_IDLE; // Kết thúc chu trình, quay về đợi cửa sổ mới
                        end else begin
                            send_idx <= send_idx + 1'b1;
                            // Nạp trước dữ liệu của kênh tiếp theo để xuất ở nhịp clock tới
                            stem_out_pixel <= channel_out[send_idx + 1'b1];
                            stem_out_ch_idx <= {2'b00, send_idx} + 1'b1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule