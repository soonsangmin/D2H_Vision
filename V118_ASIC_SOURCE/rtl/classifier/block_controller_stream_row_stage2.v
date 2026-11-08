`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// STREAMING ROW-BUFFERED BLOCK CONTROLLER - RESIDUAL DSP PIPELINE V1
//
// Stage-1 migration from the proven full-frame controller.
// FINAL-S8 adds the Python-locked main/skip residual Q31 requantization
// before signed residual addition.
//
// IMPORTANT ARCHITECTURE CHOICE:
//   - Keep the existing TOP inter-stage frame buffers.
//   - Remove the per-block expanded FULL FRAME buffer.
//   - Expand output is accumulated into one HWC vector and written into a
//     THREE-ROW line buffer.
//   - The controller alternates between filling only the rows required by the
//     next output row and processing exactly ONE output row.
//
// Therefore this module is NOT yet full-network streaming.  It is the safe
// intermediate step that reduces the large internal expanded-frame RAM while
// preserving the existing top-level scheduler and downstream HWC framing.
//
// Row schedule:
//   STRIDE=1:
//       fill row0,row1 -> process out0
//       fill row2       -> process out1
//       fill row3       -> process out2
//       ...
//   STRIDE=2:
//       fill row0,row1 -> process out0
//       fill row2,row3 -> process out1
//       fill row4,row5 -> process out2
//       ...
//
// The existing WindowGen is reused unchanged; it is started with
// start_row=end_row=current output row.
// ============================================================================

module block_controller_stream_row_stage2 #(
    parameter integer IN_CH        = 24,
    parameter integer EXP_CH       = 48,
    parameter integer OUT_CH       = 24,
    parameter integer HAS_RESIDUAL = 1,
    parameter integer STRIDE       = 1,
    parameter integer IMG_WIDTH    = 96,
    parameter integer IMG_HEIGHT   = 96,

    // Legacy single residual multiplier parameter kept only for source
    // compatibility. It is NOT used by the final S8 residual datapath.
    parameter RES_MULT_FILE        = "",

    // Final Python-locked residual requantization uses two Q31 multipliers:
    //   main:  S_PROJ -> S_OUT
    //   skip:  S_IN   -> S_OUT
    parameter RES_MAIN_MULT_FILE   = "",
    parameter RES_SKIP_MULT_FILE   = "",

    // Default settings preserve B1-B6. B7 enables one-row look-ahead and uses
    // a fourth physical row bank to avoid overwriting the current 3x3 support.
    parameter integer ROW_BANKS = 4,
    parameter integer ENABLE_ROW_LOOKAHEAD = 1
)(
    input  wire clk,
    input  wire rst_n,

    // ------------------------------------------------------------------------
    // PW EXPAND -> controller
    // ------------------------------------------------------------------------
    input  wire                     expand_in_valid,
    input  wire [7:0]               expand_in_pixel,
    input  wire [7:0]               expand_in_ch_idx,
    input  wire [9:0]               expand_in_row,
    input  wire [9:0]               expand_in_col,
    output wire                     expand_in_ready,

    // ------------------------------------------------------------------------
    // Residual packed vector store
    // ------------------------------------------------------------------------
    input  wire [IN_CH*8-1:0]       res_fifo_rd_data,
    input  wire                     res_fifo_empty,
    output wire                     res_fifo_rd_en,

    // ------------------------------------------------------------------------
    // Controller -> shared DW
    // ------------------------------------------------------------------------
    output reg                      dw_in_valid,
    output reg [7:0]                dw_ch_idx,
    output reg [7:0]                dw_p00, dw_p01, dw_p02,
    output reg [7:0]                dw_p10, dw_p11, dw_p12,
    output reg [7:0]                dw_p20, dw_p21, dw_p22,
    input  wire                     dw_ready,

    // ------------------------------------------------------------------------
    // Shared PW Project -> controller
    // ------------------------------------------------------------------------
    input  wire [7:0]               pw_out,
    input  wire [7:0]               pw_out_ch_idx,
    input  wire                     pw_out_valid,
    output wire                     pw_out_ready,

    // ------------------------------------------------------------------------
    // Controller -> next stage
    // ------------------------------------------------------------------------
    output wire [7:0]               block_out_pixel,
    output wire [7:0]               block_out_ch_idx,
    output wire                     block_out_valid,
    input  wire                     block_out_ready,

    output reg                      block_busy,
    output wire                     pause_safe,

    // When asserted by the top scheduler, freeze the block at its current
    // safe state. If the block is sitting in ST_WAIT_LAUNCH, it may still
    // accept one pending PW-Expand output so the shared engine can drain
    // cleanly before ownership changes.
    input  wire                     scheduler_hold
);

    localparam integer EXP_LAST  = EXP_CH - 1;
    localparam integer OUT_LAST  = OUT_CH - 1;
    localparam integer OUT_WIDTH = ((IMG_WIDTH  + 2 - 3) / STRIDE) + 1;
    localparam integer OUT_HEIGHT= ((IMG_HEIGHT + 2 - 3) / STRIDE) + 1;

    // Match the WindowGen and row-buffer address buses to this stage's actual
    // dimensions. For a 48x48 stage, both address buses are 6 bits wide.
    // Keeping these widths equal avoids an undriven upper bit (Z) when a
    // 6-bit WindowGen output is connected to a fixed 7-bit controller wire.
    localparam integer ROW_ADDR_WIDTH =
        (IMG_HEIGHT > 1) ? $clog2(IMG_HEIGHT) : 1;
    localparam integer COL_ADDR_WIDTH =
        (IMG_WIDTH > 1) ? $clog2(IMG_WIDTH) : 1;
    localparam integer CHANNEL_ADDR_WIDTH =
        (EXP_CH > 1) ? $clog2(EXP_CH) : 1;

    // ------------------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------------------
    localparam [3:0]
        ST_FILL       = 4'd0,
        ST_WAIT_LAUNCH= 4'd1,
        ST_WINDOW     = 4'd2,
        ST_SEND_DW    = 4'd3,
        ST_WAIT_PW    = 4'd4,
        ST_DONE       = 4'd5;

    reg [3:0] state;

    reg [7:0] expected_pw_ch;
    reg [6:0] out_row;
    reg [6:0] row_pixel_count;

    // Number of COMPLETE expanded input rows resident/committed so far.
    // 0 means no complete row yet; N means rows 0..N-1 are complete.
    reg [7:0]  filled_rows;
    reg        input_frame_complete;
    // Count every accepted expanded scalar independently of channel decode.
    // This gives a deterministic end-of-frame indication even when the final
    // PW-Expand packet finishes one cycle away from the row/channel counter.
    localparam integer TOTAL_EXP_SCALARS = IMG_WIDTH * IMG_HEIGHT * EXP_CH;
    localparam integer EXP_COUNT_W = (TOTAL_EXP_SCALARS > 1) ? $clog2(TOTAL_EXP_SCALARS + 1) : 1;
    reg [EXP_COUNT_W-1:0] expand_accept_count;

    // Current input row/column being assembled from expanded scalar stream.
    reg [COL_ADDR_WIDTH-1:0] fill_col;

    // Window generator launch pulse and done tracking.
    reg       wg_done_seen;
    reg       win_gen_start;
    reg [6:0] wg_start_row;

    reg       done_reported;
    integer   dbg_window_accept_count;

    // Number of spatial windows of the current output row that have
    // actually been accepted by the controller at channel 0.
    // Recovery is only allowed after a complete row of windows is confirmed.
    reg [6:0] row_window_count;

    // ------------------------------------------------------------------------
    // Scalar HWC write/read path.
    // The PW engine already emits one channel byte per accepted cycle. Store
    // that byte directly instead of registering two complete EXP_CH vectors.
    // ------------------------------------------------------------------------
    wire [ROW_ADDR_WIDTH-1:0] row_buf_wr_row;
    wire [COL_ADDR_WIDTH-1:0] row_buf_wr_col;
    wire [CHANNEL_ADDR_WIDTH-1:0] row_buf_wr_channel;
    wire row_buf_wr_valid;

    assign row_buf_wr_row = filled_rows[ROW_ADDR_WIDTH-1:0];
    assign row_buf_wr_col = fill_col;
    assign row_buf_wr_channel = expand_in_ch_idx[CHANNEL_ADDR_WIDTH-1:0];
    assign row_buf_wr_valid = expand_in_valid && expand_in_ready &&
                              (expand_in_ch_idx < EXP_CH);

    // ------------------------------------------------------------------------
    // Window generator wires. Only one channel byte is read at a time.
    // ------------------------------------------------------------------------
    wire [7:0] wg_p00, wg_p01, wg_p02;
    wire [7:0] wg_p10, wg_p11, wg_p12;
    wire [7:0] wg_p20, wg_p21, wg_p22;
    // EXP_CH=48 requires CHANNEL_ADDR_WIDTH=$clog2(48)=6.
    // Match the generator port width exactly; an 8-bit net leaves its upper
    // bits undriven (Z) in this port connection and breaks channel==0 tests.
    wire [CHANNEL_ADDR_WIDTH-1:0] wg_channel_idx;
    wire       wg_window_valid;
    wire       wg_window_ready;
    wire       wg_busy;
    wire       wg_done;

    wire       wg_rd_valid;
    wire [ROW_ADDR_WIDTH-1:0] wg_rd_top_row, wg_rd_mid_row, wg_rd_bot_row;
    wire       wg_rd_top_valid, wg_rd_mid_valid, wg_rd_bot_valid;
    wire [COL_ADDR_WIDTH-1:0] wg_rd_center_col;
    wire [CHANNEL_ADDR_WIDTH-1:0] wg_rd_channel;
    wire [7:0] rb_p00,rb_p01,rb_p02,rb_p10,rb_p11,rb_p12,rb_p20,rb_p21,rb_p22;
    wire       rb_rd_data_valid;
    wire       row_buf_wr_ready;

    // ------------------------------------------------------------------------
    // Determine the last input row required for a given output row.
    // A 3x3 zero-padded window centered at out_row*STRIDE needs
    // center+1, clamped to the last real input row.
    // ------------------------------------------------------------------------
    function [7:0] required_rows;
        input [6:0] output_row;
        integer tmp;
        begin
            tmp = output_row * STRIDE + 1;
            if (tmp >= IMG_HEIGHT)
                tmp = IMG_HEIGHT - 1;
            required_rows = tmp + 1;
        end
    endfunction

    // ------------------------------------------------------------------------
    // FINAL S8 RESIDUAL Q31 MULTIPLIERS
    //
    // Python locked reference:
    //   qmain = requant_s8(pw_out,      S_PROJ -> S_OUT)
    //   qskip = requant_s8(residual_in, S_IN   -> S_OUT)
    //   sum   = qmain + qskip
    //   clip  = [-127, +127]
    //
    // The residual FIFO itself remains a pure packed S8 vector.
    // ------------------------------------------------------------------------
    reg [31:0] residual_main_mult_mem [0:0];
    reg [31:0] residual_skip_mult_mem [0:0];

    wire signed [31:0] residual_main_mult_q31 =
        $signed(residual_main_mult_mem[0]);

    wire signed [31:0] residual_skip_mult_q31 =
        $signed(residual_skip_mult_mem[0]);

    initial begin : INIT_RES_MULT
        // Safe defaults. Final residual instances override these through
        // RES_MAIN_MULT_FILE / RES_SKIP_MULT_FILE.
        residual_main_mult_mem[0] = 32'h7fffffff;
        residual_skip_mult_mem[0] = 32'h7fffffff;

        if (RES_MAIN_MULT_FILE != "") begin
            $readmemh(RES_MAIN_MULT_FILE, residual_main_mult_mem);
        end

        if (RES_SKIP_MULT_FILE != "") begin
            $readmemh(RES_SKIP_MULT_FILE, residual_skip_mult_mem);
        end

        $display("[STREAM-CTRL][RES_MULT] main_file=%s main_q31=0x%08h skip_file=%s skip_q31=0x%08h",
                 RES_MAIN_MULT_FILE,
                 residual_main_mult_mem[0],
                 RES_SKIP_MULT_FILE,
                 residual_skip_mult_mem[0]);
    end

    initial begin : FILECHECK_CONTROLLER_STREAM_ROW_V1
        $display("[FILECHECK] CONTROLLER_STREAM_ROW_BUILD=20261016_STAGE5_CHANNEL_ADDR_DEBUG");
        $display("[STREAM-CTRL] IMG=%0dx%0d EXP=%0d OUT=%0d STRIDE=%0d RES=%0d MAIN=%s SKIP=%s",
                 IMG_WIDTH, IMG_HEIGHT, EXP_CH, OUT_CH, STRIDE, HAS_RESIDUAL,
                 RES_MAIN_MULT_FILE, RES_SKIP_MULT_FILE);
    end

    // ------------------------------------------------------------------------
    // Track incoming HWC scalar stream and spatial column.
    // Every accepted scalar is written directly to the byte-wide row RAM.
    // There are no EXP_CH*8-bit pixel-assembly registers in this path.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_col            <= {COL_ADDR_WIDTH{1'b0}};
            filled_rows         <= 8'd0;
            input_frame_complete <= 1'b0;
            expand_accept_count <= {EXP_COUNT_W{1'b0}};
        end else begin
            if (expand_in_valid && expand_in_ready &&
                (expand_in_ch_idx < EXP_CH)) begin

                if (expand_accept_count < TOTAL_EXP_SCALARS)
                    expand_accept_count <= expand_accept_count + 1'b1;

                if (expand_accept_count == TOTAL_EXP_SCALARS-1) begin
                    input_frame_complete <= 1'b1;
                    filled_rows <= IMG_HEIGHT;
                    $display("[STREAM-CTRL] EXPAND FRAME COMPLETE scalars=%0d",
                             TOTAL_EXP_SCALARS);
                end

                if (expand_in_ch_idx == EXP_LAST) begin
                    if (fill_col == IMG_WIDTH-1) begin
                        if (expand_accept_count != TOTAL_EXP_SCALARS-1)
                            filled_rows <= filled_rows + 1'b1;
                        if (filled_rows + 1'b1 >= IMG_HEIGHT)
                            input_frame_complete <= 1'b1;
                        fill_col <= {COL_ADDR_WIDTH{1'b0}};
                    end else begin
                        fill_col <= fill_col + 1'b1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // REAL SCALAR EXPANDED ROW BUFFER (3 banks by default; 4 for B7 overlap)
    // ------------------------------------------------------------------------
    stream_row_buffer_3x3_parallel_hwc_stage2 #(
        .WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.CHANNELS(EXP_CH),
        .ROW_WIDTH(ROW_ADDR_WIDTH),.COL_WIDTH(COL_ADDR_WIDTH),.CHANNEL_INDEX_WIDTH(CHANNEL_ADDR_WIDTH),
        .ROW_BANKS(ROW_BANKS)
    ) u_stream_row_buffer (
        .clk(clk),.rst_n(rst_n),
        .wr_valid(row_buf_wr_valid),.wr_row(row_buf_wr_row),.wr_col(row_buf_wr_col),
        .wr_channel(row_buf_wr_channel),.wr_data(expand_in_pixel),.wr_ready(row_buf_wr_ready),
        .rd_valid(wg_rd_valid),
        .rd_top_row(wg_rd_top_row),.rd_top_valid(wg_rd_top_valid),
        .rd_mid_row(wg_rd_mid_row),.rd_mid_valid(wg_rd_mid_valid),
        .rd_bot_row(wg_rd_bot_row),.rd_bot_valid(wg_rd_bot_valid),
        .rd_center_col(wg_rd_center_col),.rd_channel(wg_rd_channel),
        .rd_p00(rb_p00),.rd_p01(rb_p01),.rd_p02(rb_p02),
        .rd_p10(rb_p10),.rd_p11(rb_p11),.rd_p12(rb_p12),
        .rd_p20(rb_p20),.rd_p21(rb_p21),.rd_p22(rb_p22),
        .rd_data_valid(rb_rd_data_valid)
    );

    // ------------------------------------------------------------------------
    // Launch WindowGen for exactly ONE output row.
    // Continuous start is avoided; one ST_WAIT_LAUNCH cycle gives the final
    // row write one clean clock to commit before the first RAM request.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            win_gen_start <= 1'b0;
        end else begin
            win_gen_start <= (state == ST_WAIT_LAUNCH) && !scheduler_hold;
        end
    end

    // ------------------------------------------------------------------------
    // Handshakes
    // ------------------------------------------------------------------------
    // In B7 only, accept one future expanded row while the current output
    // row is being computed. At output row r, rows r-1/r/r+1 are still in use;
    // with four banks, writing row r+2 uses a different physical bank. The
    // filled_rows bound stops immediately after that one look-ahead row.
    wire lookahead_state =
        (state == ST_WAIT_LAUNCH) ||
        (state == ST_WINDOW) ||
        (state == ST_SEND_DW) ||
        (state == ST_WAIT_PW);

    wire allow_row_lookahead =
        (ENABLE_ROW_LOOKAHEAD != 0) &&
        (ROW_BANKS == 4) &&
        !scheduler_hold &&
        lookahead_state &&
        (filled_rows < (required_rows(out_row) + 8'd1));

    assign expand_in_ready =
        ((state == ST_FILL) ||
         (scheduler_hold && (state == ST_WAIT_LAUNCH)) ||
         allow_row_lookahead) &&
        (filled_rows < IMG_HEIGHT) &&
        row_buf_wr_ready;

    // A held controller must not acknowledge a WindowGen transaction.
    // Previously state==ST_WINDOW alone kept READY high while scheduler_hold
    // froze this controller's FSM. WindowGen then drained a whole row without
    // the controller accepting any windows (WG DONE, windows_accepted=0).
    assign wg_window_ready =
        (state == ST_WINDOW) && !scheduler_hold;

    // ------------------------------------------------------------------------
    // Window Generator.  Process one output row at a time.
    // ------------------------------------------------------------------------
    ram_window_generator_3x3_parallel_rowrange7 #(
        .WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.CHANNELS(EXP_CH),.STRIDE(STRIDE),
        .ROW_ADDR_WIDTH(ROW_ADDR_WIDTH),.COL_ADDR_WIDTH(COL_ADDR_WIDTH),.CHANNEL_INDEX_WIDTH(CHANNEL_ADDR_WIDTH)
    ) u_window_gen (
        .clk(clk),.rst_n(rst_n),.start(win_gen_start),.start_row(wg_start_row),.end_row(wg_start_row),
        .rd_center_col(wg_rd_center_col),.rd_channel(wg_rd_channel),
        .rd_top_row(wg_rd_top_row),.rd_top_valid(wg_rd_top_valid),
        .rd_mid_row(wg_rd_mid_row),.rd_mid_valid(wg_rd_mid_valid),
        .rd_bot_row(wg_rd_bot_row),.rd_bot_valid(wg_rd_bot_valid),.rd_valid(wg_rd_valid),
        .rd_p00(rb_p00),.rd_p01(rb_p01),.rd_p02(rb_p02),
        .rd_p10(rb_p10),.rd_p11(rb_p11),.rd_p12(rb_p12),
        .rd_p20(rb_p20),.rd_p21(rb_p21),.rd_p22(rb_p22),.rd_data_valid(rb_rd_data_valid),
        .p00(wg_p00),.p01(wg_p01),.p02(wg_p02),.p10(wg_p10),.p11(wg_p11),.p12(wg_p12),
        .p20(wg_p20),.p21(wg_p21),.p22(wg_p22),.channel_idx(wg_channel_idx),
        .window_valid(wg_window_valid),.window_ready(wg_window_ready),.busy(wg_busy),.done(wg_done),.window_count()
    );

    // ------------------------------------------------------------------------
    // DW transaction payload remains stable throughout ST_SEND_DW.
    // ------------------------------------------------------------------------
    always @(*) begin
        // Do not launch/duplicate a DW transaction while the scheduler freezes
        // this block. The payload and state remain stable until resumed.
        dw_in_valid = (state == ST_SEND_DW) && !scheduler_hold;
    end

    // ------------------------------------------------------------------------
    // Independent handshake trace. This counter is intentionally NOT reset
    // when row_pixel_count/row_window_count are cleared at row completion.
    // It lets the log distinguish a stale/duplicate source file from a real
    // controller counter reset or a scheduler hold.
    // ------------------------------------------------------------------------
    reg [31:0] wg_trace_accept_count;
    integer wg_trace_blocked_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wg_trace_accept_count <= 32'd0;
            wg_trace_blocked_count <= 0;
        end else begin
            if (win_gen_start) begin
                wg_trace_accept_count <= 32'd0;
                wg_trace_blocked_count <= 0;
                $display("[WG-TRACE][START] build=20261016_STAGE5_CHANNEL_ADDR_DEBUG out_row=%0d ctrl_state=%0d hold=%b filled=%0d required=%0d",
                         wg_start_row, state, scheduler_hold, filled_rows, required_rows(out_row));
            end else if (wg_window_valid && wg_window_ready) begin
                wg_trace_accept_count <= wg_trace_accept_count + 1'b1;
                if (wg_trace_accept_count < 4 || (wg_trace_accept_count % 512) == 0)
                    $display("[WG-TRACE][ACCEPT] n=%0d row=%0d channel=%0d state=%0d hold=%b",
                             wg_trace_accept_count, out_row, wg_channel_idx, state, scheduler_hold);
            end
            if (wg_window_valid && !wg_window_ready && wg_trace_blocked_count < 8) begin
                $display("[WG-TRACE][BLOCKED] row=%0d ch=%0d ctrl_state=%0d hold=%b busy=%b done=%b",
                         out_row, wg_channel_idx, state, scheduler_hold, wg_busy, wg_done);
                wg_trace_blocked_count <= wg_trace_blocked_count + 1;
            end
            if (wg_done) begin
                $display("[WG-TRACE][DONE-SEEN] row=%0d transfers=%0d expected=%0d ctrl_state=%0d row_windows=%0d row_pixels=%0d hold=%b busy=%b valid=%b ready=%b",
                         out_row, wg_trace_accept_count, (OUT_WIDTH*EXP_CH), state,
                         row_window_count, row_pixel_count, scheduler_hold, wg_busy,
                         wg_window_valid, wg_window_ready);
            end
        end
    end

    // ------------------------------------------------------------------------
    // Main controller state machine.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_FILL;
            expected_pw_ch <= 8'd0;
            out_row        <= 7'd0;
            row_pixel_count <= 7'd0;
            wg_start_row   <= 7'd0;
            wg_done_seen   <= 1'b0;
            dw_ch_idx      <= 8'd0;

            dw_p00 <= 8'd0; dw_p01 <= 8'd0; dw_p02 <= 8'd0;
            dw_p10 <= 8'd0; dw_p11 <= 8'd0; dw_p12 <= 8'd0;
            dw_p20 <= 8'd0; dw_p21 <= 8'd0; dw_p22 <= 8'd0;

            block_busy <= 1'b1;
            row_window_count <= 7'd0;
        end else begin

            // WindowGen produces a one-cycle done pulse after the row has been
            // fully handed off to the controller.
            if (wg_done) begin
                wg_done_seen <= 1'b1;
                $display("[STREAM-CTRL][WG DONE] row=%0d windows_accepted=%0d row_pixel_count=%0d",
                         out_row, row_window_count, row_pixel_count);
            end

            if (scheduler_hold) begin
                // Freeze the sequencer at its current state.  A controller in
                // ST_WAIT_LAUNCH is deliberately left there so a single
                // pending PW-Expand vector can be drained through the
                // special expand_in_ready path above; WindowGen is held off.
                block_busy <= 1'b0;
            end else begin
            case (state)

                // ============================================================
                // Fill only enough expanded rows for the current output row.
                // ============================================================
                ST_FILL: begin
                    block_busy <= 1'b1;

                    // If the complete input frame has already arrived, no
                    // more source data will ever come. Do not remain in FILL.
                    // Scalar writes commit on accepted input cycles. WAIT_LAUNCH
                    // still provides a clean guard cycle before the first read.
                    // Normally the final input-scalar handshake below moves
                    // us directly to WAIT_LAUNCH. With row look-ahead, however,
                    // the final scalar of the next row can arrive on the same
                    // cycle as the current output row completes. In that case
                    // the FSM enters ST_FILL using the old filled_rows value;
                    // re-check row availability here so it does not consume an
                    // unnecessary additional row before launching WindowGen.
                    if (((input_frame_complete || (ENABLE_ROW_LOOKAHEAD != 0))) &&
                        (filled_rows >= required_rows(out_row))) begin
                        state <= ST_WAIT_LAUNCH;
                    end else if (expand_in_valid && expand_in_ready &&
                        (expand_in_ch_idx == EXP_LAST) &&
                        (fill_col == IMG_WIDTH-1)) begin

                        // The final scalar is written to RAM on this accepted
                        // cycle; WAIT_LAUNCH delays the first read until afterward.
                        if ((filled_rows + 1'b1) >= required_rows(out_row)) begin
                            state <= ST_WAIT_LAUNCH;
                            $display("[STREAM-CTRL] READY out_row=%0d filled_rows=%0d required_rows=%0d",
                                     out_row, filled_rows + 1'b1,
                                     required_rows(out_row));
                        end
                    end
                end

                // ============================================================
                // One clean cycle after row completion: launch WindowGen.
                // ============================================================
                ST_WAIT_LAUNCH: begin
                    block_busy   <= 1'b1;
                    wg_start_row    <= out_row;
                    wg_done_seen    <= 1'b0;
                    row_window_count<= 7'd0;
                    state           <= ST_WINDOW;
                    $display("[STREAM-CTRL][WG START] row=%0d stride=%0d",
                             out_row, STRIDE);
                end

                // ============================================================
                // Accept one 3x3 window / expanded channel.
                // ============================================================
                ST_WINDOW: begin
                    block_busy <= 1'b1;

                    // FIX15 recovery: only recover when WindowGen has really
                    // completed and this controller has accepted every spatial
                    // window of the current output row at channel 0.
                    if (wg_done_seen &&
                        !wg_busy &&
                        !wg_window_valid &&
                        (row_window_count >= OUT_WIDTH)) begin
                        if (out_row == OUT_HEIGHT-1) begin
                            state <= ST_DONE;
                            $display("[STREAM-CTRL][RECOVER] FINAL ROW COMPLETE out_row=%0d", out_row);
                        end else begin
                            out_row <= out_row + 1'b1;
                            if (ENABLE_ROW_LOOKAHEAD != 0)
                                state <= ST_FILL;
                            else if ((filled_rows >= required_rows(out_row + 1'b1)) ||
                                     input_frame_complete)
                                state <= ST_WAIT_LAUNCH;
                            else
                                state <= ST_FILL;
                            $display("[STREAM-CTRL][RECOVER] ROW COMPLETE out_row=%0d -> next=%0d",
                                     out_row, out_row + 1'b1);
                        end
                        wg_done_seen <= 1'b0;
                        row_window_count <= 7'd0;
                    end else if (wg_window_valid && wg_window_ready) begin
                        dw_p00 <= wg_p00; dw_p01 <= wg_p01; dw_p02 <= wg_p02;
                        dw_p10 <= wg_p10; dw_p11 <= wg_p11; dw_p12 <= wg_p12;
                        dw_p20 <= wg_p20; dw_p21 <= wg_p21; dw_p22 <= wg_p22;
                        dw_ch_idx <= wg_channel_idx;
                        state <= ST_SEND_DW;

                        if (wg_channel_idx == 0) begin
                            if (row_window_count < OUT_WIDTH)
                                row_window_count <= row_window_count + 1'b1;
                            if ((dbg_window_accept_count < 4) ||
                                ((dbg_window_accept_count % 4096) == 0))
                                $display("[STREAM-CTRL] WINDOW ACCEPT #%0d row=%0d",
                                         dbg_window_accept_count, out_row);
                            dbg_window_accept_count <= dbg_window_accept_count + 1;
                        end
                    end
                end

                // ============================================================
                // Drive one DW transaction until accepted.
                // ============================================================
                ST_SEND_DW: begin
                    block_busy <= 1'b1;

                    if (dw_ready) begin
                        if (dw_ch_idx == EXP_LAST) begin
                            expected_pw_ch <= 8'd0;
                            state <= ST_WAIT_PW;
                        end else begin
                            state <= ST_WINDOW;
                        end
                    end
                end

                // ============================================================
                // Wait for OUT_CH Project outputs for current spatial vector.
                // ============================================================
                ST_WAIT_PW: begin
                    block_busy <= 1'b1;

                    if (pw_out_valid && pw_out_ready) begin
                        if (pw_out_ch_idx != expected_pw_ch) begin
                            $display("[STREAM-CTRL][ERROR] PW CH mismatch row=%0d exp=%0d got=%0d",
                                     out_row, expected_pw_ch, pw_out_ch_idx);
                        end

                        if (expected_pw_ch == OUT_LAST) begin
                            expected_pw_ch <= 8'd0;

                            // ------------------------------------------------
                            // ROBUST ROW COMPLETION:
                            //
                            // One output row contains exactly OUT_WIDTH spatial
                            // vectors, and each vector produces OUT_CH accepted
                            // PW outputs. Therefore row completion can be
                            // determined entirely from the actual PW handshakes
                            // and does not depend on catching the one-cycle
                            // WindowGen done pulse.
                            // ------------------------------------------------
                            if (row_pixel_count == OUT_WIDTH-1) begin
                                row_pixel_count <= 7'd0;
                                row_window_count <= 7'd0;

                                if (out_row == OUT_HEIGHT-1) begin
                                    state <= ST_DONE;
                                    $display("[STREAM-CTRL] FINAL ROW COMPLETE out_row=%0d vectors=%0d",
                                             out_row, OUT_WIDTH);
                                end else begin
                                    out_row <= out_row + 1'b1;

                                    if (ENABLE_ROW_LOOKAHEAD != 0) begin
                                        // Expose a deterministic pause-safe boundary so the
                                        // shared-engine scheduler can hand off after each row.
                                        state <= ST_FILL;
                                    end else if ((filled_rows >= required_rows(out_row + 1'b1)) ||
                                                 input_frame_complete) begin
                                        state <= ST_WAIT_LAUNCH;
                                    end else begin
                                        state <= ST_FILL;
                                    end

                                    $display("[STREAM-CTRL] ROW COMPLETE out_row=%0d vectors=%0d -> next=%0d",
                                             out_row, OUT_WIDTH, out_row + 1'b1);
                                end
                            end else begin
                                row_pixel_count <= row_pixel_count + 1'b1;
                                state <= ST_WINDOW;
                            end
                        end else begin
                            expected_pw_ch <= expected_pw_ch + 1'b1;
                        end
                    end
                end

                ST_DONE: begin
                    block_busy <= 1'b0;
                end

                default: begin
                    state <= ST_FILL;
                    block_busy <= 1'b1;
                end
            endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // PW Project output -> optional residual add -> downstream HWC stream.
    // ------------------------------------------------------------------------
    wire residual_available;
    wire pw_fire;
    wire [7:0] residual_ch_val;

    // The residual multiplier is explicitly pipelined at its product output.
    // MAIN product rounding overlaps with registration of the SKIP product,
    // so only one extra cycle per residual channel is introduced.
    localparam [2:0]
        RES_MAC_IDLE      = 3'd0,
        RES_MAC_MAIN      = 3'd1,
        RES_MAC_MAIN_POST = 3'd2,
        RES_MAC_SKIP_POST = 3'd3,
        RES_MAC_DONE      = 3'd4;
    reg [2:0] residual_mul_state;
    reg signed [8:0]  residual_main_rounded_q;
    reg signed [7:0]  residual_out_q;
    reg signed [7:0]  residual_main_input_q;
    reg signed [7:0]  residual_skip_input_q;
    reg signed [63:0] residual_mul_product_q;

    assign residual_available =
        (HAS_RESIDUAL == 0) ? 1'b1 : !res_fifo_empty;

    // Residual stages hold the PW Project transaction until the shared
    // Q31 multiplier has processed both main and skip operands. Non-residual
    // stages retain their original single-cycle pass-through handshake.
    assign pw_out_ready =
        (state == ST_WAIT_PW) &&
        !scheduler_hold &&
        residual_available &&
        block_out_ready &&
        ((HAS_RESIDUAL == 0) || (residual_mul_state == RES_MAC_DONE));

    assign pw_fire = pw_out_valid && pw_out_ready;

    generate
        if (HAS_RESIDUAL != 0) begin : GEN_RESIDUAL
            assign residual_ch_val =
                (pw_out_ch_idx < IN_CH) ?
                res_fifo_rd_data[pw_out_ch_idx*8 +: 8] :
                8'd0;
        end else begin : GEN_NO_RESIDUAL
            assign residual_ch_val = 8'd0;
        end
    endgenerate

    // Consume one residual vector after the last output channel of each
    // spatial location has successfully left the controller.
    assign res_fifo_rd_en =
        (HAS_RESIDUAL != 0) &&
        pw_fire &&
        (pw_out_ch_idx == OUT_LAST);

    // ------------------------------------------------------------------------
    // FINAL S8 RESIDUAL REQUANTIZATION + SIGNED ADD
    // DSP optimization: share one Q31 multiplier for the main and skip paths.
    // A residual output is not accepted until both products have completed.
    // ------------------------------------------------------------------------
    // Latch both operands when a PW channel is first seen. This shortens the
    // row_tag/residual-store -> DSP path to a small input-capture path and keeps
    // the operands stable while the shared multiplier is reused for MAIN/SKIP.
    wire signed [7:0] residual_mul_input =
        (residual_mul_state == RES_MAC_MAIN) ? residual_main_input_q : residual_skip_input_q;
    wire signed [31:0] residual_mul_q31 =
        (residual_mul_state == RES_MAC_MAIN) ? residual_main_mult_q31 : residual_skip_mult_q31;

    // Keep the sign-extension and result width consistent with the original
    // Q31 arithmetic. Quartus can now see only one multiplier per residual
    // controller instead of independent main/skip multiplier cones.
    // IMPORTANT: keep the original multiply operands and expression intact.
    // A signed S8 by signed S32 product is exact in 40 bits; the full 64-bit
    // expression is retained here to preserve the current Quartus multiplier
    // inference rather than forcing a wider 40x40 operand multiplication.
    wire signed [63:0] residual_mul_product =
        $signed({{56{residual_mul_input[7]}}, residual_mul_input}) *
        $signed(residual_mul_q31);
    wire signed [39:0] residual_mul_product_40 = residual_mul_product_q[39:0];

    function signed [8:0] q31_round_product_symmetric;
        input signed [39:0] product;
        reg signed [39:0] rounded;
        begin
            // Algebraically identical symmetric rounding without a wide abs():
            // positive: (x + 2^30) >>> 31
            // negative: (x + 2^30 - 1) >>> 31
            if (product[39])
                rounded = (product + 40'sd1073741823) >>> 31;
            else
                rounded = (product + 40'sd1073741824) >>> 31;
            q31_round_product_symmetric = rounded[8:0];
        end
    endfunction

    wire signed [8:0] residual_mul_rounded =
        q31_round_product_symmetric(residual_mul_product_40);
    wire signed [8:0] residual_main_s8 = residual_main_rounded_q;
    // The product register contains the SKIP product from RES_MAC_MAIN_POST
    // through the output handshake, so debug values remain representative.
    wire signed [8:0] residual_skip_s8 = residual_mul_rounded;
    wire signed [9:0] residual_sum_s8 =
        $signed({residual_main_s8[8], residual_main_s8}) +
        $signed({residual_skip_s8[8], residual_skip_s8});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            residual_mul_state       <= RES_MAC_IDLE;
            residual_main_rounded_q  <= 9'sd0;
            residual_out_q           <= 8'sd0;
            residual_main_input_q    <= 8'sd0;
            residual_skip_input_q    <= 8'sd0;
            residual_mul_product_q   <= 64'sd0;
        end else begin
            case (residual_mul_state)
                RES_MAC_IDLE: begin
                    if ((HAS_RESIDUAL != 0) &&
                        (state == ST_WAIT_PW) &&
                        pw_out_valid && residual_available) begin
                        // Save data before the multiply. The residual FIFO word
                        // remains held until pw_fire, but this register boundary
                        // keeps row-tag/empty/mux logic off the multiplier path.
                        residual_main_input_q <= $signed(pw_out);
                        residual_skip_input_q <= $signed(residual_ch_val);
                        residual_mul_state    <= RES_MAC_MAIN;
                    end
                end

                RES_MAC_MAIN: begin
                    // Register the exact original multiply expression. This is
                    // the DSP output-register candidate for the MAIN requant.
                    residual_mul_product_q <= residual_mul_product;
                    residual_mul_state     <= RES_MAC_MAIN_POST;
                end

                RES_MAC_MAIN_POST: begin
                    // Parallel work in this cycle:
                    //   (1) round the registered MAIN product into main_q;
                    //   (2) register the SKIP product into the same DSP output
                    //       register. Since this state is not RES_MAC_MAIN,
                    //       the multiplier mux selects the captured skip input.
                    residual_main_rounded_q <= residual_mul_rounded;
                    residual_mul_product_q  <= residual_mul_product;
                    residual_mul_state      <= RES_MAC_SKIP_POST;
                end

                RES_MAC_SKIP_POST: begin
                    // Rounding, signed residual add and clamp are downstream
                    // of the registered SKIP product. This cuts the DSP product
                    // path and adds only one cycle per residual channel.
                    if (residual_sum_s8 < -10'sd127)
                        residual_out_q <= -8'sd127;
                    else if (residual_sum_s8 > 10'sd127)
                        residual_out_q <= 8'sd127;
                    else
                        residual_out_q <= residual_sum_s8[7:0];
                    residual_mul_state <= RES_MAC_DONE;
                end

                RES_MAC_DONE: begin
                    if (pw_fire)
                        residual_mul_state <= RES_MAC_IDLE;
                end

                default: residual_mul_state <= RES_MAC_IDLE;
            endcase
        end
    end

    generate
        if (HAS_RESIDUAL != 0) begin : GEN_RES_REQUANT
            assign block_out_pixel = residual_out_q;
        end else begin : GEN_NO_RES_REQUANT
            // Preserve the non-residual pass-through path.
            assign block_out_pixel = pw_out;
        end
    endgenerate

    // Lightweight simulation visibility: print only the first few residual
    // conversions after reset to avoid log spam.
    integer dbg_res_print_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_res_print_count <= 0;
        end else if (HAS_RESIDUAL != 0 &&
                     pw_out_valid && pw_out_ready &&
                     dbg_res_print_count < 4) begin
            $display("[STREAM-CTRL][RES] pw_s8=%0d res_s8=%0d mainM=0x%08h skipM=0x%08h main_q=%0d skip_q=%0d sum=%0d out=%0d",
                     $signed(pw_out),
                     $signed(residual_ch_val),
                     residual_main_mult_mem[0],
                     residual_skip_mult_mem[0],
                     residual_main_s8,
                     residual_skip_s8,
                     residual_sum_s8,
                     $signed(block_out_pixel));
            dbg_res_print_count <= dbg_res_print_count + 1;
        end
    end

    assign block_out_ch_idx = pw_out_ch_idx;
    assign block_out_valid  =
        (state == ST_WAIT_PW) &&
        !scheduler_hold &&
        pw_out_valid &&
        residual_available &&
        ((HAS_RESIDUAL == 0) || (residual_mul_state == RES_MAC_DONE));

    // IMPORTANT: shared-engine preemption is allowed ONLY at a true source
    // wait boundary.  Do not preempt from ST_WINDOW even when WG has asserted
    // done, because the controller may still need to drain the final PW
    // vector / DW transaction.  The controller will enter ST_FILL after the
    // current output row is fully committed, and that is the deterministic
    // safe point for the top scheduler.
    // ST_FILL is only pause-safe when this controller really needs more
    // expanded source rows. If enough rows are already resident, ST_FILL will
    // launch WindowGen on the next clock; advertising pause_safe there creates
    // a race where the scheduler freezes the controller at the row-launch edge.
    wire fill_waiting_for_source =
        (filled_rows < required_rows(out_row)) && !input_frame_complete;

    assign pause_safe =
        ((state == ST_FILL) && fill_waiting_for_source) ||
        (state == ST_DONE);

    // ------------------------------------------------------------------------
    // Debug
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_reported <= 1'b0;
            dbg_window_accept_count <= 0;
        end else begin
            if (state != ST_DONE) begin
                done_reported <= 1'b0;
            end else if (!done_reported) begin
                $display("[STREAM-CTRL] BLOCK DONE");
                done_reported <= 1'b1;
            end

            if (expand_in_valid && expand_in_ready &&
                (expand_in_ch_idx == 0) && (expand_in_col == 0)) begin
                $display("[STREAM-CTRL] EXPAND ROW START top=(%0d,%0d) local_filled_rows=%0d",
                         expand_in_row, expand_in_col, filled_rows);
            end
        end
    end

endmodule

`default_nettype wire