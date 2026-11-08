// -----------------------------------------------------------------------------
// Sobel 96x96 wrapper for the existing RGB565 crop BRAM.
//
// The arithmetic itself is intentionally NOT reimplemented here.  This wrapper
// instantiates the user-provided golden modules:
//   * rgb_to_grayscale
//   * sobel_convolution
//
// Border policy: x=0/95 or y=0/95 is written as 8'h00 so the classifier always
// receives an exact 96x96x1 UINT8 image (9216 bytes).
// -----------------------------------------------------------------------------
module sobel96_engine (
    input  logic        clk_i,
    input  logic        rstn_i,

    input  logic        start_i,
    output logic        busy_o,
    output logic        done_o,

    // Synchronous RGB565 read port from image96_bram.
    output logic [13:0] rgb_rd_addr_o,
    input  logic [15:0] rgb_rd_data_i,

    // 8-bit Sobel output write port.
    output logic        sobel_wr_en_o,
    output logic [13:0] sobel_wr_addr_o,
    output logic [7:0]  sobel_wr_data_o
);
    localparam integer IMG_W = 96;
    localparam integer IMG_H = 96;

    typedef enum logic [3:0] {
        S_IDLE,
        S_CHECK,
        S_READ_REQ,
        S_READ_WAIT,
        S_CAPTURE,
        S_COMPUTE,
        S_WRITE,
        S_NEXT,
        S_DONE
    } state_t;

    state_t state_r;

    logic [6:0] x_r;
    logic [6:0] y_r;
    logic [3:0] tap_r;

    logic [7:0] p00_r, p01_r, p02_r;
    logic [7:0] p10_r, p11_r, p12_r;
    logic [7:0] p20_r, p21_r, p22_r;

    wire [7:0] gray_from_rgb;
    wire signed [11:0] gradient_x_unused;
    wire signed [11:0] gradient_y_unused;
    wire [7:0] sobel_magnitude;

    // 96*y + x = (64+32)*y + x.  No multiplier/divider is inferred.
    function automatic [13:0] addr96;
        input [6:0] x;
        input [6:0] y;
        reg [13:0] yy;
        begin
            yy = {7'd0, y};
            addr96 = (yy << 6) + (yy << 5) + {7'd0, x};
        end
    endfunction

    // Golden RGB565 -> grayscale arithmetic supplied by the user.
    rgb_to_grayscale u_rgb_to_grayscale (
        .rgb_data  (rgb_rd_data_i),
        .gray_data (gray_from_rgb)
    );

    // Golden Sobel arithmetic supplied by the user.
    sobel_convolution u_sobel_convolution (
        .gradient_x (gradient_x_unused),
        .gradient_y (gradient_y_unused),
        .magnitude  (sobel_magnitude),

        .pixel_00 (p00_r), .pixel_01 (p01_r), .pixel_02 (p02_r),
        .pixel_10 (p10_r), .pixel_11 (p11_r), .pixel_12 (p12_r),
        .pixel_20 (p20_r), .pixel_21 (p21_r), .pixel_22 (p22_r)
    );

    // Address of the currently requested tap.  All requests in this branch are
    // interior pixels, so x_r/y_r +/- 1 cannot underflow or overflow.
    always_comb begin
        case (tap_r)
            4'd0: rgb_rd_addr_o = addr96(x_r - 7'd1, y_r - 7'd1);
            4'd1: rgb_rd_addr_o = addr96(x_r,         y_r - 7'd1);
            4'd2: rgb_rd_addr_o = addr96(x_r + 7'd1, y_r - 7'd1);
            4'd3: rgb_rd_addr_o = addr96(x_r - 7'd1, y_r);
            4'd4: rgb_rd_addr_o = addr96(x_r,         y_r);
            4'd5: rgb_rd_addr_o = addr96(x_r + 7'd1, y_r);
            4'd6: rgb_rd_addr_o = addr96(x_r - 7'd1, y_r + 7'd1);
            4'd7: rgb_rd_addr_o = addr96(x_r,         y_r + 7'd1);
            default: rgb_rd_addr_o = addr96(x_r + 7'd1, y_r + 7'd1);
        endcase
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r         <= S_IDLE;
            x_r             <= 7'd0;
            y_r             <= 7'd0;
            tap_r           <= 4'd0;
            p00_r           <= 8'd0;
            p01_r           <= 8'd0;
            p02_r           <= 8'd0;
            p10_r           <= 8'd0;
            p11_r           <= 8'd0;
            p12_r           <= 8'd0;
            p20_r           <= 8'd0;
            p21_r           <= 8'd0;
            p22_r           <= 8'd0;
            busy_o          <= 1'b0;
            done_o          <= 1'b0;
            sobel_wr_en_o   <= 1'b0;
            sobel_wr_addr_o <= 14'd0;
            sobel_wr_data_o <= 8'd0;
        end else begin
            done_o        <= 1'b0;
            sobel_wr_en_o <= 1'b0;

            case (state_r)
                S_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        x_r     <= 7'd0;
                        y_r     <= 7'd0;
                        tap_r   <= 4'd0;
                        busy_o  <= 1'b1;
                        state_r <= S_CHECK;
                    end
                end

                S_CHECK: begin
                    if ((x_r == 7'd0) || (x_r == 7'd95) ||
                        (y_r == 7'd0) || (y_r == 7'd95)) begin
                        sobel_wr_en_o   <= 1'b1;
                        sobel_wr_addr_o <= addr96(x_r, y_r);
                        sobel_wr_data_o <= 8'h00;
                        state_r         <= S_NEXT;
                    end else begin
                        tap_r   <= 4'd0;
                        state_r <= S_READ_REQ;
                    end
                end

                // image96_bram uses a registered address on its read port.
                // Keep an explicit wait state so the returned RGB565 word is
                // stable before the grayscale value is captured.
                S_READ_REQ:  state_r <= S_READ_WAIT;
                S_READ_WAIT: state_r <= S_CAPTURE;

                S_CAPTURE: begin
                    case (tap_r)
                        4'd0: p00_r <= gray_from_rgb;
                        4'd1: p01_r <= gray_from_rgb;
                        4'd2: p02_r <= gray_from_rgb;
                        4'd3: p10_r <= gray_from_rgb;
                        4'd4: p11_r <= gray_from_rgb;
                        4'd5: p12_r <= gray_from_rgb;
                        4'd6: p20_r <= gray_from_rgb;
                        4'd7: p21_r <= gray_from_rgb;
                        4'd8: p22_r <= gray_from_rgb;
                        default: ;
                    endcase

                    if (tap_r == 4'd8) begin
                        state_r <= S_COMPUTE;
                    end else begin
                        tap_r   <= tap_r + 4'd1;
                        state_r <= S_READ_REQ;
                    end
                end

                // One explicit cycle lets the final p22 nonblocking assignment
                // settle before sobel_magnitude is sampled in S_WRITE.
                S_COMPUTE: state_r <= S_WRITE;

                S_WRITE: begin
                    sobel_wr_en_o   <= 1'b1;
                    sobel_wr_addr_o <= addr96(x_r, y_r);
                    sobel_wr_data_o <= sobel_magnitude;
                    state_r         <= S_NEXT;
                end

                S_NEXT: begin
                    if (x_r == 7'd95) begin
                        x_r <= 7'd0;
                        if (y_r == 7'd95) begin
                            state_r <= S_DONE;
                        end else begin
                            y_r     <= y_r + 7'd1;
                            state_r <= S_CHECK;
                        end
                    end else begin
                        x_r     <= x_r + 7'd1;
                        state_r <= S_CHECK;
                    end
                end

                S_DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    state_r <= S_IDLE;
                end

                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
