// V6.0.5: M10K synchronous-read FIFO with a DATA_READ / DATA_SEND schedule.
// Deliberately one buffered pixel per 2 cycles; no changes to quantization or
// the 320 x 256 output raster (top/bottom padding remains 8 rows each).
module camera_preprocess_320x256 #(
    parameter integer FIFO_DEPTH = 1024
)(
    input logic clk_i, rstn_i, cam_start_frame_i, cam_pixel_valid_i,
    input logic [15:0] cam_rgb565_i,
    output logic pixel_valid_o,
    output logic [23:0] pixel_ycbcr_o,
    output logic frame_done_o, busy_o, fifo_overflow_o
);
    localparam logic [23:0] PAD_PIXEL = 24'h008080;
    localparam integer TOP_PIX = 2560;
    localparam integer DATA_PIX = 76800;
    localparam integer BOT_PIX = 2560;
    localparam integer PW = $clog2(FIFO_DEPTH);

    // V6.23 timing: break the 50 MHz RGB565->YCbCr->2x2 scaler
    // combinational path at a registered boundary.  Preserve every valid
    // sample and its order; the 2x2 scaler receives the same pixels, just
    // one clock later.  No DSP/weight/quantization changes.
    logic [23:0] conv, sp;
    logic [23:0] conv_pipe_q;
    logic        conv_valid_q;
    logic sv, sl;
    rgb565_to_ycbcr u0 (.rgb565_i(cam_rgb565_i), .ycbcr_o(conv));

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            conv_pipe_q <= 24'd0;
            conv_valid_q <= 1'b0;
        end else begin
            // A frame-start pulse discards the preceding frame's pending
            // sample, matching the scaler's existing start priority.
            conv_pipe_q <= conv;
            conv_valid_q <= cam_pixel_valid_i && !cam_start_frame_i;
        end
    end

    area_scaler_2x2 u1 (
        .clk_i(clk_i), .rstn_i(rstn_i), .start_i(cam_start_frame_i),
        .pixel_valid_i(conv_valid_q), .pixel_ycbcr_i(conv_pipe_q),
        .pixel_valid_o(sv), .pixel_ycbcr_o(sp), .pixel_last_o(sl)
    );

    (* ramstyle = "M10K" *) logic [23:0] fifo [0:FIFO_DEPTH-1];
    logic [23:0] fifo_read_q;
    logic [PW-1:0] wp, rp;
    logic [PW:0] fc;
    logic [11:0] pc;
    logic [16:0] dc;
    typedef enum logic [2:0] {IDLE, TOP, DATA_READ, DATA_SEND, BOT} st_t;
    st_t st;

    // Both RAM ports live in reset-free sequential processes, enabling
    // true Cyclone V Simple Dual Port inference instead of a bank of FFs.
    wire fifo_push = rstn_i && !cam_start_frame_i && sv &&
                    (((st == TOP) && (fc < FIFO_DEPTH)) ||
                     ((st == DATA_READ) && (fc != 0) && (fc < FIFO_DEPTH)) ||
                     ((st == DATA_SEND) && (fc < FIFO_DEPTH)));
    always_ff @(posedge clk_i) begin
        if (fifo_push) fifo[wp] <= sp;
        if (rstn_i && !cam_start_frame_i && st == DATA_READ && fc != 0)
            fifo_read_q <= fifo[rp];
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            st <= IDLE;
            pixel_valid_o <= 0; pixel_ycbcr_o <= 0;
            frame_done_o <= 0; busy_o <= 0; fifo_overflow_o <= 0;
            wp <= 0; rp <= 0; fc <= 0; pc <= 0; dc <= 0;
        end else begin
            pixel_valid_o <= 0;
            frame_done_o <= 0;
            if (cam_start_frame_i) begin
                st <= TOP; busy_o <= 1; fifo_overflow_o <= 0;
                wp <= 0; rp <= 0; fc <= 0; pc <= 0; dc <= 0;
            end else begin
                case (st)
                    IDLE: busy_o <= 0;
                    TOP: begin
                        pixel_valid_o <= 1;
                        pixel_ycbcr_o <= PAD_PIXEL;
                        if (sv) begin
                            if (fc < FIFO_DEPTH) begin
                                wp <= wp + 1'b1;
                                fc <= fc + 1'b1;
                            end else fifo_overflow_o <= 1;
                        end
                        if (pc == TOP_PIX-1) begin
                            pc <= 0; st <= DATA_READ;
                        end else pc <= pc + 1'b1;
                    end
                    DATA_READ: begin
                        if (fc != 0) begin
                            // Request an M10K synchronous read. DATA_SEND will
                            // consume fifo_read_q on the following clock.
                            rp <= rp + 1'b1;
                            st <= DATA_SEND;
                            if (sv && fc < FIFO_DEPTH) begin
                                wp <= wp + 1'b1;
                                // simultaneous enqueue/dequeue; fc unchanged
                            end else begin
                                fc <= fc - 1'b1;
                                if (sv) fifo_overflow_o <= 1;
                            end
                        end else if (sv) begin
                            // Empty FIFO: directly bypass the source pixel.
                            pixel_valid_o <= 1;
                            pixel_ycbcr_o <= sp;
                            if (dc == DATA_PIX-1) begin
                                dc <= 0; st <= BOT;
                            end else dc <= dc + 1'b1;
                        end
                    end
                    DATA_SEND: begin
                        pixel_valid_o <= 1;
                        pixel_ycbcr_o <= fifo_read_q;
                        if (sv) begin
                            if (fc < FIFO_DEPTH) begin
                                wp <= wp + 1'b1;
                                fc <= fc + 1'b1;
                            end else fifo_overflow_o <= 1;
                        end
                        if (dc == DATA_PIX-1) begin
                            dc <= 0; st <= BOT;
                        end else begin
                            dc <= dc + 1'b1; st <= DATA_READ;
                        end
                    end
                    BOT: begin
                        pixel_valid_o <= 1;
                        pixel_ycbcr_o <= PAD_PIXEL;
                        if (pc == BOT_PIX-1) begin
                            pc <= 0; st <= IDLE; busy_o <= 0;
                            frame_done_o <= 1;
                        end else pc <= pc + 1'b1;
                    end
                    default: st <= IDLE;
                endcase
            end
        end
    end
endmodule
