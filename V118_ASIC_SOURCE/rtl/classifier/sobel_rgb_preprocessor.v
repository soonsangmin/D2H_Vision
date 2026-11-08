`timescale 1ns/1ps
`default_nettype none

// Timing-oriented implementation of RGB565 -> Gray + Sobel.
//
// Keeps the external interface and pixel function of
// sobel_rgb_preprocessor_current_dual_output.sv:
//   * RGB565 -> exact Gray using rgb_to_grayscale
//   * 3 grayscale row buffers
//   * 3x3 Sobel, zero-padded image borders
//   * magnitude = min(abs(Gx) + abs(Gy), 255)
//   * Gray and Sobel output are aligned and share pixel_valid/pixel_ready
//
// Timing change:
//   The old path was send_col -> 3x3 row-bank/column mux -> Sobel Gx/Gy
//   arithmetic -> absolute values -> magnitude/saturation -> out_pixel_reg.
//   This version registers the column addresses, reads physical row banks in
//   their own stage, selects the 3x3 window, and pipelines the Sobel arithmetic.
//   The output value is unchanged, but pixels take more clocks to prepare.
module sobel_rgb_preprocessor #(
    parameter integer WIDTH  = 96,
    parameter integer HEIGHT = 96
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [15:0] rgb_data,
    input  wire        rgb_valid,
    output wire        rgb_ready,
    output wire [7:0]  pixel_out,
    output wire [7:0]  gray_out,
    output wire        pixel_valid,
    input  wire        pixel_ready,
    output wire        busy,
    output wire        done
);

    // State encoding is deliberately explicit for easier SignalTap debugging.
    localparam [3:0]
        S_IDLE         = 4'd0,
        S_RECEIVE      = 4'd1,
        S_PREP_COL     = 4'd2,
        S_READ_BANKS   = 4'd3,
        S_SELECT_WIN   = 4'd4,
        S_DIFF         = 4'd5,
        S_PARTIAL_SUM  = 4'd6,
        S_GRAD_SUM     = 4'd7,
        S_ABS          = 4'd8,
        S_MAG_SUM      = 4'd9,
        S_PUBLISH      = 4'd10,
        S_WAIT_PIXEL   = 4'd11,
        S_DONE         = 4'd12;

    reg [3:0] state;

    // Three 8-bit grayscale row buffers (same storage architecture).
    reg [7:0] row0 [0:WIDTH-1];
    reg [7:0] row1 [0:WIDTH-1];
    reg [7:0] row2 [0:WIDTH-1];

    reg [6:0] rx_row;
    reg [6:0] rx_col;
    reg [6:0] send_row;
    reg [6:0] send_col;

    reg [1:0] top_bank;
    reg [1:0] mid_bank;
    reg [1:0] bot_bank;
    reg       top_zero;
    reg       bot_zero;

    wire [7:0] gray_data;
    rgb_to_grayscale u_rgb_to_grayscale (
        .rgb_data  (rgb_data),
        .gray_data (gray_data)
    );

    // ------------------------------------------------------------------
    // Stage 0: register the three column addresses and edge-valid flags.
    // Saturating the addresses avoids out-of-range dynamic array indices;
    // left/right padding is represented separately by the valid flags.
    // ------------------------------------------------------------------
    reg [6:0] col_left_q;
    reg [6:0] col_center_q;
    reg [6:0] col_right_q;
    reg       col_left_valid_q;
    reg       col_right_valid_q;

    // ------------------------------------------------------------------
    // Stage 1: register all three horizontal taps from each physical row
    // bank. The bank selection is intentionally deferred to the next stage,
    // reducing the send_col -> row-buffer mux depth.
    // ------------------------------------------------------------------
    reg [7:0] row0_left_q, row0_center_q, row0_right_q;
    reg [7:0] row1_left_q, row1_center_q, row1_right_q;
    reg [7:0] row2_left_q, row2_center_q, row2_right_q;

    // ------------------------------------------------------------------
    // Stage 2: selected 3x3 window registers and aligned center Gray.
    // ------------------------------------------------------------------
    reg [7:0] p00_q, p01_q, p02_q;
    reg [7:0] p10_q, p11_q, p12_q;
    reg [7:0] p20_q, p21_q, p22_q;
    reg [7:0] gray_center_q;

    wire [7:0] top_left =
        (top_bank == 2'd0) ? row0_left_q :
        (top_bank == 2'd1) ? row1_left_q : row2_left_q;
    wire [7:0] top_center =
        (top_bank == 2'd0) ? row0_center_q :
        (top_bank == 2'd1) ? row1_center_q : row2_center_q;
    wire [7:0] top_right =
        (top_bank == 2'd0) ? row0_right_q :
        (top_bank == 2'd1) ? row1_right_q : row2_right_q;

    wire [7:0] mid_left =
        (mid_bank == 2'd0) ? row0_left_q :
        (mid_bank == 2'd1) ? row1_left_q : row2_left_q;
    wire [7:0] mid_center =
        (mid_bank == 2'd0) ? row0_center_q :
        (mid_bank == 2'd1) ? row1_center_q : row2_center_q;
    wire [7:0] mid_right =
        (mid_bank == 2'd0) ? row0_right_q :
        (mid_bank == 2'd1) ? row1_right_q : row2_right_q;

    wire [7:0] bot_left =
        (bot_bank == 2'd0) ? row0_left_q :
        (bot_bank == 2'd1) ? row1_left_q : row2_left_q;
    wire [7:0] bot_center =
        (bot_bank == 2'd0) ? row0_center_q :
        (bot_bank == 2'd1) ? row1_center_q : row2_center_q;
    wire [7:0] bot_right =
        (bot_bank == 2'd0) ? row0_right_q :
        (bot_bank == 2'd1) ? row1_right_q : row2_right_q;

    // ------------------------------------------------------------------
    // Sobel pipeline registers.
    // Difference is in [-255,255] (10-bit signed); twice-difference fits
    // in 10-bit signed; partial and final gradients fit in 11-bit signed.
    // ------------------------------------------------------------------
    reg signed [9:0] gx_a_q, gx_b_q, gx_c_q;
    reg signed [9:0] gy_a_q, gy_b_q, gy_c_q;

    reg signed [10:0] gx_part0_q, gx_part1_q;
    reg signed [10:0] gy_part0_q, gy_part1_q;
    reg signed [10:0] gx_q, gy_q;

    reg [10:0] abs_gx_q, abs_gy_q;
    reg [11:0] magnitude_sum_q;

    reg [7:0] out_pixel_reg;
    reg [7:0] out_gray_reg;
    reg       out_valid_reg;

    assign pixel_out   = out_pixel_reg;
    assign gray_out    = out_gray_reg;
    assign pixel_valid = out_valid_reg;

    assign rgb_ready = (state == S_RECEIVE);
    assign busy      = (state != S_IDLE) && (state != S_DONE);
    assign done      = (state == S_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rx_row <= 7'd0;
            rx_col <= 7'd0;
            send_row <= 7'd0;
            send_col <= 7'd0;

            top_bank <= 2'd0;
            mid_bank <= 2'd0;
            bot_bank <= 2'd0;
            top_zero <= 1'b0;
            bot_zero <= 1'b0;

            col_left_q <= 7'd0;
            col_center_q <= 7'd0;
            col_right_q <= 7'd0;
            col_left_valid_q <= 1'b0;
            col_right_valid_q <= 1'b0;

            row0_left_q <= 8'd0; row0_center_q <= 8'd0; row0_right_q <= 8'd0;
            row1_left_q <= 8'd0; row1_center_q <= 8'd0; row1_right_q <= 8'd0;
            row2_left_q <= 8'd0; row2_center_q <= 8'd0; row2_right_q <= 8'd0;

            p00_q <= 8'd0; p01_q <= 8'd0; p02_q <= 8'd0;
            p10_q <= 8'd0; p11_q <= 8'd0; p12_q <= 8'd0;
            p20_q <= 8'd0; p21_q <= 8'd0; p22_q <= 8'd0;
            gray_center_q <= 8'd0;

            gx_a_q <= 10'sd0; gx_b_q <= 10'sd0; gx_c_q <= 10'sd0;
            gy_a_q <= 10'sd0; gy_b_q <= 10'sd0; gy_c_q <= 10'sd0;
            gx_part0_q <= 11'sd0; gx_part1_q <= 11'sd0;
            gy_part0_q <= 11'sd0; gy_part1_q <= 11'sd0;
            gx_q <= 11'sd0; gy_q <= 11'sd0;
            abs_gx_q <= 11'd0; abs_gy_q <= 11'd0;
            magnitude_sum_q <= 12'd0;

            out_pixel_reg <= 8'd0;
            out_gray_reg <= 8'd0;
            out_valid_reg <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    out_valid_reg <= 1'b0;
                    if (frame_start) begin
                        rx_row <= 7'd0;
                        rx_col <= 7'd0;
                        send_row <= 7'd0;
                        send_col <= 7'd0;
                        state <= S_RECEIVE;
                    end
                end

                // Input pixel -> grayscale row ring.
                S_RECEIVE: begin
                    if (rgb_valid && rgb_ready) begin
                        case (rx_row % 3)
                            0: row0[rx_col] <= gray_data;
                            1: row1[rx_col] <= gray_data;
                            2: row2[rx_col] <= gray_data;
                            default: ;
                        endcase

                        if (rx_col == WIDTH-1) begin
                            rx_col <= 7'd0;
                            if (rx_row == 1) begin
                                // Rows 0 and 1 are ready; emit output row 0.
                                send_row <= 7'd0;
                                send_col <= 7'd0;
                                top_zero <= 1'b1;
                                bot_zero <= 1'b0;
                                top_bank <= 2'd0;
                                mid_bank <= 2'd0;
                                bot_bank <= 2'd1;
                                state <= S_PREP_COL;
                            end else if (rx_row >= 2) begin
                                // Input row N enables output center row N-1.
                                send_row <= rx_row - 1'b1;
                                send_col <= 7'd0;
                                top_zero <= 1'b0;
                                bot_zero <= 1'b0;
                                top_bank <= (rx_row - 2) % 3;
                                mid_bank <= (rx_row - 1) % 3;
                                bot_bank <= rx_row % 3;
                                state <= S_PREP_COL;
                            end else begin
                                // Row 0 complete: proceed to receive row 1.
                                rx_row <= 7'd1;
                            end
                        end else begin
                            rx_col <= rx_col + 1'b1;
                        end
                    end
                end

                // Split address calculation from row-buffer data selection.
                S_PREP_COL: begin
                    col_left_q <= (send_col == 0) ? 7'd0 : send_col - 1'b1;
                    col_center_q <= send_col;
                    col_right_q <= (send_col == WIDTH-1) ? send_col : send_col + 1'b1;
                    col_left_valid_q <= (send_col != 0);
                    col_right_valid_q <= (send_col != WIDTH-1);
                    state <= S_READ_BANKS;
                end

                // Physical-row muxes end at registers before bank selection.
                S_READ_BANKS: begin
                    row0_left_q   <= col_left_valid_q  ? row0[col_left_q]   : 8'h00;
                    row0_center_q <= row0[col_center_q];
                    row0_right_q  <= col_right_valid_q ? row0[col_right_q]  : 8'h00;

                    row1_left_q   <= col_left_valid_q  ? row1[col_left_q]   : 8'h00;
                    row1_center_q <= row1[col_center_q];
                    row1_right_q  <= col_right_valid_q ? row1[col_right_q]  : 8'h00;

                    row2_left_q   <= col_left_valid_q  ? row2[col_left_q]   : 8'h00;
                    row2_center_q <= row2[col_center_q];
                    row2_right_q  <= col_right_valid_q ? row2[col_right_q]  : 8'h00;
                    state <= S_SELECT_WIN;
                end

                // Select the three physical row banks in a separate stage.
                S_SELECT_WIN: begin
                    if (top_zero) begin
                        p00_q <= 8'h00; p01_q <= 8'h00; p02_q <= 8'h00;
                    end else begin
                        p00_q <= top_left; p01_q <= top_center; p02_q <= top_right;
                    end

                    p10_q <= mid_left; p11_q <= mid_center; p12_q <= mid_right;

                    if (bot_zero) begin
                        p20_q <= 8'h00; p21_q <= 8'h00; p22_q <= 8'h00;
                    end else begin
                        p20_q <= bot_left; p21_q <= bot_center; p22_q <= bot_right;
                    end

                    gray_center_q <= mid_center;
                    state <= S_DIFF;
                end

                // Gx = (p02-p00) + 2*(p12-p10) + (p22-p20)
                // Gy = (p00-p20) + 2*(p01-p21) + (p02-p22)
                S_DIFF: begin
                    gx_a_q <= $signed({2'b00, p02_q}) - $signed({2'b00, p00_q});
                    gx_b_q <= $signed({2'b00, p12_q}) - $signed({2'b00, p10_q});
                    gx_c_q <= $signed({2'b00, p22_q}) - $signed({2'b00, p20_q});

                    gy_a_q <= $signed({2'b00, p00_q}) - $signed({2'b00, p20_q});
                    gy_b_q <= $signed({2'b00, p01_q}) - $signed({2'b00, p21_q});
                    gy_c_q <= $signed({2'b00, p02_q}) - $signed({2'b00, p22_q});
                    state <= S_PARTIAL_SUM;
                end

                // First adder level: keep the doubled difference signed and wide.
                S_PARTIAL_SUM: begin
                    gx_part0_q <= $signed({gx_a_q[9], gx_a_q})
                                  + ($signed({gx_b_q[9], gx_b_q}) <<< 1);
                    gx_part1_q <= $signed({gx_c_q[9], gx_c_q});
                    gy_part0_q <= $signed({gy_a_q[9], gy_a_q})
                                  + ($signed({gy_b_q[9], gy_b_q}) <<< 1);
                    gy_part1_q <= $signed({gy_c_q[9], gy_c_q});
                    state <= S_GRAD_SUM;
                end

                // Second adder level: final signed gradients.
                S_GRAD_SUM: begin
                    gx_q <= gx_part0_q + gx_part1_q;
                    gy_q <= gy_part0_q + gy_part1_q;
                    state <= S_ABS;
                end

                S_ABS: begin
                    abs_gx_q <= gx_q[10] ? $unsigned(-gx_q) : $unsigned(gx_q);
                    abs_gy_q <= gy_q[10] ? $unsigned(-gy_q) : $unsigned(gy_q);
                    state <= S_MAG_SUM;
                end

                S_MAG_SUM: begin
                    magnitude_sum_q <= {1'b0, abs_gx_q} + {1'b0, abs_gy_q};
                    state <= S_PUBLISH;
                end

                // Short final path: compare/saturate a registered magnitude.
                S_PUBLISH: begin
                    out_pixel_reg <= (magnitude_sum_q > 12'd255)
                                   ? 8'hFF : magnitude_sum_q[7:0];
                    out_gray_reg <= gray_center_q;
                    out_valid_reg <= 1'b1;
                    state <= S_WAIT_PIXEL;
                end

                // Keep both output bytes stable while downstream is stalled.
                S_WAIT_PIXEL: begin
                    if (out_valid_reg && pixel_ready) begin
                        out_valid_reg <= 1'b0;
                        if (send_col == WIDTH-1) begin
                            send_col <= 7'd0;
                            if (send_row == HEIGHT-2) begin
                                // Now emit the final image row with zero bottom padding.
                                send_row <= HEIGHT-1;
                                top_zero <= 1'b0;
                                bot_zero <= 1'b1;
                                top_bank <= (HEIGHT-2) % 3;
                                mid_bank <= (HEIGHT-1) % 3;
                                state <= S_PREP_COL;
                            end else if (send_row == HEIGHT-1) begin
                                state <= S_DONE;
                            end else begin
                                // Read the next input row before producing the next output row.
                                rx_row <= send_row + 2;
                                rx_col <= 7'd0;
                                state <= S_RECEIVE;
                            end
                        end else begin
                            send_col <= send_col + 1'b1;
                            state <= S_PREP_COL;
                        end
                    end
                end

                S_DONE: begin
                    out_valid_reg <= 1'b0;
                    state <= S_DONE;
                end

                default: begin
                    state <= S_IDLE;
                    out_valid_reg <= 1'b0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
