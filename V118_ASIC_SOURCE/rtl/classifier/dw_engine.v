module dw_engine #(
    // ------------------------------------------------------------------------
    // Weight, Bias, Mult Files cho 7 Blocks
    // ------------------------------------------------------------------------
    parameter B1_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b1_dw_weight.hex",

    parameter B1_BIAS_FILE =
        "rtl/classifier/hex_weights/b1_dw_bias_s16.hex",

    parameter B1_MULT_FILE =
        "rtl/classifier/hex_weights/b1_dw_mult.hex",

    parameter B2_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b2_dw_weight.hex",

    parameter B2_BIAS_FILE =
        "rtl/classifier/hex_weights/b2_dw_bias_s16.hex",

    parameter B2_MULT_FILE =
        "rtl/classifier/hex_weights/b2_dw_mult.hex",

    parameter B3_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b3_dw_weight.hex",

    parameter B3_BIAS_FILE =
        "rtl/classifier/hex_weights/b3_dw_bias_s16.hex",

    parameter B3_MULT_FILE =
        "rtl/classifier/hex_weights/b3_dw_mult.hex",

    parameter B4_WEIGHT_FILE =
        "rtl/classifier/hex_weights/b4_dw_weight.hex",

    parameter B4_BIAS_FILE =
        "rtl/classifier/hex_weights/b4_dw_bias_s16.hex",

    parameter B4_MULT_FILE =
        "rtl/classifier/hex_weights/b4_dw_mult.hex",

    parameter B5_WEIGHT_FILE = "rtl/classifier/hex_weights/b5_dw_weight.hex",
    parameter B5_BIAS_FILE   = "rtl/classifier/hex_weights/b5_dw_bias_s16.hex",
    parameter B5_MULT_FILE   = "rtl/classifier/hex_weights/b5_dw_mult.hex",

    parameter B6_WEIGHT_FILE = "rtl/classifier/hex_weights/b6_dw_weight.hex",
    parameter B6_BIAS_FILE   = "rtl/classifier/hex_weights/b6_dw_bias_s16.hex",
    parameter B6_MULT_FILE   = "rtl/classifier/hex_weights/b6_dw_mult.hex",

    parameter B7_WEIGHT_FILE = "rtl/classifier/hex_weights/b7_dw_weight.hex",
    parameter B7_BIAS_FILE   = "rtl/classifier/hex_weights/b7_dw_bias_s16.hex",
    parameter B7_MULT_FILE   = "rtl/classifier/hex_weights/b7_dw_mult.hex",

    parameter DW_PACKED_WEIGHT_FILE =
        "rtl/classifier/hex_weights/dw_weight_packed72.hex",
    parameter QSHIFT         = 31,
    parameter PARALLEL_TAP   = 3
)(
    input  wire        clk,
    input  wire        rst_n,

    // 3-bit cho 7 Blocks (0=B1, 1=B2, 2=B3, 3=B4, 4=B5, 5=B6, 6=B7)
    input  wire [2:0]  block_sel,

    input  wire        in_valid,
    input  wire [7:0]  p00, p01, p02,
    input  wire [7:0]  p10, p11, p12,
    input  wire [7:0]  p20, p21, p22,
    input  wire [7:0]  in_ch_idx,

    output reg         ready,
    output reg [7:0]   dw_out,
    output reg [7:0]   out_ch_idx,
    output reg         out_valid,
    input  wire        out_ready,
    output reg         busy
);

    localparam integer TAP_GROUPS = (9 + PARALLEL_TAP - 1) / PARALLEL_TAP;

    localparam [2:0]
        ST_RX      = 3'd0,
        ST_MAC0    = 3'd1,
        ST_MAC1    = 3'd2,
        ST_MAC2    = 3'd3,
        ST_REQUANT = 3'd4,
        ST_OUTPUT  = 3'd5;

    reg [2:0] state;
    reg [2:0] active_block;
    reg [8:0] current_ch;

    reg [7:0] pixel_buf [0:8];

    // ========================================================================
    // Khai báo Mảng ROM chứa Trọng số, Bias, Mult cho 7 Blocks
    // Sức chứa tính toán theo số kênh Expand tối đa mỗi block * 9 tap
    // ========================================================================
    localparam integer DW_WEIGHT_WORDS = 736;
    // One 72-bit word contains tap0 in [7:0] through tap8 in [71:64].
    (* ramstyle = "M10K" *) reg [71:0] dw_weight_rom [0:DW_WEIGHT_WORDS-1];
    reg [71:0] dw_weight_q;

    reg signed [15:0] b1_bias [0:47];   reg signed [31:0] b1_mult [0:0];
    reg signed [15:0] b2_bias [0:47];   reg signed [31:0] b2_mult [0:0];
    reg signed [15:0] b3_bias [0:63];   reg signed [31:0] b3_mult [0:0];
    reg signed [15:0] b4_bias [0:63];   reg signed [31:0] b4_mult [0:0];
    reg signed [15:0] b5_bias [0:127];  reg signed [31:0] b5_mult [0:0];
    reg signed [15:0] b6_bias [0:127];  reg signed [31:0] b6_mult [0:0];
    reg signed [15:0] b7_bias [0:255];  reg signed [31:0] b7_mult [0:0];

    wire signed [7:0] weight_tap0 = dw_weight_q[7:0];
    wire signed [7:0] weight_tap1 = dw_weight_q[15:8];
    wire signed [7:0] weight_tap2 = dw_weight_q[23:16];
    wire signed [7:0] weight_tap3 = dw_weight_q[31:24];
    wire signed [7:0] weight_tap4 = dw_weight_q[39:32];
    wire signed [7:0] weight_tap5 = dw_weight_q[47:40];
    wire signed [7:0] weight_tap6 = dw_weight_q[55:48];
    wire signed [7:0] weight_tap7 = dw_weight_q[63:56];
    wire signed [7:0] weight_tap8 = dw_weight_q[71:64];
    // DSP optimization: reuse three narrow 9x8 multipliers across the
    // existing ST_MAC0/ST_MAC1/ST_MAC2 states. The original code built nine
    // parallel products although the FSM consumed only three per cycle.
    reg signed [15:0] tap_prod0, tap_prod1, tap_prod2;
    reg signed [17:0] prod_sum;
    // Worst-case unsigned-byte pixel x signed-byte weight over 9 taps plus
    // locked bias is < 300k, so signed 20 bits are sufficient.
    reg signed [19:0] accum, accum_next;
    reg signed [31:0] current_mult;

    reg signed [63:0] scaled_acc;
    wire signed [31:0] accum_for_q31 = {{12{accum[19]}}, accum};
    integer i;
    localparam integer REQUANT_HIGH_BIT = QSHIFT + 7;

    // Exact Q31/ReLU6 quantizer. Since negative values are clamped to zero,
    // don't build absolute-value or negative-rounding logic. Saturation is
    // detected before the narrow rounding adder, as in STEM/EXPAND/HEAD V1.
    function [7:0] quantize_dw_relu6;
        input signed [63:0] product_in;
        reg [QSHIFT+6:0] rounded_positive;
        reg [QSHIFT+6:0] half_q;
        begin
            half_q = {{(QSHIFT+6){1'b0}}, 1'b1} << (QSHIFT-1);
            if (product_in[63]) begin
                quantize_dw_relu6 = 8'd0;
            end else if ((|product_in[63:REQUANT_HIGH_BIT]) ||
                         (product_in[QSHIFT+6:QSHIFT] == 7'd127) ||
                         ((product_in[QSHIFT+6:QSHIFT] == 7'd126) && product_in[QSHIFT-1])) begin
                quantize_dw_relu6 = 8'd127;
            end else begin
                rounded_positive = product_in[QSHIFT+6:0] + half_q;
                quantize_dw_relu6 = {1'b0, rounded_positive[QSHIFT+6:QSHIFT]};
            end
        end
    endfunction

    // ========================================================================
    // Nạp dữ liệu Hex cho tất cả các Block
    // ========================================================================
    initial begin
        $readmemh(DW_PACKED_WEIGHT_FILE, dw_weight_rom, 0, DW_WEIGHT_WORDS-1);
        $readmemh(B1_BIAS_FILE, b1_bias); $readmemh(B1_MULT_FILE, b1_mult, 0, 0);
        $readmemh(B2_BIAS_FILE, b2_bias); $readmemh(B2_MULT_FILE, b2_mult, 0, 0);
        $readmemh(B3_BIAS_FILE, b3_bias); $readmemh(B3_MULT_FILE, b3_mult, 0, 0);
        $readmemh(B4_BIAS_FILE, b4_bias); $readmemh(B4_MULT_FILE, b4_mult, 0, 0);
        $readmemh(B5_BIAS_FILE, b5_bias); $readmemh(B5_MULT_FILE, b5_mult, 0, 0);
        $readmemh(B6_BIAS_FILE, b6_bias); $readmemh(B6_MULT_FILE, b6_mult, 0, 0);
        $readmemh(B7_BIAS_FILE, b7_bias); $readmemh(B7_MULT_FILE, b7_mult, 0, 0);

    end

    // ========================================================================
    // Shared narrow MAC multipliers
    //
    // IMPORTANT RESOURCE FIX:
    // Select the three pixel/weight operand pairs FIRST, then instantiate
    // exactly three multiplication expressions below. Do not place separate
    // multiplication expressions inside each ST_MAC case branch: that coding
    // style can infer nine parallel products (3 per state) and raise DSP use.
    //
    // ST_MAC0 selects taps 0..2, ST_MAC1 taps 3..5, ST_MAC2 taps 6..8.
    // Each product remains U8 x S8 and fits exactly in signed 16 bits.
    // ========================================================================
    reg [7:0]         tap_pixel0, tap_pixel1, tap_pixel2;
    reg signed [7:0]  tap_weight0, tap_weight1, tap_weight2;

    always @(*) begin
        case (state)
            ST_MAC0: begin
                tap_pixel0 = pixel_buf[0]; tap_pixel1 = pixel_buf[1]; tap_pixel2 = pixel_buf[2];
                tap_weight0 = weight_tap0; tap_weight1 = weight_tap1; tap_weight2 = weight_tap2;
            end
            ST_MAC1: begin
                tap_pixel0 = pixel_buf[3]; tap_pixel1 = pixel_buf[4]; tap_pixel2 = pixel_buf[5];
                tap_weight0 = weight_tap3; tap_weight1 = weight_tap4; tap_weight2 = weight_tap5;
            end
            ST_MAC2: begin
                tap_pixel0 = pixel_buf[6]; tap_pixel1 = pixel_buf[7]; tap_pixel2 = pixel_buf[8];
                tap_weight0 = weight_tap6; tap_weight1 = weight_tap7; tap_weight2 = weight_tap8;
            end
            default: begin
                tap_pixel0 = 8'd0; tap_pixel1 = 8'd0; tap_pixel2 = 8'd0;
                tap_weight0 = 8'sd0; tap_weight1 = 8'sd0; tap_weight2 = 8'sd0;
            end
        endcase

        // Exactly three shared U8 x S8 multipliers, used over the existing
        // three MAC cycles. These expressions are intentionally outside case.
        tap_prod0 = $signed({1'b0, tap_pixel0}) * $signed(tap_weight0);
        tap_prod1 = $signed({1'b0, tap_pixel1}) * $signed(tap_weight1);
        tap_prod2 = $signed({1'b0, tap_pixel2}) * $signed(tap_weight2);

        // The exact sum of three signed 8x8 products fits in signed 18 bits.
        // Keep the narrow tree out of the 32-bit accumulator adder path.
        prod_sum = $signed({{2{tap_prod0[15]}}, tap_prod0})
                 + $signed({{2{tap_prod1[15]}}, tap_prod1})
                 + $signed({{2{tap_prod2[15]}}, tap_prod2});
    end

    // Packed per-channel kernel offsets in the combined DW ROM.
    function [9:0] dw_weight_address;
        input [2:0] block_id;
        input [8:0] ch;
        begin
            case (block_id)
                3'd0: dw_weight_address = 10'd0   + ch;
                3'd1: dw_weight_address = 10'd48  + ch;
                3'd2: dw_weight_address = 10'd96  + ch;
                3'd3: dw_weight_address = 10'd160 + ch;
                3'd4: dw_weight_address = 10'd224 + ch;
                3'd5: dw_weight_address = 10'd352 + ch;
                3'd6: dw_weight_address = 10'd480 + ch;
                default: dw_weight_address = 10'd0;
            endcase
        end
    endfunction

    // Synchronous read is timed on the same accepted RX edge that starts
    // ST_MAC0. The registered 72-bit kernel is available throughout MAC0..2.
    always @(posedge clk) begin
        if (rst_n && state == ST_RX && in_valid && ready)
            dw_weight_q <= dw_weight_rom[dw_weight_address(block_sel, {1'b0,in_ch_idx})];
    end

    // Chọn hệ số lượng tử hóa (Multiplier) theo Block hiện hành
    always @(*) begin
        case (active_block)
            3'd0: current_mult = b1_mult[0];
            3'd1: current_mult = b2_mult[0];
            3'd2: current_mult = b3_mult[0];
            3'd3: current_mult = b4_mult[0];
            3'd4: current_mult = b5_mult[0];
            3'd5: current_mult = b6_mult[0];
            3'd6: current_mult = b7_mult[0];
            default: current_mult = 32'sd0;
        endcase
    end


    // ========================================================================
    // Main FSM - valid is held until out_ready.
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RX;
            active_block <= 3'd0;
            current_ch <= 9'd0;
            ready <= 1'b1;
            busy <= 1'b0;
            dw_out <= 8'd0;
            out_ch_idx <= 8'd0;
            out_valid <= 1'b0;
            accum <= 20'sd0;
            accum_next <= 20'sd0;
            scaled_acc <= 64'sd0;
            for (i = 0; i < 9; i = i + 1)
                pixel_buf[i] <= 8'd0;
        end else begin
            case (state)
                ST_RX: begin
                    ready <= 1'b1;
                    busy <= 1'b0;
                    out_valid <= 1'b0;

                    if (in_valid && ready) begin
                        pixel_buf[0] <= p00; pixel_buf[1] <= p01; pixel_buf[2] <= p02;
                        pixel_buf[3] <= p10; pixel_buf[4] <= p11; pixel_buf[5] <= p12;
                        pixel_buf[6] <= p20; pixel_buf[7] <= p21; pixel_buf[8] <= p22;

                        active_block <= block_sel;
                        current_ch <= {1'b0,in_ch_idx};

                        case (block_sel)
                            3'd0: accum <= b1_bias[in_ch_idx];
                            3'd1: accum <= b2_bias[in_ch_idx];
                            3'd2: accum <= b3_bias[in_ch_idx];
                            3'd3: accum <= b4_bias[in_ch_idx];
                            3'd4: accum <= b5_bias[in_ch_idx];
                            3'd5: accum <= b6_bias[in_ch_idx];
                            3'd6: accum <= b7_bias[in_ch_idx];
                            default: accum <= 20'sd0;
                        endcase

                        ready <= 1'b0;
                        busy <= 1'b1;
                        state <= ST_MAC0;
                    end
                end

                ST_MAC0: begin
                    ready <= 1'b0; busy <= 1'b1;
                    accum_next = accum + prod_sum;
                    accum <= accum_next;
                    state <= ST_MAC1;
                end

                ST_MAC1: begin
                    ready <= 1'b0; busy <= 1'b1;
                    accum_next = accum + prod_sum;
                    accum <= accum_next;
                    state <= ST_MAC2;
                end

                ST_MAC2: begin
                    ready <= 1'b0; busy <= 1'b1;
                    accum_next = accum + prod_sum;
                    accum <= accum_next;
                    state <= ST_REQUANT;
                end

                ST_REQUANT: begin
                    ready <= 1'b0; busy <= 1'b1;

                    // ----------------------------------------------------
                    // Python reference: symmetric Q31 rounding
                    //   y = sign(n) * floor((abs(n)+2^30)/2^31)
                    // ----------------------------------------------------
                    scaled_acc = $signed(accum_for_q31) * $signed(current_mult);
                    // Conv-BN-ReLU6: negative values are zero regardless of
                    // their rounded magnitude. Keep only the positive Q31 path.
                    dw_out <= quantize_dw_relu6(scaled_acc);

                    out_ch_idx <= current_ch[7:0];
                    state <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    ready <= 1'b0;
                    busy <= 1'b1;
                    out_valid <= 1'b1;

                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                        ready <= 1'b1;
                        busy <= 1'b0;
                        state <= ST_RX;
                    end
                end

                default: state <= ST_RX;
            endcase
        end
    end
endmodule