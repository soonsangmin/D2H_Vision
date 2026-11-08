`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Streaming single-frame CNN IP wrapper with 3-row line buffers.
//
// External input:
//   frame_valid : rising edge starts one frame (one frame per reset).
//   pixel_valid/pixel_ready : streaming pixel handshake.
//   gray_pixel and sobel_pixel are separate 8-bit values at the same (row,col).
//   Input order: row-major, exactly FRAME_W*FRAME_H accepted pixel handshakes.
//
// Only three rows per input stream are buffered. There is NO full-frame store.
// The wrapper generates SAME-padded 3x3 windows and streams them directly to
// cnn_top_stream_b1_b2_stage2. It backpressures the pixel source whenever a
// generated window has not yet been accepted by the CNN.
//
// Window order is byte-ascending in each 72-bit bus:
//   [7:0]=p00, [15:8]=p01, ... [71:64]=p22.
// The scan emits exactly 96*96 windows, including zero-padding at all borders.
// ============================================================================
module cnn_top_ip (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       frame_valid,

    input  wire       pixel_valid,
    output wire       pixel_ready,
    input  wire [7:0] gray_pixel,
    input  wire [7:0] sobel_pixel,

    output reg  [2:0] predicted_class,
    output wire       done,

    // V6.1.1 DEBUG - observation-only taps (do not affect CNN handshake)
    output wire        debug_fc_valid_o,
    output wire [2:0]  debug_fc_index_o,
    output wire signed [31:0] debug_fc_value_o,
    output wire        debug_fc_frame_done_o,
    output wire [6:0]  debug_stage_mask_o,
    output wire [2:0]  debug_active_block_o
);

    // This MobileNet top is configured for a fixed 96x96 input frame.
    localparam integer FRAME_W = 96;
    localparam integer FRAME_H = 96;
    localparam [3:0]
        S_IDLE         = 4'd0,
        S_WAIT_CORE    = 4'd1,
        S_ACCEPT_PIXEL = 4'd2,
        S_PIXEL_WAIT   = 4'd3,
        S_SEND_WINDOW  = 4'd4,
        S_BOTTOM_READ  = 4'd5,
        S_BOTTOM_WAIT  = 4'd6,
        S_SEND_BOTTOM  = 4'd7,
        S_WAIT_DONE    = 4'd8,
        S_DONE         = 4'd9;

    reg [3:0] state;

    reg frame_valid_d;
    reg frame_started;
    reg start_pulse;

    reg [6:0] input_row;
    reg [6:0] input_col;
    reg [1:0] bank_sel;

    // Remember the input transaction while synchronous line-buffer reads settle.
    reg [6:0] saved_row;
    reg [6:0] saved_col;
    reg [1:0] saved_bank;
    reg [7:0] saved_gray_pixel;
    reg [7:0] saved_sobel_pixel;

    wire pixel_fire;
    wire core_stem_ready;
    wire core_done;
    wire core_busy;

    // Three physical line banks per stream. Each bank is only FRAME_W x 8 bits.
    // A bank is written for the current row and read for a prior row, never both
    // at the same time during the input phase. Let synthesis choose the best
    // small-memory implementation; these memories are deliberately not forced
    // into one full-frame RAM.
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] gray_line0  [0:FRAME_W-1];
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] gray_line1  [0:FRAME_W-1];
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] gray_line2  [0:FRAME_W-1];
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] sobel_line0 [0:FRAME_W-1];
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] sobel_line1 [0:FRAME_W-1];
    (* ramstyle = "MLAB", ram_style = "distributed" *) reg [7:0] sobel_line2 [0:FRAME_W-1];

    // One registered read-data signal per physical bank. Reusing the same
    // read-data register in input and bottom-flush phases keeps each line bank
    // to a single read port for RAM inference.
    reg [7:0] gray_line0_rd, gray_line1_rd, gray_line2_rd;
    reg [7:0] sobel_line0_rd, sobel_line1_rd, sobel_line2_rd;

    wire [7:0] gray_prev1_sample;
    wire [7:0] gray_prev2_sample;
    wire [7:0] sobel_prev1_sample;
    wire [7:0] sobel_prev2_sample;

    assign gray_prev1_sample = (saved_row < 1) ? 8'd0 :
                               (saved_bank == 2'd0) ? gray_line2_rd :
                               (saved_bank == 2'd1) ? gray_line0_rd : gray_line1_rd;
    assign gray_prev2_sample = (saved_row < 2) ? 8'd0 :
                               (saved_bank == 2'd0) ? gray_line1_rd :
                               (saved_bank == 2'd1) ? gray_line2_rd : gray_line0_rd;
    assign sobel_prev1_sample = (saved_row < 1) ? 8'd0 :
                                (saved_bank == 2'd0) ? sobel_line2_rd :
                                (saved_bank == 2'd1) ? sobel_line0_rd : sobel_line1_rd;
    assign sobel_prev2_sample = (saved_row < 2) ? 8'd0 :
                                (saved_bank == 2'd0) ? sobel_line1_rd :
                                (saved_bank == 2'd1) ? sobel_line2_rd : sobel_line0_rd;

    // Horizontal history for row r (current), r-1, and r-2.
    // *_d2 is column c-2, *_d1 is column c-1 before the current sample arrives.
    reg [7:0] gray_cur_d2,  gray_cur_d1;
    reg [7:0] gray_prev1_d2, gray_prev1_d1;
    reg [7:0] gray_prev2_d2, gray_prev2_d1;
    reg [7:0] sobel_cur_d2,  sobel_cur_d1;
    reg [7:0] sobel_prev1_d2, sobel_prev1_d1;
    reg [7:0] sobel_prev2_d2, sobel_prev2_d1;

    reg [71:0] gray_window_reg;
    reg [71:0] sobel_window_reg;
    reg        right_window_pending;

    // Bottom border needs one virtual zero row. Read the two final real rows
    // one column at a time and shift them horizontally; still only line buffers.
    reg [6:0] bottom_col;
    reg       bottom_right_pending;
    reg [7:0] gray_row94_d2, gray_row94_d1;
    reg [7:0] gray_row95_d2, gray_row95_d1;
    reg [7:0] sobel_row94_d2, sobel_row94_d1;
    reg [7:0] sobel_row95_d2, sobel_row95_d1;

    wire core_stem_valid;
    assign pixel_ready = (state == S_ACCEPT_PIXEL) && !core_done;
    assign pixel_fire  = pixel_valid && pixel_ready;
    assign core_stem_valid = (state == S_SEND_WINDOW) || (state == S_SEND_BOTTOM);

    // ------------------------------------------------------------------------
    // Single-port line-bank accesses. Each physical bank has one registered
    // read-data signal and is either written as the current row or read as a
    // preceding row in a given input transaction. The final bottom-row flush
    // reuses bank-1/bank-2 read outputs, rather than adding read ports.
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (pixel_fire) begin
            case (bank_sel)
                2'd0: begin
                    gray_line0[input_col]  <= gray_pixel;
                    sobel_line0[input_col] <= sobel_pixel;
                    if (input_row >= 1) begin
                        gray_line2_rd  <= gray_line2[input_col];
                        sobel_line2_rd <= sobel_line2[input_col];
                    end
                    if (input_row >= 2) begin
                        gray_line1_rd  <= gray_line1[input_col];
                        sobel_line1_rd <= sobel_line1[input_col];
                    end
                end
                2'd1: begin
                    gray_line1[input_col]  <= gray_pixel;
                    sobel_line1[input_col] <= sobel_pixel;
                    if (input_row >= 1) begin
                        gray_line0_rd  <= gray_line0[input_col];
                        sobel_line0_rd <= sobel_line0[input_col];
                    end
                    if (input_row >= 2) begin
                        gray_line2_rd  <= gray_line2[input_col];
                        sobel_line2_rd <= sobel_line2[input_col];
                    end
                end
                default: begin // bank 2
                    gray_line2[input_col]  <= gray_pixel;
                    sobel_line2[input_col] <= sobel_pixel;
                    if (input_row >= 1) begin
                        gray_line1_rd  <= gray_line1[input_col];
                        sobel_line1_rd <= sobel_line1[input_col];
                    end
                    if (input_row >= 2) begin
                        gray_line0_rd  <= gray_line0[input_col];
                        sobel_line0_rd <= sobel_line0[input_col];
                    end
                end
            endcase
        end else if (state == S_BOTTOM_READ) begin
            // For a 96x96 frame, physical banks 1 and 2 contain rows 94 and 95.
            gray_line1_rd  <= gray_line1[bottom_col];
            gray_line2_rd  <= gray_line2[bottom_col];
            sobel_line1_rd <= sobel_line1[bottom_col];
            sobel_line2_rd <= sobel_line2[bottom_col];
        end
    end

    // ------------------------------------------------------------------------
    // CNN core. The wrapper generates its expected 3x3 input stream on demand.
    // ------------------------------------------------------------------------
    wire signed [31:0] fc_out;
    wire [2:0]         fc_class_idx;
    wire               fc_out_valid;
    wire               fc_frame_done;

    // Existing debug/status outputs are internal and not exposed at this IP.
    wire [2:0]  active_block_debug;
    wire [31:0] active_source_fire_count;
    wire [31:0] active_output_fire_count;
    wire [2:0]  last_completed_block_debug;
    wire [31:0] last_completed_source_count_debug;
    wire [31:0] last_completed_output_count_debug;
    wire [6:0]  stage_completed_mask_debug;
    assign debug_fc_valid_o      = fc_out_valid;
    assign debug_fc_index_o      = fc_class_idx;
    assign debug_fc_value_o      = fc_out;
    assign debug_fc_frame_done_o = fc_frame_done;
    assign debug_stage_mask_o    = stage_completed_mask_debug;
    assign debug_active_block_o  = active_block_debug;

    cnn_top #(
        .FRAME_W(FRAME_W),
        .FRAME_H(FRAME_H)
    ) u_cnn (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_pulse),
        .stem_in_valid(core_stem_valid),
        .stem_in_ready(core_stem_ready),

        .gray_p00(gray_window_reg[ 7: 0]),
        .gray_p01(gray_window_reg[15: 8]),
        .gray_p02(gray_window_reg[23:16]),
        .gray_p10(gray_window_reg[31:24]),
        .gray_p11(gray_window_reg[39:32]),
        .gray_p12(gray_window_reg[47:40]),
        .gray_p20(gray_window_reg[55:48]),
        .gray_p21(gray_window_reg[63:56]),
        .gray_p22(gray_window_reg[71:64]),

        .sobel_p00(sobel_window_reg[ 7: 0]),
        .sobel_p01(sobel_window_reg[15: 8]),
        .sobel_p02(sobel_window_reg[23:16]),
        .sobel_p10(sobel_window_reg[31:24]),
        .sobel_p11(sobel_window_reg[39:32]),
        .sobel_p12(sobel_window_reg[47:40]),
        .sobel_p20(sobel_window_reg[55:48]),
        .sobel_p21(sobel_window_reg[63:56]),
        .sobel_p22(sobel_window_reg[71:64]),

        .fc_out(fc_out),
        .fc_class_idx(fc_class_idx),
        .fc_out_valid(fc_out_valid),
        .fc_frame_done(fc_frame_done),
        .cnn_busy(core_busy),
        .cnn_done(core_done),
        .active_block_debug(active_block_debug),
        .active_source_fire_count(active_source_fire_count),
        .active_output_fire_count(active_output_fire_count),
        .last_completed_block_debug(last_completed_block_debug),
        .last_completed_source_count_debug(last_completed_source_count_debug),
        .last_completed_output_count_debug(last_completed_output_count_debug),
        .stage_completed_mask_debug(stage_completed_mask_debug)
    );

    // ------------------------------------------------------------------------
    // FC logits are collected unchanged. A registered, three-stage tournament
    // argmax breaks the original serial comparison chain into one comparator
    // level per clock. Ties select the lower class index, matching the original
    // strict-greater-than loop. The external done signal waits for the result.
    reg signed [31:0] logits [0:6];
    reg argmax_s1_pending;
    reg argmax_s2_pending;
    reg argmax_s3_pending;
    reg predicted_valid;
    integer i;

    // Stage 1: compare pairs (0,1), (2,3), (4,5); carry class 6 forward.
    reg signed [31:0] arg01_value_r, arg23_value_r, arg45_value_r, arg6_value_r;
    reg [2:0] arg01_index_r, arg23_index_r, arg45_index_r;

    // Stage 2: compare winners (0..3) and (4..6).
    reg signed [31:0] arg03_value_r, arg46_value_r;
    reg [2:0] arg03_index_r, arg46_index_r;

    // Keep done low until the pipelined argmax is ready.
    assign done = core_done && predicted_valid;

    // ------------------------------------------------------------------------
    // Streaming input/window control FSM.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            frame_valid_d      <= 1'b0;
            frame_started      <= 1'b0;
            start_pulse        <= 1'b0;
            input_row          <= 7'd0;
            input_col          <= 7'd0;
            bank_sel           <= 2'd0;
            saved_row          <= 7'd0;
            saved_col          <= 7'd0;
            saved_bank         <= 2'd0;
            saved_gray_pixel   <= 8'd0;
            saved_sobel_pixel  <= 8'd0;
            gray_window_reg    <= 72'd0;
            sobel_window_reg   <= 72'd0;
            right_window_pending <= 1'b0;
            bottom_col         <= 7'd0;
            bottom_right_pending <= 1'b0;
            gray_cur_d2 <= 0; gray_cur_d1 <= 0;
            gray_prev1_d2 <= 0; gray_prev1_d1 <= 0;
            gray_prev2_d2 <= 0; gray_prev2_d1 <= 0;
            sobel_cur_d2 <= 0; sobel_cur_d1 <= 0;
            sobel_prev1_d2 <= 0; sobel_prev1_d1 <= 0;
            sobel_prev2_d2 <= 0; sobel_prev2_d1 <= 0;
            gray_row94_d2 <= 0; gray_row94_d1 <= 0;
            gray_row95_d2 <= 0; gray_row95_d1 <= 0;
            sobel_row94_d2 <= 0; sobel_row94_d1 <= 0;
            sobel_row95_d2 <= 0; sobel_row95_d1 <= 0;
            predicted_class   <= 3'd0;
            argmax_s1_pending <= 1'b0;
            argmax_s2_pending <= 1'b0;
            argmax_s3_pending <= 1'b0;
            predicted_valid   <= 1'b0;
            for (i = 0; i < 7; i = i + 1)
                logits[i] <= 32'sd0;
        end else begin
            frame_valid_d <= frame_valid;
            start_pulse   <= 1'b0;

            // Store FC results exactly as before. fc_frame_done can coincide
            // with the last output; nonblocking assignment commits it now, and
            // Stage 1 reads the completed logits array on the next clock.
            if (fc_out_valid && (fc_class_idx < 3'd7))
                logits[fc_class_idx] <= fc_out;

            if (argmax_s1_pending) begin
                if (logits[0] >= logits[1]) begin
                    arg01_value_r <= logits[0]; arg01_index_r <= 3'd0;
                end else begin
                    arg01_value_r <= logits[1]; arg01_index_r <= 3'd1;
                end
                if (logits[2] >= logits[3]) begin
                    arg23_value_r <= logits[2]; arg23_index_r <= 3'd2;
                end else begin
                    arg23_value_r <= logits[3]; arg23_index_r <= 3'd3;
                end
                if (logits[4] >= logits[5]) begin
                    arg45_value_r <= logits[4]; arg45_index_r <= 3'd4;
                end else begin
                    arg45_value_r <= logits[5]; arg45_index_r <= 3'd5;
                end
                arg6_value_r <= logits[6];
                argmax_s1_pending <= 1'b0;
                argmax_s2_pending <= 1'b1;
            end

            if (argmax_s2_pending) begin
                if (arg01_value_r >= arg23_value_r) begin
                    arg03_value_r <= arg01_value_r;
                    arg03_index_r <= arg01_index_r;
                end else begin
                    arg03_value_r <= arg23_value_r;
                    arg03_index_r <= arg23_index_r;
                end
                if (arg45_value_r >= arg6_value_r) begin
                    arg46_value_r <= arg45_value_r;
                    arg46_index_r <= arg45_index_r;
                end else begin
                    arg46_value_r <= arg6_value_r;
                    arg46_index_r <= 3'd6;
                end
                argmax_s2_pending <= 1'b0;
                argmax_s3_pending <= 1'b1;
            end

            if (argmax_s3_pending) begin
                predicted_class <= (arg03_value_r >= arg46_value_r)
                                 ? arg03_index_r : arg46_index_r;
                predicted_valid <= 1'b1;
                argmax_s3_pending <= 1'b0;
            end

            if (fc_frame_done)
                argmax_s1_pending <= 1'b1;

            case (state)
                S_IDLE: begin
                    if (frame_valid && !frame_valid_d && !frame_started) begin
                        frame_started <= 1'b1;
                        start_pulse   <= 1'b1;
                        input_row     <= 7'd0;
                        input_col     <= 7'd0;
                        bank_sel      <= 2'd0;
                        predicted_class   <= 3'd0;
                        argmax_s1_pending <= 1'b0;
                        argmax_s2_pending <= 1'b0;
                        argmax_s3_pending <= 1'b0;
                        predicted_valid   <= 1'b0;
                        for (i = 0; i < 7; i = i + 1)
                            logits[i] <= 32'sd0;
                        state <= S_WAIT_CORE;
                    end
                end

                S_WAIT_CORE: begin
                    if (core_stem_ready)
                        state <= S_ACCEPT_PIXEL;
                end

                S_ACCEPT_PIXEL: begin
                    if (pixel_fire) begin
                        saved_row         <= input_row;
                        saved_col         <= input_col;
                        saved_bank        <= bank_sel;
                        saved_gray_pixel  <= gray_pixel;
                        saved_sobel_pixel <= sobel_pixel;
                        state <= S_PIXEL_WAIT;
                    end
                end

                S_PIXEL_WAIT: begin
                    // Start each row's horizontal histories at column zero.
                    if (saved_col == 0) begin
                        gray_cur_d2   <= 8'd0;
                        gray_cur_d1   <= saved_gray_pixel;
                        gray_prev1_d2 <= 8'd0;
                        gray_prev1_d1 <= gray_prev1_sample;
                        gray_prev2_d2 <= 8'd0;
                        gray_prev2_d1 <= gray_prev2_sample;

                        sobel_cur_d2   <= 8'd0;
                        sobel_cur_d1   <= saved_sobel_pixel;
                        sobel_prev1_d2 <= 8'd0;
                        sobel_prev1_d1 <= sobel_prev1_sample;
                        sobel_prev2_d2 <= 8'd0;
                        sobel_prev2_d1 <= sobel_prev2_sample;
                    end else begin
                        gray_cur_d2   <= gray_cur_d1;
                        gray_cur_d1   <= saved_gray_pixel;
                        gray_prev1_d2 <= gray_prev1_d1;
                        gray_prev1_d1 <= gray_prev1_sample;
                        gray_prev2_d2 <= gray_prev2_d1;
                        gray_prev2_d1 <= gray_prev2_sample;

                        sobel_cur_d2   <= sobel_cur_d1;
                        sobel_cur_d1   <= saved_sobel_pixel;
                        sobel_prev1_d2 <= sobel_prev1_d1;
                        sobel_prev1_d1 <= sobel_prev1_sample;
                        sobel_prev2_d2 <= sobel_prev2_d1;
                        sobel_prev2_d1 <= sobel_prev2_sample;
                    end

                    if ((saved_row >= 1) && (saved_col >= 1)) begin
                        // Top row of window: input row r-2; zero if out of frame.
                        gray_window_reg[ 7: 0] <= (saved_row >= 2) ? gray_prev2_d2 : 8'd0;
                        gray_window_reg[15: 8] <= (saved_row >= 2) ? gray_prev2_d1 : 8'd0;
                        gray_window_reg[23:16] <= (saved_row >= 2) ? gray_prev2_sample : 8'd0;
                        // Middle row: input row r-1.
                        gray_window_reg[31:24] <= gray_prev1_d2;
                        gray_window_reg[39:32] <= gray_prev1_d1;
                        gray_window_reg[47:40] <= gray_prev1_sample;
                        // Bottom row: input row r, with current input pixel as right tap.
                        gray_window_reg[55:48] <= gray_cur_d2;
                        gray_window_reg[63:56] <= gray_cur_d1;
                        gray_window_reg[71:64] <= saved_gray_pixel;

                        sobel_window_reg[ 7: 0] <= (saved_row >= 2) ? sobel_prev2_d2 : 8'd0;
                        sobel_window_reg[15: 8] <= (saved_row >= 2) ? sobel_prev2_d1 : 8'd0;
                        sobel_window_reg[23:16] <= (saved_row >= 2) ? sobel_prev2_sample : 8'd0;
                        sobel_window_reg[31:24] <= sobel_prev1_d2;
                        sobel_window_reg[39:32] <= sobel_prev1_d1;
                        sobel_window_reg[47:40] <= sobel_prev1_sample;
                        sobel_window_reg[55:48] <= sobel_cur_d2;
                        sobel_window_reg[63:56] <= sobel_cur_d1;
                        sobel_window_reg[71:64] <= saved_sobel_pixel;

                        right_window_pending <= 1'b0;
                        state <= S_SEND_WINDOW;
                    end else if (saved_col == FRAME_W-1) begin
                        // Row 0 produces no output windows. Advance to row 1.
                        input_row <= saved_row + 1'b1;
                        input_col <= 7'd0;
                        if (bank_sel == 2'd2) bank_sel <= 2'd0;
                        else                  bank_sel <= bank_sel + 1'b1;
                        state <= S_ACCEPT_PIXEL;
                    end else begin
                        input_col <= saved_col + 1'b1;
                        state <= S_ACCEPT_PIXEL;
                    end
                end

                S_SEND_WINDOW: begin
                    if (core_stem_ready) begin
                        if (!right_window_pending && (saved_col == FRAME_W-1)) begin
                            // Regular window x=FRAME_W-2 accepted; now emit the
                            // right-padding window x=FRAME_W-1 using the two
                            // latest horizontal samples and a zero right tap.
                            gray_window_reg[ 7: 0] <= (saved_row >= 2) ? gray_prev2_d2 : 8'd0;
                            gray_window_reg[15: 8] <= (saved_row >= 2) ? gray_prev2_d1 : 8'd0;
                            gray_window_reg[23:16] <= 8'd0;
                            gray_window_reg[31:24] <= gray_prev1_d2;
                            gray_window_reg[39:32] <= gray_prev1_d1;
                            gray_window_reg[47:40] <= 8'd0;
                            gray_window_reg[55:48] <= gray_cur_d2;
                            gray_window_reg[63:56] <= gray_cur_d1;
                            gray_window_reg[71:64] <= 8'd0;

                            sobel_window_reg[ 7: 0] <= (saved_row >= 2) ? sobel_prev2_d2 : 8'd0;
                            sobel_window_reg[15: 8] <= (saved_row >= 2) ? sobel_prev2_d1 : 8'd0;
                            sobel_window_reg[23:16] <= 8'd0;
                            sobel_window_reg[31:24] <= sobel_prev1_d2;
                            sobel_window_reg[39:32] <= sobel_prev1_d1;
                            sobel_window_reg[47:40] <= 8'd0;
                            sobel_window_reg[55:48] <= sobel_cur_d2;
                            sobel_window_reg[63:56] <= sobel_cur_d1;
                            sobel_window_reg[71:64] <= 8'd0;
                            right_window_pending <= 1'b1;
                            // Stay in this state; the new padding window is the
                            // next stream transaction and is held stable.
                        end else if (right_window_pending) begin
                            right_window_pending <= 1'b0;
                            if (saved_row == FRAME_H-1) begin
                                bottom_col <= 7'd0;
                                bottom_right_pending <= 1'b0;
                                state <= S_BOTTOM_READ;
                            end else begin
                                input_row <= saved_row + 1'b1;
                                input_col <= 7'd0;
                                if (bank_sel == 2'd2) bank_sel <= 2'd0;
                                else                  bank_sel <= bank_sel + 1'b1;
                                state <= S_ACCEPT_PIXEL;
                            end
                        end else begin
                            input_col <= saved_col + 1'b1;
                            state <= S_ACCEPT_PIXEL;
                        end
                    end
                end

                S_BOTTOM_READ: begin
                    // Sync reads of row 94 and row 95 occur in the memory block.
                    state <= S_BOTTOM_WAIT;
                end

                S_BOTTOM_WAIT: begin
                    if (bottom_col == 0) begin
                        // Seed horizontal history with column 0. The left border
                        // is emitted when column 1 is read on the next iteration.
                        gray_row94_d2 <= 8'd0;
                        gray_row94_d1 <= gray_line1_rd;
                        gray_row95_d2 <= 8'd0;
                        gray_row95_d1 <= gray_line2_rd;
                        sobel_row94_d2 <= 8'd0;
                        sobel_row94_d1 <= sobel_line1_rd;
                        sobel_row95_d2 <= 8'd0;
                        sobel_row95_d1 <= sobel_line2_rd;
                        bottom_col <= 7'd1;
                        state <= S_BOTTOM_READ;
                    end else begin
                        // Bottom output row y=FRAME_H-1; the third row is zero.
                        gray_window_reg[ 7: 0] <= gray_row94_d2;
                        gray_window_reg[15: 8] <= gray_row94_d1;
                        gray_window_reg[23:16] <= gray_line1_rd;
                        gray_window_reg[31:24] <= gray_row95_d2;
                        gray_window_reg[39:32] <= gray_row95_d1;
                        gray_window_reg[47:40] <= gray_line2_rd;
                        gray_window_reg[55:48] <= 8'd0;
                        gray_window_reg[63:56] <= 8'd0;
                        gray_window_reg[71:64] <= 8'd0;

                        sobel_window_reg[ 7: 0] <= sobel_row94_d2;
                        sobel_window_reg[15: 8] <= sobel_row94_d1;
                        sobel_window_reg[23:16] <= sobel_line1_rd;
                        sobel_window_reg[31:24] <= sobel_row95_d2;
                        sobel_window_reg[39:32] <= sobel_row95_d1;
                        sobel_window_reg[47:40] <= sobel_line2_rd;
                        sobel_window_reg[55:48] <= 8'd0;
                        sobel_window_reg[63:56] <= 8'd0;
                        sobel_window_reg[71:64] <= 8'd0;

                        gray_row94_d2 <= gray_row94_d1;
                        gray_row94_d1 <= gray_line1_rd;
                        gray_row95_d2 <= gray_row95_d1;
                        gray_row95_d1 <= gray_line2_rd;
                        sobel_row94_d2 <= sobel_row94_d1;
                        sobel_row94_d1 <= sobel_line1_rd;
                        sobel_row95_d2 <= sobel_row95_d1;
                        sobel_row95_d1 <= sobel_line2_rd;

                        bottom_right_pending <= 1'b0;
                        state <= S_SEND_BOTTOM;
                    end
                end

                S_SEND_BOTTOM: begin
                    if (core_stem_ready) begin
                        if (bottom_right_pending) begin
                            // Final window (bottom-right corner) accepted.
                            state <= S_WAIT_DONE;
                            bottom_right_pending <= 1'b0;
                        end else if (bottom_col == FRAME_W-1) begin
                            // Output x=FRAME_W-2 was accepted. Generate the
                            // right-padded bottom-right window x=FRAME_W-1.
                            gray_window_reg[ 7: 0] <= gray_row94_d2;
                            gray_window_reg[15: 8] <= gray_row94_d1;
                            gray_window_reg[23:16] <= 8'd0;
                            gray_window_reg[31:24] <= gray_row95_d2;
                            gray_window_reg[39:32] <= gray_row95_d1;
                            gray_window_reg[47:40] <= 8'd0;
                            gray_window_reg[55:48] <= 8'd0;
                            gray_window_reg[63:56] <= 8'd0;
                            gray_window_reg[71:64] <= 8'd0;

                            sobel_window_reg[ 7: 0] <= sobel_row94_d2;
                            sobel_window_reg[15: 8] <= sobel_row94_d1;
                            sobel_window_reg[23:16] <= 8'd0;
                            sobel_window_reg[31:24] <= sobel_row95_d2;
                            sobel_window_reg[39:32] <= sobel_row95_d1;
                            sobel_window_reg[47:40] <= 8'd0;
                            sobel_window_reg[55:48] <= 8'd0;
                            sobel_window_reg[63:56] <= 8'd0;
                            sobel_window_reg[71:64] <= 8'd0;
                            bottom_right_pending <= 1'b1;
                            // Stay in send state for the padded rightmost window.
                        end else begin
                            bottom_col <= bottom_col + 1'b1;
                            state <= S_BOTTOM_READ;
                        end
                    end
                end

                S_WAIT_DONE: begin
                    if (core_done)
                        state <= S_DONE;
                end

                S_DONE: begin
                    state <= S_DONE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire