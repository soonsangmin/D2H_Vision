`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// MobileNet V13 STAGE 2B TOP - B1->B2->B3 ROW STREAMING
//
// Network:
//   Input: Gray + Sobel 96x96
//   Stem : Gray 1->12 + Sobel 1->12 = 24
//   B1   : 24 -> 48 -> 24, S1, residual
//   B2   : 24 -> 48 -> 32, S1
//   B3   : 32 -> 64 -> 32, S1, residual
//   B4   : 32 -> 64 -> 64, S2
//   B5   : 64 -> 128 -> 64, S1, residual
//   B6   : 64 -> 128 -> 128, S2
//   B7   : 128 -> 256 -> 128, S1, residual
//   Head : 128 -> 256, 1x1
//   GAP  : 24x24x256 -> 256
//   FC   : 256 -> 7
//
// -----------------------------------------------------------------------------
// IMPORTANT ARCHITECTURE NOTE
// -----------------------------------------------------------------------------
// Stage-1 uses a three-row expanded buffer inside each block. Stage-2A further
// removes the B1->B2 full-frame buffer by time-multiplexing the shared arithmetic
// engines at row boundaries. A small completed-row FIFO carries B1 output rows
// to B2. B7 remains controller-streamed; Stage-6 removes the final B6->B7 full-frame buffer.
//
// This is deliberate. It prevents a shared PW/DW engine from being driven by
// two blocks simultaneously and gives every stage a clean transaction
// boundary:
//
//     SOURCE ROWS -> PW EXPAND -> BLOCK CONTROLLER -> OUTPUT ROWS/FRAME
//
// Residual blocks use a packed residual row-ring so the controller sees a
// FWFT-style vector for the current output spatial location without a full frame.
//
// The top contains two small helper modules below:
//   1) top_hwc_frame_buffer (legacy downstream boundaries)
//   2) top_residual_vector_store_row4_streaming
//   3) stream_interstage_row_fifo_hwc_stage2 (all row-stream boundaries)
//
// Both are sequentially used: write first, then read. There is no simultaneous
// read/write requirement for the intermediate feature maps in this version.
// ============================================================================

module cnn_top #(
    parameter integer FRAME_W = 96,
    parameter integer FRAME_H = 96,
    
    // Legacy residual parameters retained for source compatibility.
    

    // FINAL PYTHON-LOCKED S8 residual multipliers
    parameter RES_B1_MAIN_MULT_FILE = "rtl/classifier/hex_weights/residual/b1_main_mult.hex",
    parameter RES_B1_SKIP_MULT_FILE = "rtl/classifier/hex_weights/residual/b1_skip_mult.hex",
    parameter RES_B3_MAIN_MULT_FILE = "rtl/classifier/hex_weights/residual/b3_main_mult.hex",
    parameter RES_B3_SKIP_MULT_FILE = "rtl/classifier/hex_weights/residual/b3_skip_mult.hex",
    parameter RES_B5_MAIN_MULT_FILE = "rtl/classifier/hex_weights/residual/b5_main_mult.hex",
    parameter RES_B5_SKIP_MULT_FILE = "rtl/classifier/hex_weights/residual/b5_skip_mult.hex",
    parameter RES_B7_MAIN_MULT_FILE = "rtl/classifier/hex_weights/residual/b7_main_mult.hex",
    parameter RES_B7_SKIP_MULT_FILE = "rtl/classifier/hex_weights/residual/b7_skip_mult.hex"
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    // ========================================================================
    // STEM INPUT: one 3x3 Gray + one 3x3 Sobel window
    // ========================================================================
    input  wire       stem_in_valid,
    output wire       stem_in_ready,

    input  wire [7:0] gray_p00, gray_p01, gray_p02,
    input  wire [7:0] gray_p10, gray_p11, gray_p12,
    input  wire [7:0] gray_p20, gray_p21, gray_p22,

    input  wire [7:0] sobel_p00, sobel_p01, sobel_p02,
    input  wire [7:0] sobel_p10, sobel_p11, sobel_p12,
    input  wire [7:0] sobel_p20, sobel_p21, sobel_p22,

    // ========================================================================
    // FINAL FC OUTPUT
    // ========================================================================
    output wire signed [31:0] fc_out,
    output wire [2:0]         fc_class_idx,
    output wire               fc_out_valid,
    output wire               fc_frame_done,

    // ========================================================================
    // STATUS / DEBUG
    // ========================================================================
    output wire               cnn_busy,
    output wire               cnn_done,
    output wire [2:0]         active_block_debug,
    output wire [31:0]        active_source_fire_count,
    output wire [31:0]        active_output_fire_count,
    output wire [2:0]         last_completed_block_debug,
    output wire [31:0]        last_completed_source_count_debug,
    output wire [31:0]        last_completed_output_count_debug,
    output wire [6:0]         stage_completed_mask_debug
);

    // ========================================================================
    // GEOMETRY
    // ========================================================================
    localparam integer B1_IN_W  = 96;
    localparam integer B1_IN_H  = 96;
    localparam integer B1_EXP   = 48;
    localparam integer B1_OUT   = 24;

    localparam integer B2_IN_W  = 96;
    localparam integer B2_IN_H  = 96;
    localparam integer B2_EXP   = 48;
    localparam integer B2_OUT   = 32;

    localparam integer B3_IN_W  = 96;
    localparam integer B3_IN_H  = 96;
    localparam integer B3_EXP   = 64;
    localparam integer B3_OUT   = 32;

    localparam integer B4_IN_W  = 96;
    localparam integer B4_IN_H  = 96;
    localparam integer B4_EXP   = 64;
    localparam integer B4_OUT   = 64;

    localparam integer B5_IN_W  = 48;
    localparam integer B5_IN_H  = 48;
    localparam integer B5_EXP   = 128;
    localparam integer B5_OUT   = 64;

    localparam integer B6_IN_W  = 48;
    localparam integer B6_IN_H  = 48;
    localparam integer B6_EXP   = 128;
    localparam integer B6_OUT   = 128;

    localparam integer B7_IN_W  = 24;
    localparam integer B7_IN_H  = 24;
    localparam integer B7_IN    = 128;
    localparam integer B7_EXP   = 256;
    localparam integer B7_OUT   = 128;

    localparam integer B4_OUT_W = 48;
    localparam integer B4_OUT_H = 48;
    localparam integer B6_OUT_W = 24;
    localparam integer B6_OUT_H = 24;

    localparam integer B1_OUT_PIXELS = B1_IN_W*B1_IN_H;
    localparam integer B2_OUT_PIXELS = B2_IN_W*B2_IN_H;
    localparam integer B3_OUT_PIXELS = B3_IN_W*B3_IN_H;
    localparam integer B4_OUT_PIXELS = B4_OUT_W*B4_OUT_H;
    localparam integer B5_OUT_PIXELS = B5_IN_W*B5_IN_H;
    localparam integer B6_OUT_PIXELS = B6_OUT_W*B6_OUT_H;
    localparam integer B7_OUT_PIXELS = B7_IN_W*B7_IN_H;

    // ========================================================================
    // TOP FSM
    // ========================================================================
    localparam [3:0]
        S_IDLE   = 4'd0,
        S_B1     = 4'd1,
        S_B2     = 4'd2,
        S_B3     = 4'd3,
        S_B4     = 4'd4,
        S_B5     = 4'd5,
        S_B6     = 4'd6,
        S_B7     = 4'd7,
        S_FINISH = 4'd8,
        S_DONE   = 4'd9;

    reg [3:0] state;
    reg [2:0] active_block;
    reg       cnn_done_r;

    // PW Expand input-channel count for the currently active block.
    // B1/B2: 24, B3/B4: 32, B5/B6: 64, B7: 128.
    wire [8:0] active_in_ch =
        (active_block == 3'd0) ? 9'd24  :
        (active_block == 3'd1) ? 9'd24  :
        (active_block == 3'd2) ? 9'd32  :
        (active_block == 3'd3) ? 9'd32  :
        (active_block == 3'd4) ? 9'd64  :
        (active_block == 3'd5) ? 9'd64  :
        (active_block == 3'd6) ? 9'd128 :
        9'd24;
    reg       handoff_pending;
    reg       handoff_request;
    reg [2:0] handoff_target;

    // PW-Expand ST_RX can accept a partial input vector while busy=0.
    // Ownership must NEVER switch in the middle of that vector.
    reg       pw_rx_partial;


    // ========================================================================
    // SHARED INTERCONNECT FOR THE SEVEN BLOCK CONTROLLERS
    // ========================================================================
    wire stem_in_ready_int;
    wire active_expand_ready;

    wire b1_expand_ready, b2_expand_ready, b3_expand_ready, b4_expand_ready;
    wire b5_expand_ready, b6_expand_ready, b7_expand_ready;

    wire b1_dw_valid_i, b2_dw_valid_i, b3_dw_valid_i, b4_dw_valid_i;
    wire [7:0] b1_dw_ch_idx, b2_dw_ch_idx, b3_dw_ch_idx, b4_dw_ch_idx;
    wire [7:0] b5_dw_ch_idx, b6_dw_ch_idx, b7_dw_ch_idx;
    wire [7:0] b1_dw_p00, b1_dw_p01, b1_dw_p02, b2_dw_p00, b2_dw_p01, b2_dw_p02;
    wire [7:0] b3_dw_p00, b3_dw_p01, b3_dw_p02, b4_dw_p00, b4_dw_p01, b4_dw_p02;
    wire [7:0] b5_dw_p00, b5_dw_p01, b5_dw_p02, b6_dw_p00, b6_dw_p01, b6_dw_p02;
    wire [7:0] b7_dw_p00, b7_dw_p01, b7_dw_p02;
    wire [7:0] b1_dw_p10, b1_dw_p11, b1_dw_p12, b2_dw_p10, b2_dw_p11, b2_dw_p12;
    wire [7:0] b3_dw_p10, b3_dw_p11, b3_dw_p12, b4_dw_p10, b4_dw_p11, b4_dw_p12;
    wire [7:0] b5_dw_p10, b5_dw_p11, b5_dw_p12, b6_dw_p10, b6_dw_p11, b6_dw_p12;
    wire [7:0] b7_dw_p10, b7_dw_p11, b7_dw_p12;
    wire [7:0] b1_dw_p20, b1_dw_p21, b1_dw_p22, b2_dw_p20, b2_dw_p21, b2_dw_p22;
    wire [7:0] b3_dw_p20, b3_dw_p21, b3_dw_p22, b4_dw_p20, b4_dw_p21, b4_dw_p22;
    wire [7:0] b5_dw_p20, b5_dw_p21, b5_dw_p22, b6_dw_p20, b6_dw_p21, b6_dw_p22;
    wire [7:0] b7_dw_p20, b7_dw_p21, b7_dw_p22;
    wire b5_dw_valid_i, b6_dw_valid_i, b7_dw_valid_i;
    wire b1_dw_ready, b2_dw_ready, b3_dw_ready, b4_dw_ready;
    wire b5_dw_ready, b6_dw_ready, b7_dw_ready;

    wire b1_pw_ready, b2_pw_ready, b3_pw_ready, b4_pw_ready;
    wire b5_pw_ready, b6_pw_ready, b7_pw_ready;
    wire b1_pw_out_valid, b2_pw_out_valid, b3_pw_out_valid, b4_pw_out_valid;
    wire b5_pw_out_valid, b6_pw_out_valid, b7_pw_out_valid;
    wire [7:0] b1_pw_out_pixel, b2_pw_out_pixel, b3_pw_out_pixel, b4_pw_out_pixel;
    wire [7:0] b5_pw_out_pixel, b6_pw_out_pixel, b7_pw_out_pixel;
    wire [7:0] b1_pw_out_ch_idx, b2_pw_out_ch_idx, b3_pw_out_ch_idx, b4_pw_out_ch_idx;
    wire [7:0] b5_pw_out_ch_idx, b6_pw_out_ch_idx, b7_pw_out_ch_idx;

    wire b1_block_out_valid, b2_block_out_valid, b3_block_out_valid, b4_block_out_valid;
    wire b5_block_out_valid, b6_block_out_valid, b7_block_out_valid;
    wire [7:0] b1_block_out_pixel, b2_block_out_pixel, b3_block_out_pixel, b4_block_out_pixel;
    wire [7:0] b5_block_out_pixel, b6_block_out_pixel, b7_block_out_pixel;
    wire [7:0] b1_block_out_ch_idx, b2_block_out_ch_idx, b3_block_out_ch_idx, b4_block_out_ch_idx;
    wire [7:0] b5_block_out_ch_idx, b6_block_out_ch_idx, b7_block_out_ch_idx;
    wire b1_block_out_ready, b2_block_out_ready, b3_block_out_ready, b4_block_out_ready;
    wire b5_block_out_ready, b6_block_out_ready, b7_block_out_ready;
    wire b1_busy, b2_busy, b3_busy, b4_busy, b5_busy, b6_busy, b7_busy;

    wire b1_rd_valid, b2_rd_valid, b3_rd_valid, b5_rd_valid, b6_rd_valid;
    wire [7:0] b1_rd_pixel, b2_rd_pixel, b3_rd_pixel, b5_rd_pixel, b6_rd_pixel;
    wire [7:0] b1_rd_ch_idx, b2_rd_ch_idx, b3_rd_ch_idx, b5_rd_ch_idx, b6_rd_ch_idx;

    wire [24*8-1:0] b1_res_data;
    wire [32*8-1:0] b3_res_data;
    wire [64*8-1:0] b5_res_data;
    wire [128*8-1:0] b7_res_data;
    wire b1_res_empty, b3_res_empty, b5_res_empty, b7_res_empty;
    wire b1_res_rd_en, b3_res_rd_en, b5_res_rd_en, b7_res_rd_en;
    wire b1_res_wr_valid, b3_res_wr_valid, b5_res_wr_valid, b7_res_wr_valid;
    wire b1_res_wr_ready, b3_res_wr_ready, b5_res_wr_ready, b7_res_wr_ready;

    wire b1_wr_ready, b1_write_done, b1_read_done;
    wire b2_wr_ready, b2_write_done, b2_read_done;
    wire b3_wr_ready, b3_write_done, b3_read_done;
        wire b5_wr_ready, b5_write_done, b5_read_done;
    wire b6_wr_ready, b6_write_done, b6_read_done;

    // ========================================================================
    // B1 -> B2 ROW FIFO INTERFACE
    // ========================================================================
    // These signals were referenced by the Stage-2 scheduler/mux before they
    // were declared. With `default_nettype none` that becomes a VRFC error.
    wire        b1b2_fifo_wr_ready;
    wire [7:0]  b1b2_fifo_rows;
    wire        b1b2_fifo_rd_valid;
    wire        b1b2_fifo_rd_ready;
    wire [7:0]  b1b2_fifo_rd_pixel;
    wire [7:0]  b1b2_fifo_rd_ch_idx;
    wire [7:0]  b1b2_fifo_rd_row_idx;
    wire        b1b2_fifo_empty;
    wire        b1b2_fifo_full;

    // B2 -> B3 row FIFO.
    wire        b2b3_fifo_wr_ready;
    wire [7:0]  b2b3_fifo_rows;
    wire        b2b3_fifo_rd_valid;
    wire [7:0]  b2b3_fifo_rd_pixel;
    wire [7:0]  b2b3_fifo_rd_ch_idx;
    wire [7:0]  b2b3_fifo_rd_row_idx;
    wire        b2b3_fifo_rd_ready;
    wire        b2b3_fifo_empty;
    wire        b2b3_fifo_full;

    // B3 -> B4 row FIFO: B3 produces 96x96x32 HWC, B4 consumes the same
    // 32-channel input at stride=2. Two complete rows are enough to launch
    // B4 output row 0; thereafter B4 consumes two new B3 rows per output row.
    wire        b3b4_fifo_wr_ready;
    wire [7:0]  b3b4_fifo_rows;
    wire        b3b4_fifo_rd_valid;
    wire        b3b4_fifo_rd_ready;
    wire [7:0]  b3b4_fifo_rd_pixel;
    wire [7:0]  b3b4_fifo_rd_ch_idx;
    wire [7:0]  b3b4_fifo_rd_row_idx;
    wire        b3b4_fifo_empty;
    wire        b3b4_fifo_full;

    // B4 -> B5 row FIFO: B4 produces 48x48x64 HWC and B5 consumes the same
    // stream at stride=1. Two complete rows are enough to launch B5 row 0.
    wire        b4b5_fifo_wr_ready;
    wire [7:0]  b4b5_fifo_rows;
    wire        b4b5_fifo_rd_valid;
    wire        b4b5_fifo_rd_ready;
    wire [7:0]  b4b5_fifo_rd_pixel;
    wire [7:0]  b4b5_fifo_rd_ch_idx;
    wire [7:0]  b4b5_fifo_rd_row_idx;
    wire        b4b5_fifo_empty;
    wire        b4b5_fifo_full;

    // B5 -> B6 row FIFO.
    wire        b5b6_fifo_wr_ready;
    wire [7:0]  b5b6_fifo_rows;
    wire        b5b6_fifo_rd_valid;
    wire        b5b6_fifo_rd_ready;
    wire [7:0]  b5b6_fifo_rd_pixel;
    wire [7:0]  b5b6_fifo_rd_ch_idx;
    wire [7:0]  b5b6_fifo_rd_row_idx;
    wire        b5b6_fifo_empty;
    wire        b5b6_fifo_full;

    // B6 -> B7 row FIFO: B6 produces 24x24x128 HWC, B7 consumes the same
    // geometry at stride=1. Two complete rows are enough to launch B7 row 0.
    wire        b6b7_fifo_wr_ready;
    wire [7:0]  b6b7_fifo_rows;
    wire        b6b7_fifo_rd_valid;
    wire        b6b7_fifo_rd_ready;
    wire [7:0]  b6b7_fifo_rd_pixel;
    wire [7:0]  b6b7_fifo_rd_ch_idx;
    wire [7:0]  b6b7_fifo_rd_row_idx;
    wire        b6b7_fifo_empty;
    wire        b6b7_fifo_full;

    // Controllers expose a pause-safe indication used by the row scheduler.
    wire        b1_pause_safe;
    wire        b2_pause_safe;
    wire        b3_pause_safe;
    wire        b4_pause_safe;
    wire        b5_pause_safe;
    wire        b6_pause_safe;
    wire        b7_pause_safe;

    // Keep the current owner selected during a handoff. The owner controller
    // is frozen, but may drain one pending PW-Expand output while the shared
    // engine returns to IDLE. This prevents one expanded vector from being
    // stolen by the next block.
    wire b1_scheduler_hold = (state != S_B1) || (handoff_pending && (active_block == 3'd0));
    wire b2_scheduler_hold = (state != S_B2) || (handoff_pending && (active_block == 3'd1));
    wire b3_scheduler_hold = (state != S_B3) || (handoff_pending && (active_block == 3'd2));
    wire b4_scheduler_hold = (state != S_B4) || (handoff_pending && (active_block == 3'd3));
    wire b5_scheduler_hold = (state != S_B5) || (handoff_pending && (active_block == 3'd4));
    wire b6_scheduler_hold = (state != S_B6) || (handoff_pending && (active_block == 3'd5));
    wire b7_scheduler_hold = (state != S_B7) || (handoff_pending && (active_block == 3'd6));

    // NEVER switch active_block while any shared engine still owns a packet.
    // This is critical because PW Expand latches its block internally while
    // the top-level engine selection is driven by active_block.
    wire shared_engine_idle =
        !pw_exp_busy &&
        !pw_exp_out_valid &&
        !dw_busy &&
        !pw_proj_busy &&
        !pw_proj_out_valid;

    // The previous scheduler used shared_engine_idle alone.  That is unsafe
    // because PW Expand reports busy=0 in ST_RX even when ch=0..22 of the
    // current input vector have already been accepted.  In that condition an
    // owner switch causes the next block to overwrite the same input_buf.
    wire pw_input_last_fire =
        source_fire &&
        (pw_exp_in_ch_idx == (active_in_ch - 10'd1));

    // If a source scalar is being accepted this cycle, the only safe handoff
    // point is the LAST scalar of that vector.  Otherwise wait for a clean
    // idle cycle with no partial vector.
    wire pw_handoff_safe =
        (shared_engine_idle && !pw_rx_partial && !source_fire) ||
        pw_input_last_fire;

    wire b1_pause_safe_arb = b1_pause_safe && pw_handoff_safe;
    wire b2_pause_safe_arb = b2_pause_safe && pw_handoff_safe;
    wire b3_pause_safe_arb = b3_pause_safe && pw_handoff_safe;
    wire b4_pause_safe_arb = b4_pause_safe && pw_handoff_safe;
    wire b5_pause_safe_arb = b5_pause_safe && pw_handoff_safe;
    wire b6_pause_safe_arb = b6_pause_safe && pw_handoff_safe;
    wire b7_pause_safe_arb = b7_pause_safe && pw_handoff_safe;

    assign active_block_debug = active_block;

    // Simulation-only breadcrumb: confirms that the intended DUT really
    // elaborated as part of the active simulation hierarchy.
    initial begin
        $display("[TOP-STREAM-ROW-V10] cnn_top stage-7 row-stream FIX5_SOURCE_LIMIT_NO_MIDROW_PREEMPT + active_in_ch elaborated");
        $display("[TOP] Geometry: B1=96x96 B2=96x96 B3=96x96 B4=48x48 B5=48x48 B6=24x24 B7=24x24");
        $display("[TOP] Flow: STEM->B1->B2->B3->B4->B5->B6->B7->HEAD->GAP->FC | B1/B2/B3/B4/B5/B6/B7 row-stream boundaries + direct B7->HEAD streaming FIX1");
    end

    // ========================================================================
    // STEM
    // ========================================================================
    wire [7:0] stem_out_pixel;
    wire [7:0] stem_out_ch_idx;
    wire       stem_out_valid;
    wire       stem_out_ready;

    stem_conv3x3_dual u_stem (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(stem_in_valid),
        .in_ready(stem_in_ready_int),

        .p00({sobel_p00, gray_p00}),
        .p01({sobel_p01, gray_p01}),
        .p02({sobel_p02, gray_p02}),
        .p10({sobel_p10, gray_p10}),
        .p11({sobel_p11, gray_p11}),
        .p12({sobel_p12, gray_p12}),
        .p20({sobel_p20, gray_p20}),
        .p21({sobel_p21, gray_p21}),
        .p22({sobel_p22, gray_p22}),

        .stem_out_pixel(stem_out_pixel),
        .stem_out_ch_idx(stem_out_ch_idx),
        .out_valid(stem_out_valid),
        .out_ready(stem_out_ready)
    );

    assign stem_in_ready = (state == S_B1) && stem_in_ready_int;

    // ========================================================================
    // SHARED PW EXPAND
    // ========================================================================
    wire [2:0] pw_block_sel;
    assign pw_block_sel = active_block;

    wire       pw_exp_in_valid;
    wire [7:0] pw_exp_in_pixel;
    wire [7:0] pw_exp_in_ch_idx;
    wire       pw_exp_in_ready;

    wire [7:0] pw_exp_out_pixel;
    wire [7:0] pw_exp_out_ch_idx;
    wire       pw_exp_out_valid;
    wire       pw_exp_busy;

    // Residual row stores are part of the source-side handshake.
    // When the current residual row-ring is full, the source must STOP before
    // PW Expand accepts the scalar; otherwise the residual value would be
    // dropped while the feature stream continues.
    wire active_residual_wr_ready =
        (state == S_B1) ? b1_res_wr_ready :
        (state == S_B3) ? b3_res_wr_ready :
        (state == S_B5) ? b5_res_wr_ready :
        (state == S_B7) ? b7_res_wr_ready :
        1'b1;

    assign pw_exp_in_valid =
        !handoff_pending && active_residual_wr_ready && active_source_allow ?
        (
            (state == S_B1) ? stem_out_valid :
            (state == S_B2) ? b1b2_fifo_rd_valid :
            (state == S_B3) ? b2b3_fifo_rd_valid :
            (state == S_B4) ? b3b4_fifo_rd_valid :
            (state == S_B5) ? b4b5_fifo_rd_valid :
            (state == S_B6) ? b5b6_fifo_rd_valid :
            (state == S_B7) ? b6b7_fifo_rd_valid :
            1'b0
        ) : 1'b0;

    assign pw_exp_in_pixel =
        (state == S_B1) ? stem_out_pixel :
        (state == S_B2) ? b1b2_fifo_rd_pixel :
        (state == S_B3) ? b2b3_fifo_rd_pixel :
        (state == S_B4) ? b3b4_fifo_rd_pixel :
        (state == S_B5) ? b4b5_fifo_rd_pixel :
        (state == S_B6) ? b5b6_fifo_rd_pixel :
        (state == S_B7) ? b6b7_fifo_rd_pixel :
        8'd0;

    assign pw_exp_in_ch_idx =
        (state == S_B1) ? stem_out_ch_idx :
        (state == S_B2) ? b1b2_fifo_rd_ch_idx :
        (state == S_B3) ? b2b3_fifo_rd_ch_idx :
        (state == S_B4) ? b3b4_fifo_rd_ch_idx :
        (state == S_B5) ? b4b5_fifo_rd_ch_idx :
        (state == S_B6) ? b5b6_fifo_rd_ch_idx :
        (state == S_B7) ? b6b7_fifo_rd_ch_idx :
        8'd0;

    pw_engine_expand u_pw_expand (
        .clk(clk),
        .rst_n(rst_n),
        .block_sel(pw_block_sel),
        .in_valid(pw_exp_in_valid),
        .pixel_in(pw_exp_in_pixel),
        .in_ch_idx(pw_exp_in_ch_idx),
        .window_ready(active_expand_ready),
        .ready(pw_exp_in_ready),
        .pw_out(pw_exp_out_pixel),
        .out_ch_idx(pw_exp_out_ch_idx),
        .out_valid(pw_exp_out_valid),
        .busy(pw_exp_busy)
    );

    // The source of an active stage is allowed to advance only when PW Expand
    // actually accepts its current scalar.
    wire source_fire;
    assign source_fire = pw_exp_in_valid && pw_exp_in_ready;

    // Track whether PW Expand is part-way through an input vector.  This is
    // top-level state because the shared PW engine itself does not expose its
    // RX progress.  At handoff, the next block must not take ownership until
    // the current vector has reached its final input channel.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pw_rx_partial <= 1'b0;
        end else if (source_fire) begin
            if (pw_exp_in_ch_idx == (active_in_ch - 10'd1))
                pw_rx_partial <= 1'b0;
            else
                pw_rx_partial <= 1'b1;
        end
    end

    // ========================================================================
    // SOURCE BUFFER READ READY
    // ========================================================================
    assign stem_out_ready =
        (state == S_B1 && !handoff_pending && active_source_allow) ?
        (pw_exp_in_ready && b1_res_wr_ready) : 1'b0;
    assign b3b4_fifo_rd_ready =
        (state == S_B4 && !handoff_pending && active_source_allow) ?
        pw_exp_in_ready : 1'b0;
    assign b4b5_fifo_rd_ready =
        (state == S_B5 && !handoff_pending && active_source_allow) ?
        (pw_exp_in_ready && b5_res_wr_ready) : 1'b0;
    assign b5b6_fifo_rd_ready =
        (state == S_B6 && !handoff_pending && active_source_allow) ?
        pw_exp_in_ready : 1'b0;
    assign b6b7_fifo_rd_ready =
        (state == S_B7 && !handoff_pending && active_source_allow) ?
        (pw_exp_in_ready && b7_res_wr_ready) : 1'b0;
    // IMPORTANT: FIFO pop must be identical to the actual PW-Expand source fire.
    // When the source limit is reached, source VALID and FIFO READY both stop.
    assign b1b2_fifo_rd_ready =
        (state == S_B2 && !handoff_pending && active_source_allow) ?
        pw_exp_in_ready : 1'b0;
    assign b2b3_fifo_rd_ready =
        (state == S_B3 && !handoff_pending && active_source_allow) ?
        (pw_exp_in_ready && b3_res_wr_ready) : 1'b0;

    // ========================================================================
    // INPUT ROW/COL TRACKER FOR THE SHARED EXPAND OUTPUT
    // ========================================================================
    reg [9:0] expand_row;
    reg [9:0] expand_col;
    reg [3:0] expand_prev_state;

    wire [9:0] active_in_width =
        (state == S_B1) ? B1_IN_W :
        (state == S_B2) ? B2_IN_W :
        (state == S_B3) ? B3_IN_W :
        (state == S_B4) ? B4_IN_W :
        (state == S_B5) ? B5_IN_W :
        (state == S_B6) ? B6_IN_W :
        (state == S_B7) ? B7_IN_W :
        10'd0;

    wire [9:0] active_in_height =
        (state == S_B1) ? B1_IN_H :
        (state == S_B2) ? B2_IN_H :
        (state == S_B3) ? B3_IN_H :
        (state == S_B4) ? B4_IN_H :
        (state == S_B5) ? B5_IN_H :
        (state == S_B6) ? B6_IN_H :
        (state == S_B7) ? B7_IN_H :
        10'd0;

    wire [9:0] active_exp_ch =
        (state == S_B1) ? B1_EXP :
        (state == S_B2) ? B2_EXP :
        (state == S_B3) ? B3_EXP :
        (state == S_B4) ? B4_EXP :
        (state == S_B5) ? B5_EXP :
        (state == S_B6) ? B6_EXP :
        (state == S_B7) ? B7_EXP :
        10'd0;

    // ========================================================================
    // SOURCE LOOK-AHEAD LIMIT
    // ========================================================================
    // PW Expand may accept the next input vector before the controller has
    // finished draining the current expanded vector.  That is legal for the
    // arithmetic engine, but it is NOT legal for our 3-row controller buffer:
    // the source must never run beyond the rows required by the current output
    // row.  Otherwise an extra vector can remain stranded in PW Expand while
    // the controller is already in ST_WINDOW/ST_WAIT_LAUNCH.
    //
    // Limit is expressed in scalar HWC handshakes.  For a 3x3 SAME convolution
    // the current output row r needs input rows 0 .. r*stride+1, therefore:
    //     required_rows = min(r*stride + 2, input_height).
    function [31:0] source_scalar_limit;
        input [7:0]  completed_output_rows;
        input integer stride_i;
        input integer width_i;
        input integer in_ch_i;
        input integer height_i;
        integer req_rows;
        begin
            req_rows = completed_output_rows * stride_i + 2;
            if (req_rows > height_i)
                req_rows = height_i;
            source_scalar_limit = req_rows * width_i * in_ch_i;
        end
    endfunction

    wire [31:0] b1_source_limit =
        source_scalar_limit(b1_rows_produced, 1, B1_IN_W, 24, B1_IN_H);
    wire [31:0] b2_source_limit =
        source_scalar_limit(b2_rows_produced, 1, B2_IN_W, 24, B2_IN_H);
    wire [31:0] b3_source_limit =
        source_scalar_limit(b3_rows_produced, 1, B3_IN_W, 32, B3_IN_H);
    wire [31:0] b4_source_limit =
        source_scalar_limit(b4_rows_produced, 2, B4_IN_W, 32, B4_IN_H);
    wire [31:0] b5_source_limit =
        source_scalar_limit(b5_rows_produced, 1, B5_IN_W, 64, B5_IN_H);
    wire [31:0] b6_source_limit =
        source_scalar_limit(b6_rows_produced, 2, B6_IN_W, 64, B6_IN_H);
    wire [31:0] b7_source_limit =
        source_scalar_limit(b7_rows_consumed, 1, B7_IN_W, 128, B7_IN_H);

    wire [31:0] active_source_count_now =
        (state == S_B1) ? b1_source_count :
        (state == S_B2) ? b2_source_count :
        (state == S_B3) ? b3_source_count :
        (state == S_B4) ? b4_source_count :
        (state == S_B5) ? b5_source_count :
        (state == S_B6) ? b6_source_count :
        (state == S_B7) ? b7_source_count :
        32'd0;

    wire [31:0] active_source_limit =
        (state == S_B1) ? b1_source_limit :
        (state == S_B2) ? b2_source_limit :
        (state == S_B3) ? b3_source_limit :
        (state == S_B4) ? b4_source_limit :
        (state == S_B5) ? b5_source_limit :
        (state == S_B6) ? b6_source_limit :
        (state == S_B7) ? b7_source_limit :
        32'd0;

    wire active_source_allow =
        (active_source_count_now < active_source_limit);

    // ========================================================================
    // SHARED DW
    // ========================================================================
    wire       dw_in_valid;
    wire [7:0] dw_in_ch_idx;
    wire [7:0] dw_p00, dw_p01, dw_p02;
    wire [7:0] dw_p10, dw_p11, dw_p12;
    wire [7:0] dw_p20, dw_p21, dw_p22;
    wire       dw_ready;

    wire [7:0] dw_out_pixel;
    wire [7:0] dw_out_ch_idx;
    wire       dw_out_valid;
    wire       dw_out_ready;
    wire       dw_busy;

    assign dw_out_ready = pw_proj_in_ready;

    dw_engine u_dw (
        .clk(clk),
        .rst_n(rst_n),
        .block_sel(active_block),
        .in_valid(dw_in_valid),
        .p00(dw_p00), .p01(dw_p01), .p02(dw_p02),
        .p10(dw_p10), .p11(dw_p11), .p12(dw_p12),
        .p20(dw_p20), .p21(dw_p21), .p22(dw_p22),
        .in_ch_idx(dw_in_ch_idx),
        .ready(dw_ready),
        .dw_out(dw_out_pixel),
        .out_ch_idx(dw_out_ch_idx),
        .out_valid(dw_out_valid),
        .out_ready(dw_out_ready),
        .busy(dw_busy)
    );

    // ========================================================================
    // SHARED PW PROJECT
    // ========================================================================
    wire       pw_proj_in_valid;
    wire [7:0] pw_proj_in_pixel;
    wire [7:0] pw_proj_in_ch_idx;
    wire       pw_proj_in_ready;

    wire [7:0] pw_proj_out_pixel;
    wire [7:0] pw_proj_out_ch_idx;
    wire       pw_proj_out_valid;
    wire       pw_proj_out_ready;
    wire       pw_proj_busy;

    assign pw_proj_in_valid  = dw_out_valid;
    assign pw_proj_in_pixel  = dw_out_pixel;
    assign pw_proj_in_ch_idx = dw_out_ch_idx;

    pw_engine_project u_pw_project (
        .clk(clk),
        .rst_n(rst_n),
        .block_sel(active_block),
        .in_valid(pw_proj_in_valid),
        .pixel_in(pw_proj_in_pixel),
        .in_ch_idx(pw_proj_in_ch_idx),
        .ready(pw_proj_in_ready),
        .pw_out(pw_proj_out_pixel),
        .out_ch_idx(pw_proj_out_ch_idx),
        .out_valid(pw_proj_out_valid),
        .out_ready(pw_proj_out_ready),
        .busy(pw_proj_busy)
    );

    // ========================================================================
    // CONTROLLERS
    // ========================================================================
    // One controller per block; the shared arithmetic engines are muxed to the
    // currently active controller below.

    // ------------------------------- B1 ------------------------------------
    // All block controllers see the shared DW/PW project result, but only the
    // active controller is allowed to drive the shared bus.
    assign dw_in_valid =
        (state == S_B1) ? b1_dw_valid_i :
        (state == S_B2) ? b2_dw_valid_i :
        (state == S_B3) ? b3_dw_valid_i :
        (state == S_B4) ? b4_dw_valid_i :
        (state == S_B5) ? b5_dw_valid_i :
        (state == S_B6) ? b6_dw_valid_i :
        (state == S_B7) ? b7_dw_valid_i :
        1'b0;

    assign dw_in_ch_idx =
        (state == S_B1) ? b1_dw_ch_idx :
        (state == S_B2) ? b2_dw_ch_idx :
        (state == S_B3) ? b3_dw_ch_idx :
        (state == S_B4) ? b4_dw_ch_idx :
        (state == S_B5) ? b5_dw_ch_idx :
        (state == S_B6) ? b6_dw_ch_idx :
        (state == S_B7) ? b7_dw_ch_idx :
        8'd0;

    assign dw_p00 = (state == S_B1) ? b1_dw_p00 : (state == S_B2) ? b2_dw_p00 : (state == S_B3) ? b3_dw_p00 : (state == S_B4) ? b4_dw_p00 : (state == S_B5) ? b5_dw_p00 : (state == S_B6) ? b6_dw_p00 : b7_dw_p00;
    assign dw_p01 = (state == S_B1) ? b1_dw_p01 : (state == S_B2) ? b2_dw_p01 : (state == S_B3) ? b3_dw_p01 : (state == S_B4) ? b4_dw_p01 : (state == S_B5) ? b5_dw_p01 : (state == S_B6) ? b6_dw_p01 : b7_dw_p01;
    assign dw_p02 = (state == S_B1) ? b1_dw_p02 : (state == S_B2) ? b2_dw_p02 : (state == S_B3) ? b3_dw_p02 : (state == S_B4) ? b4_dw_p02 : (state == S_B5) ? b5_dw_p02 : (state == S_B6) ? b6_dw_p02 : b7_dw_p02;
    assign dw_p10 = (state == S_B1) ? b1_dw_p10 : (state == S_B2) ? b2_dw_p10 : (state == S_B3) ? b3_dw_p10 : (state == S_B4) ? b4_dw_p10 : (state == S_B5) ? b5_dw_p10 : (state == S_B6) ? b6_dw_p10 : b7_dw_p10;
    assign dw_p11 = (state == S_B1) ? b1_dw_p11 : (state == S_B2) ? b2_dw_p11 : (state == S_B3) ? b3_dw_p11 : (state == S_B4) ? b4_dw_p11 : (state == S_B5) ? b5_dw_p11 : (state == S_B6) ? b6_dw_p11 : b7_dw_p11;
    assign dw_p12 = (state == S_B1) ? b1_dw_p12 : (state == S_B2) ? b2_dw_p12 : (state == S_B3) ? b3_dw_p12 : (state == S_B4) ? b4_dw_p12 : (state == S_B5) ? b5_dw_p12 : (state == S_B6) ? b6_dw_p12 : b7_dw_p12;
    assign dw_p20 = (state == S_B1) ? b1_dw_p20 : (state == S_B2) ? b2_dw_p20 : (state == S_B3) ? b3_dw_p20 : (state == S_B4) ? b4_dw_p20 : (state == S_B5) ? b5_dw_p20 : (state == S_B6) ? b6_dw_p20 : b7_dw_p20;
    assign dw_p21 = (state == S_B1) ? b1_dw_p21 : (state == S_B2) ? b2_dw_p21 : (state == S_B3) ? b3_dw_p21 : (state == S_B4) ? b4_dw_p21 : (state == S_B5) ? b5_dw_p21 : (state == S_B6) ? b6_dw_p21 : b7_dw_p21;
    assign dw_p22 = (state == S_B1) ? b1_dw_p22 : (state == S_B2) ? b2_dw_p22 : (state == S_B3) ? b3_dw_p22 : (state == S_B4) ? b4_dw_p22 : (state == S_B5) ? b5_dw_p22 : (state == S_B6) ? b6_dw_p22 : b7_dw_p22;

    assign active_expand_ready =
        (state == S_B1) ? b1_expand_ready :
        (state == S_B2) ? b2_expand_ready :
        (state == S_B3) ? b3_expand_ready :
        (state == S_B4) ? b4_expand_ready :
        (state == S_B5) ? b5_expand_ready :
        (state == S_B6) ? b6_expand_ready :
        (state == S_B7) ? b7_expand_ready :
        1'b0;

    // PW Project input/output handshake is shared. Only active controller gets
    // the output stream and its ready determines backpressure.
    assign pw_proj_out_ready =
        (state == S_B1) ? b1_pw_ready :
        (state == S_B2) ? b2_pw_ready :
        (state == S_B3) ? b3_pw_ready :
        (state == S_B4) ? b4_pw_ready :
        (state == S_B5) ? b5_pw_ready :
        (state == S_B6) ? b6_pw_ready :
        (state == S_B7) ? b7_pw_ready :
        1'b0;

    // Shared DW ready comes back only to the active controller.
    assign b1_dw_ready = (state == S_B1) ? dw_ready : 1'b0;
    assign b2_dw_ready = (state == S_B2) ? dw_ready : 1'b0;
    assign b3_dw_ready = (state == S_B3) ? dw_ready : 1'b0;
    assign b4_dw_ready = (state == S_B4) ? dw_ready : 1'b0;
    assign b5_dw_ready = (state == S_B5) ? dw_ready : 1'b0;
    assign b6_dw_ready = (state == S_B6) ? dw_ready : 1'b0;
    assign b7_dw_ready = (state == S_B7) ? dw_ready : 1'b0;

    assign b1_pw_out_pixel = pw_proj_out_pixel;
    assign b2_pw_out_pixel = pw_proj_out_pixel;
    assign b3_pw_out_pixel = pw_proj_out_pixel;
    assign b4_pw_out_pixel = pw_proj_out_pixel;
    assign b5_pw_out_pixel = pw_proj_out_pixel;
    assign b6_pw_out_pixel = pw_proj_out_pixel;
    assign b7_pw_out_pixel = pw_proj_out_pixel;

    assign b1_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b2_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b3_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b4_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b5_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b6_pw_out_ch_idx = pw_proj_out_ch_idx;
    assign b7_pw_out_ch_idx = pw_proj_out_ch_idx;

    assign b1_pw_out_valid = (state == S_B1) ? pw_proj_out_valid : 1'b0;
    assign b2_pw_out_valid = (state == S_B2) ? pw_proj_out_valid : 1'b0;
    assign b3_pw_out_valid = (state == S_B3) ? pw_proj_out_valid : 1'b0;
    assign b4_pw_out_valid = (state == S_B4) ? pw_proj_out_valid : 1'b0;
    assign b5_pw_out_valid = (state == S_B5) ? pw_proj_out_valid : 1'b0;
    assign b6_pw_out_valid = (state == S_B6) ? pw_proj_out_valid : 1'b0;
    assign b7_pw_out_valid = (state == S_B7) ? pw_proj_out_valid : 1'b0;

    // ========================================================================
    // B1 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(24), .EXP_CH(48), .OUT_CH(24), .HAS_RESIDUAL(1),
        .STRIDE(1), .IMG_WIDTH(96), .IMG_HEIGHT(96),
        .RES_MAIN_MULT_FILE(RES_B1_MAIN_MULT_FILE),
        .RES_SKIP_MULT_FILE(RES_B1_SKIP_MULT_FILE),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b1_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B1) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b1_expand_ready),
        .res_fifo_rd_data(b1_res_data),
        .res_fifo_empty(b1_res_empty),
        .res_fifo_rd_en(b1_res_rd_en),
        .dw_in_valid(b1_dw_valid_i),
        .dw_ch_idx(b1_dw_ch_idx),
        .dw_p00(b1_dw_p00), .dw_p01(b1_dw_p01), .dw_p02(b1_dw_p02),
        .dw_p10(b1_dw_p10), .dw_p11(b1_dw_p11), .dw_p12(b1_dw_p12),
        .dw_p20(b1_dw_p20), .dw_p21(b1_dw_p21), .dw_p22(b1_dw_p22),
        .dw_ready(b1_dw_ready),
        .pw_out(b1_pw_out_pixel), .pw_out_ch_idx(b1_pw_out_ch_idx),
        .pw_out_valid(b1_pw_out_valid), .pw_out_ready(b1_pw_ready),
        .block_out_pixel(b1_block_out_pixel),
        .block_out_ch_idx(b1_block_out_ch_idx),
        .block_out_valid(b1_block_out_valid),
        .block_out_ready(b1_block_out_ready),
        .block_busy(b1_busy),
        .pause_safe(b1_pause_safe),
        .scheduler_hold(b1_scheduler_hold)
    );

    // ========================================================================
    // B2 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(24), .EXP_CH(48), .OUT_CH(32), .HAS_RESIDUAL(0),
        .STRIDE(1), .IMG_WIDTH(96), .IMG_HEIGHT(96),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b2_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B2) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b2_expand_ready),
        .res_fifo_rd_data({24{8'd0}}),
        .res_fifo_empty(1'b1),
        .res_fifo_rd_en(),
        .dw_in_valid(b2_dw_valid_i),
        .dw_ch_idx(b2_dw_ch_idx),
        .dw_p00(b2_dw_p00), .dw_p01(b2_dw_p01), .dw_p02(b2_dw_p02),
        .dw_p10(b2_dw_p10), .dw_p11(b2_dw_p11), .dw_p12(b2_dw_p12),
        .dw_p20(b2_dw_p20), .dw_p21(b2_dw_p21), .dw_p22(b2_dw_p22),
        .dw_ready(b2_dw_ready),
        .pw_out(b2_pw_out_pixel), .pw_out_ch_idx(b2_pw_out_ch_idx),
        .pw_out_valid(b2_pw_out_valid), .pw_out_ready(b2_pw_ready),
        .block_out_pixel(b2_block_out_pixel),
        .block_out_ch_idx(b2_block_out_ch_idx),
        .block_out_valid(b2_block_out_valid),
        .block_out_ready(b2_block_out_ready),
        .block_busy(b2_busy),
        .pause_safe(b2_pause_safe),
        .scheduler_hold(b2_scheduler_hold)
    );

    // ========================================================================
    // B3 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(32), .EXP_CH(64), .OUT_CH(32), .HAS_RESIDUAL(1),
        .STRIDE(1), .IMG_WIDTH(96), .IMG_HEIGHT(96),
        .RES_MAIN_MULT_FILE(RES_B3_MAIN_MULT_FILE),
        .RES_SKIP_MULT_FILE(RES_B3_SKIP_MULT_FILE),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b3_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B3) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b3_expand_ready),
        .res_fifo_rd_data(b3_res_data),
        .res_fifo_empty(b3_res_empty),
        .res_fifo_rd_en(b3_res_rd_en),
        .dw_in_valid(b3_dw_valid_i),
        .dw_ch_idx(b3_dw_ch_idx),
        .dw_p00(b3_dw_p00), .dw_p01(b3_dw_p01), .dw_p02(b3_dw_p02),
        .dw_p10(b3_dw_p10), .dw_p11(b3_dw_p11), .dw_p12(b3_dw_p12),
        .dw_p20(b3_dw_p20), .dw_p21(b3_dw_p21), .dw_p22(b3_dw_p22),
        .dw_ready(b3_dw_ready),
        .pw_out(b3_pw_out_pixel), .pw_out_ch_idx(b3_pw_out_ch_idx),
        .pw_out_valid(b3_pw_out_valid), .pw_out_ready(b3_pw_ready),
        .block_out_pixel(b3_block_out_pixel),
        .block_out_ch_idx(b3_block_out_ch_idx),
        .block_out_valid(b3_block_out_valid),
        .block_out_ready(b3_block_out_ready),
        .block_busy(b3_busy),
        .pause_safe(b3_pause_safe),
        .scheduler_hold(b3_scheduler_hold)
    );

    // ========================================================================
    // B4 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(32), .EXP_CH(64), .OUT_CH(64), .HAS_RESIDUAL(0),
        .STRIDE(2), .IMG_WIDTH(96), .IMG_HEIGHT(96),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b4_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B4) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b4_expand_ready),
        .res_fifo_rd_data({32{8'd0}}),
        .res_fifo_empty(1'b1),
        .res_fifo_rd_en(),
        .dw_in_valid(b4_dw_valid_i),
        .dw_ch_idx(b4_dw_ch_idx),
        .dw_p00(b4_dw_p00), .dw_p01(b4_dw_p01), .dw_p02(b4_dw_p02),
        .dw_p10(b4_dw_p10), .dw_p11(b4_dw_p11), .dw_p12(b4_dw_p12),
        .dw_p20(b4_dw_p20), .dw_p21(b4_dw_p21), .dw_p22(b4_dw_p22),
        .dw_ready(b4_dw_ready),
        .pw_out(b4_pw_out_pixel), .pw_out_ch_idx(b4_pw_out_ch_idx),
        .pw_out_valid(b4_pw_out_valid), .pw_out_ready(b4_pw_ready),
        .block_out_pixel(b4_block_out_pixel),
        .block_out_ch_idx(b4_block_out_ch_idx),
        .block_out_valid(b4_block_out_valid),
        .block_out_ready(b4_block_out_ready),
        .block_busy(b4_busy),
        .pause_safe(b4_pause_safe),
        .scheduler_hold(b4_scheduler_hold)
    );

    // ========================================================================
    // B5 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(64), .EXP_CH(128), .OUT_CH(64), .HAS_RESIDUAL(1),
        .STRIDE(1), .IMG_WIDTH(48), .IMG_HEIGHT(48),
        .RES_MAIN_MULT_FILE(RES_B5_MAIN_MULT_FILE),
        .RES_SKIP_MULT_FILE(RES_B5_SKIP_MULT_FILE),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b5_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B5) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b5_expand_ready),
        .res_fifo_rd_data(b5_res_data),
        .res_fifo_empty(b5_res_empty),
        .res_fifo_rd_en(b5_res_rd_en),
        .dw_in_valid(b5_dw_valid_i),
        .dw_ch_idx(b5_dw_ch_idx),
        .dw_p00(b5_dw_p00), .dw_p01(b5_dw_p01), .dw_p02(b5_dw_p02),
        .dw_p10(b5_dw_p10), .dw_p11(b5_dw_p11), .dw_p12(b5_dw_p12),
        .dw_p20(b5_dw_p20), .dw_p21(b5_dw_p21), .dw_p22(b5_dw_p22),
        .dw_ready(b5_dw_ready),
        .pw_out(b5_pw_out_pixel), .pw_out_ch_idx(b5_pw_out_ch_idx),
        .pw_out_valid(b5_pw_out_valid), .pw_out_ready(b5_pw_ready),
        .block_out_pixel(b5_block_out_pixel),
        .block_out_ch_idx(b5_block_out_ch_idx),
        .block_out_valid(b5_block_out_valid),
        .block_out_ready(b5_block_out_ready),
        .block_busy(b5_busy),
        .pause_safe(b5_pause_safe),
        .scheduler_hold(b5_scheduler_hold)
    );

    // ========================================================================
    // B6 CONTROLLER
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(64), .EXP_CH(128), .OUT_CH(128), .HAS_RESIDUAL(0),
        .STRIDE(2), .IMG_WIDTH(48), .IMG_HEIGHT(48),
        .ROW_BANKS(3), .ENABLE_ROW_LOOKAHEAD(0)
    ) u_b6_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B6) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b6_expand_ready),
        .res_fifo_rd_data({64{8'd0}}),
        .res_fifo_empty(1'b1),
        .res_fifo_rd_en(),
        .dw_in_valid(b6_dw_valid_i),
        .dw_ch_idx(b6_dw_ch_idx),
        .dw_p00(b6_dw_p00), .dw_p01(b6_dw_p01), .dw_p02(b6_dw_p02),
        .dw_p10(b6_dw_p10), .dw_p11(b6_dw_p11), .dw_p12(b6_dw_p12),
        .dw_p20(b6_dw_p20), .dw_p21(b6_dw_p21), .dw_p22(b6_dw_p22),
        .dw_ready(b6_dw_ready),
        .pw_out(b6_pw_out_pixel), .pw_out_ch_idx(b6_pw_out_ch_idx),
        .pw_out_valid(b6_pw_out_valid), .pw_out_ready(b6_pw_ready),
        .block_out_pixel(b6_block_out_pixel),
        .block_out_ch_idx(b6_block_out_ch_idx),
        .block_out_valid(b6_block_out_valid),
        .block_out_ready(b6_block_out_ready),
        .block_busy(b6_busy),
        .pause_safe(b6_pause_safe),
        .scheduler_hold(b6_scheduler_hold)
    );



    // ========================================================================
    // B7 CONTROLLER : 128 -> 256 -> 128, 24x24, S1 + residual
    // ========================================================================
    block_controller_stream_row_stage2 #(
        .IN_CH(128), .EXP_CH(256), .OUT_CH(128), .HAS_RESIDUAL(1),
        .STRIDE(1), .IMG_WIDTH(24), .IMG_HEIGHT(24),
        .RES_MAIN_MULT_FILE(RES_B7_MAIN_MULT_FILE),
        .RES_SKIP_MULT_FILE(RES_B7_SKIP_MULT_FILE),
        .ROW_BANKS(4), .ENABLE_ROW_LOOKAHEAD(1)
    ) u_b7_ctrl (
        .clk(clk), .rst_n(rst_n),
        .expand_in_valid((state == S_B7) ? pw_exp_out_valid : 1'b0),
        .expand_in_pixel(pw_exp_out_pixel),
        .expand_in_ch_idx(pw_exp_out_ch_idx),
        .expand_in_row(expand_row),
        .expand_in_col(expand_col),
        .expand_in_ready(b7_expand_ready),
        .res_fifo_rd_data(b7_res_data),
        .res_fifo_empty(b7_res_empty),
        .res_fifo_rd_en(b7_res_rd_en),
        .dw_in_valid(b7_dw_valid_i),
        .dw_ch_idx(b7_dw_ch_idx),
        .dw_p00(b7_dw_p00), .dw_p01(b7_dw_p01), .dw_p02(b7_dw_p02),
        .dw_p10(b7_dw_p10), .dw_p11(b7_dw_p11), .dw_p12(b7_dw_p12),
        .dw_p20(b7_dw_p20), .dw_p21(b7_dw_p21), .dw_p22(b7_dw_p22),
        .dw_ready(b7_dw_ready),
        .pw_out(b7_pw_out_pixel), .pw_out_ch_idx(b7_pw_out_ch_idx),
        .pw_out_valid(b7_pw_out_valid), .pw_out_ready(b7_pw_ready),
        .block_out_pixel(b7_block_out_pixel),
        .block_out_ch_idx(b7_block_out_ch_idx),
        .block_out_valid(b7_block_out_valid),
        .block_out_ready(b7_block_out_ready),
        .block_busy(b7_busy),
        .pause_safe(b7_pause_safe),
        .scheduler_hold(b7_scheduler_hold)
    );

    // ========================================================================
    // HEAD (B7 output is accepted directly by Head)
    // ========================================================================
    wire       head_ready;
    wire       head_out_ready;
    wire [7:0] head_out_pixel;
    wire [7:0] head_out_ch_idx;
    wire       head_out_valid;
    wire       head_busy;

    assign b7_block_out_ready = (state == S_B7) ? head_ready : 1'b0;

    mobilenet_head u_head (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(b7_block_out_valid),
        .in_pixel(b7_block_out_pixel),
        .in_ch_idx(b7_block_out_ch_idx),
        .ready(head_ready),
        .out_ready(head_out_ready),
        .out_pixel(head_out_pixel),
        .out_ch_idx(head_out_ch_idx),
        .out_valid(head_out_valid),
        .busy(head_busy)
    );

    // ========================================================================
    // GAP
    // ========================================================================
    wire       gap_ready;
    wire       gap_out_ready;
    wire [7:0] gap_out_value;
    wire [7:0] gap_out_ch_idx;
    wire       gap_out_valid;
    wire       gap_frame_done;

    gap_avg_pool #(
        .WIDTH(24), .HEIGHT(24), .CHANNELS(256)
    ) u_gap (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(head_out_valid),
        .pixel_in(head_out_pixel),
        .in_ch_idx(head_out_ch_idx),
        .ready(gap_ready),
        .gap_out(gap_out_value),
        .out_ch_idx(gap_out_ch_idx),
        .out_valid(gap_out_valid),
        .out_ready(gap_out_ready),
        .frame_done(gap_frame_done)
    );

    // Head/GAP are also true ready/valid stages.
    // GAP is the consumer of Head output; FC is the consumer of GAP output.
    assign head_out_ready = gap_ready;
    assign gap_out_ready  = fc_ready;

    // ========================================================================
    // FC
    // ========================================================================
    wire       fc_ready;

    fc_classifier #(
        .IN_CH(256), .NUM_CLASSES(7), .PARALLEL_CLASS(2)
    ) u_fc (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(gap_out_valid),
        .gap_in(gap_out_value),
        .in_ch_idx(gap_out_ch_idx),
        .ready(fc_ready),
        .fc_out(fc_out),
        .class_idx(fc_class_idx),
        .out_valid(fc_out_valid),
        .frame_done(fc_frame_done)
    );

    // ========================================================================
    // INTER-STAGE BUFFERS
    // ========================================================================
    // B1..B4 now produce completed HWC rows into four-row FIFOs.
    // B6 still writes its output to a legacy full-frame buffer; B5->B6 is the
    // current streaming migration boundary.
    assign b1_block_out_ready = b1b2_fifo_wr_ready && (state == S_B1);
    assign b2_block_out_ready = b2b3_fifo_wr_ready && (state == S_B2);
    assign b3_block_out_ready = b3b4_fifo_wr_ready && (state == S_B3);
    assign b4_block_out_ready = b4b5_fifo_wr_ready && (state == S_B4);
    assign b5_block_out_ready = b5b6_fifo_wr_ready && (state == S_B5);
    assign b6_block_out_ready = b6b7_fifo_wr_ready && (state == S_B6);

    // ------------------------------------------------------------------------
    // B1 -> B2 row FIFO: 4 rows x 96 pixels x 24 channels x 8 bits.
    // ------------------------------------------------------------------------
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(96),
        .HEIGHT(96),
        .CHANNELS(24),
        .DEPTH(3),
        .DATA_WIDTH(8)
    ) u_b1_b2_row_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_valid(b1_block_out_valid),
        .wr_pixel(b1_block_out_pixel),
        .wr_ch_idx(b1_block_out_ch_idx),
        .wr_ready(b1b2_fifo_wr_ready),
        .completed_rows(b1b2_fifo_rows),
        .rd_valid(b1b2_fifo_rd_valid),
        .rd_pixel(b1b2_fifo_rd_pixel),
        .rd_ch_idx(b1b2_fifo_rd_ch_idx),
        .rd_row_idx(b1b2_fifo_rd_row_idx),
        .rd_ready(b1b2_fifo_rd_ready),
        .empty(b1b2_fifo_empty),
        .full(b1b2_fifo_full)
    );

    // ------------------------------------------------------------------------
    // B2 -> B3 row FIFO: 4 rows x 96 pixels x 32 channels.
    // ------------------------------------------------------------------------
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(96),
        .HEIGHT(96),
        .CHANNELS(32),
        .DEPTH(3),
        .DATA_WIDTH(8)
    ) u_b2_b3_row_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_valid(b2_block_out_valid),
        .wr_pixel(b2_block_out_pixel),
        .wr_ch_idx(b2_block_out_ch_idx),
        .wr_ready(b2b3_fifo_wr_ready),
        .completed_rows(b2b3_fifo_rows),
        .rd_valid(b2b3_fifo_rd_valid),
        .rd_pixel(b2b3_fifo_rd_pixel),
        .rd_ch_idx(b2b3_fifo_rd_ch_idx),
        .rd_row_idx(b2b3_fifo_rd_row_idx),
        .rd_ready(b2b3_fifo_rd_ready),
        .empty(b2b3_fifo_empty),
        .full(b2b3_fifo_full)
    );

    // ------------------------------------------------------------------------
    // B3 -> B4 row FIFO: replaces the 96x96x32 full-frame B3 buffer.
    // ------------------------------------------------------------------------
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(96),
        .HEIGHT(96),
        .CHANNELS(32),
        .DEPTH(3),
        .DATA_WIDTH(8)
    ) u_b3_b4_row_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_valid(b3_block_out_valid),
        .wr_pixel(b3_block_out_pixel),
        .wr_ch_idx(b3_block_out_ch_idx),
        .wr_ready(b3b4_fifo_wr_ready),
        .completed_rows(b3b4_fifo_rows),
        .rd_valid(b3b4_fifo_rd_valid),
        .rd_pixel(b3b4_fifo_rd_pixel),
        .rd_ch_idx(b3b4_fifo_rd_ch_idx),
        .rd_row_idx(b3b4_fifo_rd_row_idx),
        .rd_ready(b3b4_fifo_rd_ready),
        .empty(b3b4_fifo_empty),
        .full(b3b4_fifo_full)
    );

    // ------------------------------------------------------------------------
    // B4 -> B5 row FIFO: 4 rows x 48 pixels x 64 channels x 8 bits.
    // ------------------------------------------------------------------------
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(48),
        .HEIGHT(48),
        .CHANNELS(64),
        .DEPTH(3),
        .DATA_WIDTH(8)
    ) u_b4_b5_row_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_valid(b4_block_out_valid),
        .wr_pixel(b4_block_out_pixel),
        .wr_ch_idx(b4_block_out_ch_idx),
        .wr_ready(b4b5_fifo_wr_ready),
        .completed_rows(b4b5_fifo_rows),
        .rd_valid(b4b5_fifo_rd_valid),
        .rd_pixel(b4b5_fifo_rd_pixel),
        .rd_ch_idx(b4b5_fifo_rd_ch_idx),
        .rd_row_idx(b4b5_fifo_rd_row_idx),
        .rd_ready(b4b5_fifo_rd_ready),
        .empty(b4b5_fifo_empty),
        .full(b4b5_fifo_full)
    );

    // B5 -> B6 row FIFO: 4 rows x 48 pixels x 64 channels x 8 bits.
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(48), .HEIGHT(48), .CHANNELS(64), .DEPTH(3), .DATA_WIDTH(8)
    ) u_b5_b6_row_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b5_block_out_valid),
        .wr_pixel(b5_block_out_pixel),
        .wr_ch_idx(b5_block_out_ch_idx),
        .wr_ready(b5b6_fifo_wr_ready),
        .completed_rows(b5b6_fifo_rows),
        .rd_valid(b5b6_fifo_rd_valid),
        .rd_pixel(b5b6_fifo_rd_pixel),
        .rd_ch_idx(b5b6_fifo_rd_ch_idx),
        .rd_row_idx(b5b6_fifo_rd_row_idx),
        .rd_ready(b5b6_fifo_rd_ready),
        .empty(b5b6_fifo_empty),
        .full(b5b6_fifo_full)
    );

    // B6 -> B7 row FIFO: 4 rows x 24 pixels x 128 channels x 8 bits.
    // This removes the legacy 24x24x128 B6 frame buffer.
    stream_interstage_row_fifo_hwc_stage2 #(
        .WIDTH(24), .HEIGHT(24), .CHANNELS(128), .DEPTH(3), .DATA_WIDTH(8)
    ) u_b6_b7_row_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b6_block_out_valid),
        .wr_pixel(b6_block_out_pixel),
        .wr_ch_idx(b6_block_out_ch_idx),
        .wr_ready(b6b7_fifo_wr_ready),
        .completed_rows(b6b7_fifo_rows),
        .rd_valid(b6b7_fifo_rd_valid),
        .rd_pixel(b6b7_fifo_rd_pixel),
        .rd_ch_idx(b6b7_fifo_rd_ch_idx),
        .rd_row_idx(b6b7_fifo_rd_row_idx),
        .rd_ready(b6b7_fifo_rd_ready),
        .empty(b6b7_fifo_empty),
        .full(b6b7_fifo_full)
    );

    // ========================================================================
    // RESIDUAL VECTOR STORES
    // ========================================================================
    // Write one scalar per HWC channel. At the last channel of each spatial
    // pixel the store commits one packed residual vector.

    assign b1_res_wr_valid = source_fire && (state == S_B1);
    assign b3_res_wr_valid = source_fire && (state == S_B3);
    assign b5_res_wr_valid = source_fire && (state == S_B5);
    assign b7_res_wr_valid = source_fire && (state == S_B7);

    top_residual_vector_store_row4_streaming #(
        .WIDTH(96), .HEIGHT(96), .IN_CH(24)
    ) u_b1_res (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b1_res_wr_valid),
        .wr_pixel(pw_exp_in_pixel),
        .wr_ch_idx(pw_exp_in_ch_idx),
        .wr_ready(b1_res_wr_ready),
        .rd_data(b1_res_data),
        .empty(b1_res_empty),
        .rd_en(b1_res_rd_en)
    );

    top_residual_vector_store_row4_streaming #(
        .WIDTH(96), .HEIGHT(96), .IN_CH(32)
    ) u_b3_res (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b3_res_wr_valid),
        .wr_pixel(pw_exp_in_pixel),
        .wr_ch_idx(pw_exp_in_ch_idx),
        .wr_ready(b3_res_wr_ready),
        .rd_data(b3_res_data),
        .empty(b3_res_empty),
        .rd_en(b3_res_rd_en)
    );

    top_residual_vector_store_row4_streaming #(
        .WIDTH(48), .HEIGHT(48), .IN_CH(64)
    ) u_b5_res (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b5_res_wr_valid),
        .wr_pixel(pw_exp_in_pixel),
        .wr_ch_idx(pw_exp_in_ch_idx),
        .wr_ready(b5_res_wr_ready),
        .rd_data(b5_res_data),
        .empty(b5_res_empty),
        .rd_en(b5_res_rd_en)
    );

    top_residual_vector_store_row4_streaming #(
        .WIDTH(24), .HEIGHT(24), .IN_CH(128)
    ) u_b7_res (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(b7_res_wr_valid),
        .wr_pixel(pw_exp_in_pixel),
        .wr_ch_idx(pw_exp_in_ch_idx),
        .wr_ready(b7_res_wr_ready),
        .rd_data(b7_res_data),
        .empty(b7_res_empty),
        .rd_en(b7_res_rd_en)
    );

    // ========================================================================
    // EXPAND ROW/COL COUNTER
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expand_row       <= 10'd0;
            expand_col       <= 10'd0;
            expand_prev_state<= S_IDLE;
        end else begin
            if (state != expand_prev_state) begin
                // Each block has its own spatial source sequence. Reset the
                // debug coordinate when the scheduler changes active blocks.
                expand_row <= 10'd0;
                expand_col <= 10'd0;
            end else if (pw_exp_out_valid && active_expand_ready &&
                         (pw_exp_out_ch_idx == active_exp_ch-1)) begin
                if (expand_col == active_in_width-1) begin
                    expand_col <= 10'd0;
                    if (expand_row < active_in_height-1)
                        expand_row <= expand_row + 1'b1;
                end else begin
                    expand_col <= expand_col + 1'b1;
                end
            end
            expand_prev_state <= state;
        end
    end

    // ========================================================================
    // STAGE TRANSITION CONTROL
    // =======================================================================

    // Global counters are kept for B3-B7. B1/B2 are time-multiplexed, so
    // they need independent counters; otherwise B2 completion includes B1
    // transactions as well.
    reg [31:0] source_fire_count;
    reg [31:0] output_fire_count;
    reg [31:0] b1_source_count;
    reg [31:0] b1_output_count;
    reg [31:0] b2_source_count;
    reg [31:0] b2_output_count;
    reg [31:0] b3_source_count;
    reg [31:0] b3_output_count;
    reg [31:0] b4_source_count;
    reg [31:0] b4_output_count;
    reg [31:0] b5_source_count;
    reg [31:0] b5_output_count;
    reg [31:0] b6_source_count;
    reg [31:0] b6_output_count;
    reg [31:0] b7_source_count;
    reg [2:0]  last_completed_block;
    reg [31:0] last_completed_source_count;
    reg [31:0] last_completed_output_count;
    reg [6:0]  stage_completed_mask;

    assign active_source_fire_count =
        (state == S_B1) ? b1_source_count :
        (state == S_B2) ? b2_source_count :
        (state == S_B3) ? b3_source_count :
        (state == S_B4) ? b4_source_count :
        (state == S_B5) ? b5_source_count :
        (state == S_B6) ? b6_source_count :
        (state == S_B7) ? b7_source_count :
        source_fire_count;

    assign active_output_fire_count =
        (state == S_B1) ? b1_output_count :
        (state == S_B2) ? b2_output_count :
        (state == S_B3) ? b3_output_count :
        (state == S_B4) ? b4_output_count :
        (state == S_B5) ? b5_output_count :
        (state == S_B6) ? b6_output_count :
        output_fire_count;
    assign last_completed_block_debug = last_completed_block;
    assign last_completed_source_count_debug = last_completed_source_count;
    assign last_completed_output_count_debug = last_completed_output_count;
    assign stage_completed_mask_debug = stage_completed_mask;

    wire active_output_valid =
        (state == S_B1) ? b1_block_out_valid :
        (state == S_B2) ? b2_block_out_valid :
        (state == S_B3) ? b3_block_out_valid :
        (state == S_B4) ? b4_block_out_valid :
        (state == S_B5) ? b5_block_out_valid :
        (state == S_B6) ? b6_block_out_valid :
        (state == S_B7) ? b7_block_out_valid :
        1'b0;

    wire active_output_ready =
        (state == S_B1) ? b1_block_out_ready :
        (state == S_B2) ? b2_block_out_ready :
        (state == S_B3) ? b3_block_out_ready :
        (state == S_B4) ? b4_block_out_ready :
        (state == S_B5) ? b5_block_out_ready :
        (state == S_B6) ? b6_block_out_ready :
        (state == S_B7) ? b7_block_out_ready :
        1'b0;

    wire active_output_fire = active_output_valid && active_output_ready;


    // ========================================================================
    // B1 INPUT/OUTPUT HEX-DUMP DEBUG TAPS (REGISTERED SNAPSHOTS)
    // ========================================================================
    // Every dbg_*_hex_* record is captured on the same clock edge that accepts
    // the transaction. Thus the pixel, channel and zero-based index are aligned
    // in SignalTap. *_fire is a registered one-cycle pulse for the captured item.
    // Input = stem -> PW Expand acceptance. Output = B1 -> B1/B2 boundary acceptance.
    // Expected full-frame count: 96*96*24 = 221184 bytes, indices 0..221183.
    (* preserve, noprune *) reg [31:0] dbg_b1_in_hex_idx;
    (* preserve, noprune *) reg [31:0] dbg_b1_hex_idx;

    (* preserve, noprune *) reg [31:0] dbg_b1_in_hex_count;
    (* preserve, noprune *) reg [31:0] dbg_b1_hex_count;

    (* preserve, noprune *) reg [7:0] dbg_b1_in_hex_pixel;
    (* preserve, noprune *) reg [7:0] dbg_b1_in_hex_ch_idx;
    (* preserve, noprune *) reg       dbg_b1_in_hex_valid;
    (* preserve, noprune *) reg       dbg_b1_in_hex_ready;
    (* preserve, noprune *) reg       dbg_b1_in_hex_fire;

    (* preserve, noprune *) reg [7:0] dbg_b1_hex_pixel;
    (* preserve, noprune *) reg [7:0] dbg_b1_hex_ch_idx;
    (* preserve, noprune *) reg       dbg_b1_hex_valid;
    (* preserve, noprune *) reg       dbg_b1_hex_ready;
    (* preserve, noprune *) reg       dbg_b1_hex_fire;

    // Live handshakes are wires; the public dbg_* signals below are registered
    // snapshots so SignalTap sees a stable, aligned sample record.
    wire dbg_b1_in_hex_fire_live =
        (state == S_B1) && pw_exp_in_valid && pw_exp_in_ready;
    wire dbg_b1_hex_fire_live =
        (state == S_B1) && b1_block_out_valid && b1_block_out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_b1_in_hex_idx   <= 32'd0;
            dbg_b1_hex_idx      <= 32'd0;
            dbg_b1_in_hex_count <= 32'd0;
            dbg_b1_hex_count    <= 32'd0;

            dbg_b1_in_hex_pixel  <= 8'd0;
            dbg_b1_in_hex_ch_idx <= 8'd0;
            dbg_b1_in_hex_valid  <= 1'b0;
            dbg_b1_in_hex_ready  <= 1'b0;
            dbg_b1_in_hex_fire   <= 1'b0;

            dbg_b1_hex_pixel  <= 8'd0;
            dbg_b1_hex_ch_idx <= 8'd0;
            dbg_b1_hex_valid  <= 1'b0;
            dbg_b1_hex_ready  <= 1'b0;
            dbg_b1_hex_fire   <= 1'b0;
        end else if (state == S_IDLE) begin
            // Each new CNN run starts at byte index zero.
            dbg_b1_in_hex_idx   <= 32'd0;
            dbg_b1_hex_idx      <= 32'd0;
            dbg_b1_in_hex_count <= 32'd0;
            dbg_b1_hex_count    <= 32'd0;

            dbg_b1_in_hex_valid <= 1'b0;
            dbg_b1_in_hex_ready <= 1'b0;
            dbg_b1_in_hex_fire  <= 1'b0;
            dbg_b1_hex_valid    <= 1'b0;
            dbg_b1_hex_ready    <= 1'b0;
            dbg_b1_hex_fire     <= 1'b0;
        end else begin
            // Default: one-cycle event pulses clear unless a handshake occurs.
            dbg_b1_in_hex_valid <= 1'b0;
            dbg_b1_in_hex_ready <= 1'b0;
            dbg_b1_in_hex_fire  <= 1'b0;
            dbg_b1_hex_valid    <= 1'b0;
            dbg_b1_hex_ready    <= 1'b0;
            dbg_b1_hex_fire     <= 1'b0;

            if (dbg_b1_in_hex_fire_live) begin
                dbg_b1_in_hex_idx   <= dbg_b1_in_hex_count;
                dbg_b1_in_hex_pixel <= pw_exp_in_pixel;
                dbg_b1_in_hex_ch_idx <= pw_exp_in_ch_idx;
                dbg_b1_in_hex_valid <= 1'b1;
                dbg_b1_in_hex_ready <= 1'b1;
                dbg_b1_in_hex_fire  <= 1'b1;
                dbg_b1_in_hex_count <= dbg_b1_in_hex_count + 1'b1;
            end

            if (dbg_b1_hex_fire_live) begin
                dbg_b1_hex_idx   <= dbg_b1_hex_count;
                dbg_b1_hex_pixel <= b1_block_out_pixel;
                dbg_b1_hex_ch_idx <= b1_block_out_ch_idx;
                dbg_b1_hex_valid <= 1'b1;
                dbg_b1_hex_ready <= 1'b1;
                dbg_b1_hex_fire  <= 1'b1;
                dbg_b1_hex_count <= dbg_b1_hex_count + 1'b1;
            end
        end
    end

    // ========================================================================
    // B1 INTERMEDIATE-STAGE HEX DEBUG TAPS
    // ========================================================================
    // Registered snapshots are captured only when each stage's output is
    // accepted by its downstream consumer. Index is zero-based and counts bytes.
    // Expected one-frame stream lengths:
    //   PW Expand output : 96*96*48 = 442368 bytes (idx 0..442367)
    //   Depthwise output : 96*96*48 = 442368 bytes (idx 0..442367)
    //   PW Project output: 96*96*24 = 221184 bytes (idx 0..221183)
    // Note: PW Project taps are BEFORE residual addition. Final B1 output taps
    // above are AFTER the controller's residual/output path.

    (* preserve, noprune *) reg [31:0] dbg_b1_exp_hex_idx;
    (* preserve, noprune *) reg [31:0] dbg_b1_exp_hex_count;
    (* preserve, noprune *) reg [7:0]  dbg_b1_exp_hex_pixel;
    (* preserve, noprune *) reg [7:0]  dbg_b1_exp_hex_ch_idx;
    (* preserve, noprune *) reg        dbg_b1_exp_hex_valid;
    (* preserve, noprune *) reg        dbg_b1_exp_hex_ready;
    (* preserve, noprune *) reg        dbg_b1_exp_hex_fire;

    (* preserve, noprune *) reg [31:0] dbg_b1_dw_hex_idx;
    (* preserve, noprune *) reg [31:0] dbg_b1_dw_hex_count;
    (* preserve, noprune *) reg [7:0]  dbg_b1_dw_hex_pixel;
    (* preserve, noprune *) reg [7:0]  dbg_b1_dw_hex_ch_idx;
    (* preserve, noprune *) reg        dbg_b1_dw_hex_valid;
    (* preserve, noprune *) reg        dbg_b1_dw_hex_ready;
    (* preserve, noprune *) reg        dbg_b1_dw_hex_fire;

    (* preserve, noprune *) reg [31:0] dbg_b1_proj_hex_idx;
    (* preserve, noprune *) reg [31:0] dbg_b1_proj_hex_count;
    (* preserve, noprune *) reg [7:0]  dbg_b1_proj_hex_pixel;
    (* preserve, noprune *) reg [7:0]  dbg_b1_proj_hex_ch_idx;
    (* preserve, noprune *) reg        dbg_b1_proj_hex_valid;
    (* preserve, noprune *) reg        dbg_b1_proj_hex_ready;
    (* preserve, noprune *) reg        dbg_b1_proj_hex_fire;

    wire dbg_b1_exp_hex_fire_live =
        (state == S_B1) && pw_exp_out_valid && b1_expand_ready;
    wire dbg_b1_dw_hex_fire_live =
        (state == S_B1) && dw_out_valid && dw_out_ready;
    wire dbg_b1_proj_hex_fire_live =
        (state == S_B1) && pw_proj_out_valid && pw_proj_out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_b1_exp_hex_idx   <= 32'd0;
            dbg_b1_exp_hex_count <= 32'd0;
            dbg_b1_exp_hex_pixel <= 8'd0;
            dbg_b1_exp_hex_ch_idx <= 8'd0;
            dbg_b1_exp_hex_valid <= 1'b0;
            dbg_b1_exp_hex_ready <= 1'b0;
            dbg_b1_exp_hex_fire <= 1'b0;

            dbg_b1_dw_hex_idx   <= 32'd0;
            dbg_b1_dw_hex_count <= 32'd0;
            dbg_b1_dw_hex_pixel <= 8'd0;
            dbg_b1_dw_hex_ch_idx <= 8'd0;
            dbg_b1_dw_hex_valid <= 1'b0;
            dbg_b1_dw_hex_ready <= 1'b0;
            dbg_b1_dw_hex_fire <= 1'b0;

            dbg_b1_proj_hex_idx   <= 32'd0;
            dbg_b1_proj_hex_count <= 32'd0;
            dbg_b1_proj_hex_pixel <= 8'd0;
            dbg_b1_proj_hex_ch_idx <= 8'd0;
            dbg_b1_proj_hex_valid <= 1'b0;
            dbg_b1_proj_hex_ready <= 1'b0;
            dbg_b1_proj_hex_fire <= 1'b0;
        end else if (state == S_IDLE) begin
            dbg_b1_exp_hex_idx   <= 32'd0;
            dbg_b1_exp_hex_count <= 32'd0;
            dbg_b1_exp_hex_valid <= 1'b0;
            dbg_b1_exp_hex_ready <= 1'b0;
            dbg_b1_exp_hex_fire <= 1'b0;

            dbg_b1_dw_hex_idx   <= 32'd0;
            dbg_b1_dw_hex_count <= 32'd0;
            dbg_b1_dw_hex_valid <= 1'b0;
            dbg_b1_dw_hex_ready <= 1'b0;
            dbg_b1_dw_hex_fire <= 1'b0;

            dbg_b1_proj_hex_idx   <= 32'd0;
            dbg_b1_proj_hex_count <= 32'd0;
            dbg_b1_proj_hex_valid <= 1'b0;
            dbg_b1_proj_hex_ready <= 1'b0;
            dbg_b1_proj_hex_fire <= 1'b0;
        end else begin
            dbg_b1_exp_hex_valid <= 1'b0;
            dbg_b1_exp_hex_ready <= 1'b0;
            dbg_b1_exp_hex_fire <= 1'b0;
            dbg_b1_dw_hex_valid <= 1'b0;
            dbg_b1_dw_hex_ready <= 1'b0;
            dbg_b1_dw_hex_fire <= 1'b0;
            dbg_b1_proj_hex_valid <= 1'b0;
            dbg_b1_proj_hex_ready <= 1'b0;
            dbg_b1_proj_hex_fire <= 1'b0;

            if (dbg_b1_exp_hex_fire_live) begin
                dbg_b1_exp_hex_idx <= dbg_b1_exp_hex_count;
                dbg_b1_exp_hex_pixel <= pw_exp_out_pixel;
                dbg_b1_exp_hex_ch_idx <= pw_exp_out_ch_idx;
                dbg_b1_exp_hex_valid <= 1'b1;
                dbg_b1_exp_hex_ready <= 1'b1;
                dbg_b1_exp_hex_fire <= 1'b1;
                dbg_b1_exp_hex_count <= dbg_b1_exp_hex_count + 1'b1;
            end

            if (dbg_b1_dw_hex_fire_live) begin
                dbg_b1_dw_hex_idx <= dbg_b1_dw_hex_count;
                dbg_b1_dw_hex_pixel <= dw_out_pixel;
                dbg_b1_dw_hex_ch_idx <= dw_out_ch_idx;
                dbg_b1_dw_hex_valid <= 1'b1;
                dbg_b1_dw_hex_ready <= 1'b1;
                dbg_b1_dw_hex_fire <= 1'b1;
                dbg_b1_dw_hex_count <= dbg_b1_dw_hex_count + 1'b1;
            end

            if (dbg_b1_proj_hex_fire_live) begin
                dbg_b1_proj_hex_idx <= dbg_b1_proj_hex_count;
                dbg_b1_proj_hex_pixel <= pw_proj_out_pixel;
                dbg_b1_proj_hex_ch_idx <= pw_proj_out_ch_idx;
                dbg_b1_proj_hex_valid <= 1'b1;
                dbg_b1_proj_hex_ready <= 1'b1;
                dbg_b1_proj_hex_fire <= 1'b1;
                dbg_b1_proj_hex_count <= dbg_b1_proj_hex_count + 1'b1;
            end
        end
    end

    // B1 output row accounting for the streaming B1->B2 boundary.
    localparam integer B1_ROW_TX = B1_IN_W * B1_OUT;
    reg [11:0] b1_row_tx_count;
    reg [7:0]  b1_rows_produced;

    localparam integer B2_ROW_TX = B2_IN_W * B2_OUT;
    reg [11:0] b2_row_tx_count;
    reg [7:0]  b2_rows_produced;

    localparam integer B3_ROW_TX = B3_IN_W * B3_OUT;
    reg [11:0] b3_row_tx_count;
    reg [7:0]  b3_rows_produced;

    localparam integer B4_ROW_TX = B4_OUT_W * B4_OUT;
    reg [11:0] b4_row_tx_count;
    reg [7:0]  b4_rows_produced;

    localparam integer B5_ROW_TX = B5_IN_W * B5_OUT;
    reg [11:0] b5_row_tx_count;
    reg [7:0]  b5_rows_produced;

    localparam integer B6_ROW_TX = B6_OUT_W * B6_OUT;
    reg [11:0] b6_row_tx_count;
    reg [7:0]  b6_rows_produced;

    localparam integer B7_ROW_TX = B7_IN_W * B7_IN;
    reg [11:0] b7_row_tx_count;
    reg [7:0]  b7_rows_consumed;

    wire b1_row_fire =
        (state == S_B1) && active_output_fire &&
        (b1_row_tx_count == B1_ROW_TX-1);


    wire b2_complete_safe =
        (state == S_B2) && b2_pause_safe_arb &&
        (b2_rows_produced >= B2_IN_H);

    // B2 yields to B1 when its input row FIFO is empty and B1 still has rows.
    //
    // STARVATION ESCAPE: once the shared engines are truly idle and there is
    // no partial PW-Expand RX packet, B2 is provably not consuming the shared
    // datapath.  In that condition, waiting forever for the controller's
    // pause_safe indication can deadlock the whole pipeline if the controller
    // is itself waiting for upstream input.  Treat this explicit upstream-
    // starvation condition as a safe B2->B1 scheduling point.
    // IMPORTANT FIX5:
    // Never preempt B2 merely because its input FIFO is momentarily empty.
    // The previous force path could fire while B2 had already entered
    // ST_WAIT_LAUNCH/ST_WINDOW, so WindowGen was started and then the top
    // immediately moved ownership back to B1.  The per-block WindowGen is
    // not part of shared_engine_idle, therefore this created a stranded
    // B2 row with wg_done_seen=1 and zero accepted windows.
    //
    // B2 is allowed to yield to B1 only at the controller's explicit
    // pause-safe boundary (ST_FILL/ST_DONE).
    wire b2_starved_for_b1 =
        (state == S_B2) &&
        b1b2_fifo_empty &&
        (b1_rows_produced < B1_IN_H) &&
        shared_engine_idle &&
        !pw_rx_partial &&
        !source_fire &&
        b2_pause_safe;

    wire b2_yield_b1_safe =
        b2_pause_safe_arb;

    wire b2_should_yield_b1 =
        (state == S_B2) &&
        b1b2_fifo_empty &&
        (b1_rows_produced < B1_IN_H) &&
        b2_yield_b1_safe;

    // B2 may yield complete output rows to B3 even after B1 has finished.
    // The previous implementation incorrectly required
    // (b1_rows_produced < B1_IN_H), which permanently disabled this path once
    // B1 reached its final row.  That is exactly the condition seen when B2
    // had only 3 output rows buffered while all 96 B1 rows were already done.
    // Once B2->B3 contains >=2 complete rows, a clean shared-engine boundary
    // is sufficient to hand ownership to B3.
    // Same rule for B2 -> B3: a row/FIFO burst may hand off only when the
    // controller itself reports pause_safe.  shared_engine_idle alone is
    // insufficient because WindowGen lives inside the block controller.
    wire b2_force_yield_b3 =
        (state == S_B2) &&
        (b2b3_fifo_rows >= 2) &&
        shared_engine_idle &&
        !pw_rx_partial &&
        !source_fire &&
        b2_pause_safe;

    wire b2_yield_b3_safe =
        b2_pause_safe_arb;

    wire b2_should_yield_b3 =
        (state == S_B2) &&
        b2_yield_b3_safe &&
        (b2b3_fifo_rows >= 2);

    // B3 yields back to B2 only when it is safely waiting for more input rows.
    wire b3_should_yield_b2 =
        (state == S_B3) && b3_pause_safe_arb &&
        b2b3_fifo_empty &&
        (b2_rows_produced < B2_IN_H);

    // B3 produces one completed row per 96*32 output transactions. Two rows
    // are enough for B4 to launch its next stride-2 output row. This gives a
    // deterministic 2:B4 scheduling cadence without ever requiring a full B3
    // frame in memory.
    wire b3_complete_safe =
        (state == S_B3) && b3_pause_safe_arb &&
        (b3_rows_produced >= B3_IN_H);

    wire b3_should_yield_b4 =
        (state == S_B3) && b3_pause_safe_arb &&
        (b3b4_fifo_rows >= 2) &&
        (b3_rows_produced < B3_IN_H);

    // B4 STRIDE=2 consumes two complete B3 input rows per output row.
    wire b4_pause_safe_stage3 =
        (state == S_B4) && b4_pause_safe &&
        !pw_rx_partial && !source_fire;

    wire b4_should_yield_b3 =
        b4_pause_safe_stage3 &&
        (b3b4_fifo_rows < 2) &&
        (b3_rows_produced < B3_IN_H);

    // B4 -> B5 is the next row-streaming boundary. B5 is stride=1, so two
    // completed B4 rows are enough to launch B5 output row 0.
    wire b4_complete_safe =
        (state == S_B4) && b4_pause_safe_arb &&
        (b4_rows_produced >= B4_OUT_H);

    wire b4_should_yield_b5 =
        (state == S_B4) && b4_pause_safe_arb &&
        (b4b5_fifo_rows >= 2) &&
        (b4_rows_produced < B4_OUT_H);

    wire b5_should_yield_b4 =
        (state == S_B5) && b5_pause_safe_arb &&
        (b4b5_fifo_rows < 2) &&
        (b4_rows_produced < B4_OUT_H);

    wire b5_complete_safe =
        (state == S_B5) && b5_pause_safe_arb &&
        (b5_rows_produced >= B5_IN_H);

    wire b5_should_yield_b6 =
        (state == S_B5) && b5_pause_safe_arb &&
        (b5b6_fifo_rows >= 2) &&
        (b5_rows_produced < B5_IN_H);

    wire b6_should_yield_b5 =
        (state == S_B6) && b6_pause_safe_arb &&
        (b5b6_fifo_rows < 2) &&
        (b5_rows_produced < B5_IN_H);

    // B6 -> B7 is now a row-streaming boundary. B7 is stride=1, so two
    // complete B6 rows are enough to launch B7 output row 0.
    wire b6_should_yield_b7 =
        (state == S_B6) && b6_pause_safe_arb &&
        (b6b7_fifo_rows >= 2) &&
        (b6_rows_produced < B6_OUT_H);

    // B6 is complete after all 24 output rows have entered the B6->B7 FIFO.
    wire b6_complete_safe =
        (state == S_B6) && b6_pause_safe_arb &&
        (b6_rows_produced >= B6_OUT_H);

    // B7 returns ownership to B6 when it needs more input rows.
    wire b7_should_yield_b6 =
        (state == S_B7) && b7_pause_safe_arb &&
        (b6b7_fifo_rows < 2) &&
        (b6_rows_produced < B6_OUT_H);

    reg [31:0] b7_head_count;
    reg [31:0] head_gap_count;
    localparam integer B7_HEAD_TOTAL = B7_OUT_PIXELS * B7_OUT;
    localparam integer HEAD_GAP_TOTAL = B7_OUT_PIXELS * 256;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            active_block <= 3'd0;
            handoff_pending <= 1'b0;
            handoff_request <= 1'b0;
            handoff_target <= 3'd0;
            cnn_done_r <= 1'b0;
            source_fire_count <= 32'd0;
            output_fire_count <= 32'd0;
            b1_source_count <= 32'd0;
            b1_output_count <= 32'd0;
            b2_source_count <= 32'd0;
            b2_output_count <= 32'd0;
            b3_source_count <= 32'd0;
            b3_output_count <= 32'd0;
            b4_source_count <= 32'd0;
            b4_output_count <= 32'd0;
            b5_source_count <= 32'd0;
            b5_output_count <= 32'd0;
            b6_source_count <= 32'd0;
            b6_output_count <= 32'd0;
            b7_source_count <= 32'd0;
            last_completed_block <= 3'd7;
            last_completed_source_count <= 32'd0;
            last_completed_output_count <= 32'd0;
            stage_completed_mask <= 7'd0;
            b7_head_count <= 32'd0;
            head_gap_count <= 32'd0;
            b1_row_tx_count <= 12'd0;
            b1_rows_produced <= 8'd0;
            b2_row_tx_count <= 12'd0;
            b2_rows_produced <= 8'd0;
            b3_row_tx_count <= 12'd0;
            b3_rows_produced <= 8'd0;
            b4_row_tx_count <= 12'd0;
            b4_rows_produced <= 8'd0;
            b5_row_tx_count <= 12'd0;
            b5_rows_produced <= 8'd0;
            b6_row_tx_count <= 12'd0;
            b6_rows_produced <= 8'd0;
        end else begin

            // Count handshakes globally. State transitions are handled in the
            // single case statement below. Keeping S_IDLE inside that case is
            // IMPORTANT: an outer `if (state == S_IDLE)` followed by a case
            // on the old state can overwrite `state <= S_B1` with the default
            // branch in the same clock edge.
            // Count B1/B2 independently because the two blocks share the
            // same arithmetic engines and the scheduler switches between them.
            if (source_fire) begin
                case (state)
                    S_B1: b1_source_count <= b1_source_count + 1'b1;
                    S_B2: b2_source_count <= b2_source_count + 1'b1;
                    S_B3: b3_source_count <= b3_source_count + 1'b1;
                    S_B4: b4_source_count <= b4_source_count + 1'b1;
                    S_B5: b5_source_count <= b5_source_count + 1'b1;
                    S_B6: b6_source_count <= b6_source_count + 1'b1;
                    S_B7: b7_source_count <= b7_source_count + 1'b1;
                    default: source_fire_count <= source_fire_count + 1'b1;
                endcase
            end

            if (active_output_fire) begin
                case (state)
                    S_B1: b1_output_count <= b1_output_count + 1'b1;
                    S_B2: b2_output_count <= b2_output_count + 1'b1;
                    S_B3: b3_output_count <= b3_output_count + 1'b1;
                    S_B4: b4_output_count <= b4_output_count + 1'b1;
                    S_B5: b5_output_count <= b5_output_count + 1'b1;
                    S_B6: b6_output_count <= b6_output_count + 1'b1;
                    default: output_fire_count <= output_fire_count + 1'b1;
                endcase
            end

            // Direct B7 -> HEAD and HEAD -> GAP stream accounting.
            if (head_out_valid && head_out_ready) begin
                head_gap_count <= head_gap_count + 1'b1;
            end

            // Track complete B1 output rows independently of the scheduler.
            if (state == S_B1 && active_output_fire) begin
                if (b1_row_tx_count == B1_ROW_TX-1) begin
                    b1_row_tx_count <= 12'd0;
                    b1_rows_produced <= b1_rows_produced + 1'b1;
                end else begin
                    b1_row_tx_count <= b1_row_tx_count + 1'b1;
                end
            end

            if (state == S_B2 && active_output_fire) begin
                if (b2_row_tx_count == B2_ROW_TX-1) begin
                    b2_row_tx_count <= 12'd0;
                    b2_rows_produced <= b2_rows_produced + 1'b1;
                end else begin
                    b2_row_tx_count <= b2_row_tx_count + 1'b1;
                end
            end

            if (state == S_B3 && active_output_fire) begin
                if (b3_row_tx_count == B3_ROW_TX-1) begin
                    b3_row_tx_count <= 12'd0;
                    b3_rows_produced <= b3_rows_produced + 1'b1;
                end else begin
                    b3_row_tx_count <= b3_row_tx_count + 1'b1;
                end
            end

            if (state == S_B4 && active_output_fire) begin
                if (b4_row_tx_count == B4_ROW_TX-1) begin
                    b4_row_tx_count <= 12'd0;
                    b4_rows_produced <= b4_rows_produced + 1'b1;
                end else begin
                    b4_row_tx_count <= b4_row_tx_count + 1'b1;
                end
            end

            if (state == S_B5 && active_output_fire) begin
                if (b5_row_tx_count == B5_ROW_TX-1) begin
                    b5_row_tx_count <= 12'd0;
                    b5_rows_produced <= b5_rows_produced + 1'b1;
                end else begin
                    b5_row_tx_count <= b5_row_tx_count + 1'b1;
                end
            end

            if (state == S_B6 && active_output_fire) begin
                if (b6_row_tx_count == B6_ROW_TX-1) begin
                    b6_row_tx_count <= 12'd0;
                    b6_rows_produced <= b6_rows_produced + 1'b1;
                end else begin
                    b6_row_tx_count <= b6_row_tx_count + 1'b1;
                end
            end

            // Count B7 input rows from HWC scalar handshakes.
            // One complete B7 input row is exactly:
            //     B7_IN_W(24) * B7_IN(128) = 3072 scalars.
            //
            // IMPORTANT: b7_row_tx_count is a PER-ROW phase counter. It is
            // intentionally NOT reset during B6<->B7 ownership handoffs, so
            // an arbitrary pause can occur anywhere in the current row.
            // It is reset only after exactly 3072 accepted B7 scalars.
            if (state == S_B7 && source_fire) begin
                if (b7_row_tx_count == B7_ROW_TX-1) begin
                    b7_row_tx_count <= 12'd0;
                    b7_rows_consumed <= b7_rows_consumed + 1'b1;
                end else begin
                    b7_row_tx_count <= b7_row_tx_count + 1'b1;
                end
            end

            case (state)
                S_IDLE: begin
                    source_fire_count <= 32'd0;
                    output_fire_count <= 32'd0;
                    b1_source_count <= 32'd0;
                    b1_output_count <= 32'd0;
                    b2_source_count <= 32'd0;
                    b2_output_count <= 32'd0;
                    b3_source_count <= 32'd0;
                    b3_output_count <= 32'd0;
                    b4_source_count <= 32'd0;
                    b4_output_count <= 32'd0;
                    b5_source_count <= 32'd0;
                    b5_output_count <= 32'd0;
                    b6_source_count <= 32'd0;
                    b6_output_count <= 32'd0;
                    b2_row_tx_count <= 12'd0;
                    b2_rows_produced <= 8'd0;
                    b3_row_tx_count <= 12'd0;
                    b3_rows_produced <= 8'd0;
                    b4_row_tx_count <= 12'd0;
                    b4_rows_produced <= 8'd0;
                    b5_row_tx_count <= 12'd0;
                    b5_rows_produced <= 8'd0;
                    b6_row_tx_count <= 12'd0;
                    b6_rows_produced <= 8'd0;
                    b7_source_count <= 32'd0;
                    b7_row_tx_count <= 12'd0;
                    b7_rows_consumed <= 8'd0;
                    b7_head_count <= 32'd0;
                    head_gap_count <= 32'd0;

                    if (start) begin
                        active_block <= 3'd0;
                        handoff_request <= 1'b0;
                        handoff_pending <= 1'b0;
                        cnn_done_r <= 1'b0;
                        state <= S_B1;
                        $display("[TOP] START full MobileNet V13 flow");
                    end
                end

                S_B1: begin
                    active_block <= 3'd0;

                    // Complete a previously requested handoff only after the
                    // shared PW engine reaches a real vector boundary.
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            state <= S_B2;
                        end
                    end else begin
                        // A row completion creates a REQUEST, not an immediate
                        // owner switch.  This guarantees that a simultaneous
                        // PW-Expand RX packet is allowed to finish.
                        if (b1_row_fire &&
                            ((b1_rows_produced + 1'b1) >= 2)) begin
                            handoff_target <= 3'd1;
                            handoff_request <= 1'b1;
                            if ((b1_rows_produced + 1'b1) >= B1_IN_H) begin
                                stage_completed_mask[0] <= 1'b1;
//                                $display("[TOP] B1 ALL ROWS COMPLETE (96 rows) -> B2 request PW_PARTIAL=%0d", pw_rx_partial);
                            end
                        end

                        // Once the requested row handoff becomes safe, freeze
                        // the current owner for one cycle before switching.
                        if (handoff_request && b1_pause_safe_arb) begin
                            handoff_pending <= 1'b1;
                            handoff_request <= 1'b0;
                        end
                    end
                end

                S_B2: begin
                    active_block <= 3'd1;

                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd0)
                                state <= S_B1;
                            else
                                state <= S_B3;
                        end
                    end else begin
                        // Latch the reason to handoff, but do not actually mask
                        // the PW input until the current RX vector is complete.
                        if (b2_complete_safe) begin
                            stage_completed_mask[1] <= 1'b1;
                            last_completed_block <= 3'd1;
                            last_completed_source_count <= b2_source_count;
                            last_completed_output_count <= b2_output_count;
                            handoff_target <= 3'd2;
                            handoff_request <= 1'b1;
//                            $display("[TOP] B2 ALL ROWS COMPLETE -> B3 request");
                        end else if (b2_should_yield_b1) begin
                            handoff_target <= 3'd0;

                            // Normal case: keep the request/pending protocol.
                            // Starvation case: the shared engines are already
                            // idle and B2's input FIFO is empty, so commit the
                            // pending handoff immediately instead of waiting
                            // for a pause-safe pulse that may never arrive
                            // while the controller is upstream-starved.
                            if (b2_starved_for_b1) begin
                                handoff_pending <= 1'b1;
                                handoff_request <= 1'b0;
//                                $display("[TOP][SCHED-FORCE] B2 starved by empty B1->B2 FIFO -> arm B1 handoff");
                            end else begin
                                handoff_request <= 1'b1;
                            end

//                            $display("[TOP] B2 WAITING FOR B1 ROW -> B1 request FIFO_ROWS=%0d PW_PARTIAL=%0d", b1b2_fifo_rows, pw_rx_partial);
                        end else if (b2_should_yield_b3) begin
                            handoff_target <= 3'd2;
                            if (b2_force_yield_b3) begin
                                handoff_pending <= 1'b1;
                                handoff_request <= 1'b0;
//                                $display("[TOP][SCHED-FORCE] B2 -> B3 clean-boundary handoff rows=%0d B1_ROWS=%0d B2_ROWS=%0d",
//                                         b2b3_fifo_rows, b1_rows_produced, b2_rows_produced);
                            end else begin
                                handoff_request <= 1'b1;
                            end
//                            $display("[TOP] B2 -> B3 ROW BURST request rows_buffered=%0d B1_ROWS=%0d B2_ROWS=%0d PW_PARTIAL=%0d",
//                                     b2b3_fifo_rows, b1_rows_produced, b2_rows_produced, pw_rx_partial);
                        end

                        // Only convert an ordinary request into a pending
                        // handoff here.  b2_starved_for_b1 has already armed
                        // handoff_pending above, so do not rely on the old
                        // value of handoff_request in that emergency path.
                        if (handoff_request && b2_pause_safe_arb) begin
                            handoff_pending <= 1'b1;
                            handoff_request <= 1'b0;
                        end
                    end
                end

                S_B3: begin
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd1) begin
                                state <= S_B2;
                            end else begin
                                // Stage-3 B3->B4 is now a row-FIFO handoff.
                                // No full-frame read-start pulse is required.
                                state <= S_B4;
                            end
                        end
                    end else begin
                        // Upstream starvation has priority: B3 cannot make a
                        // useful row unless B2 has supplied another row.
                        if (b3_should_yield_b2) begin
                            handoff_target <= 3'd1;
                            handoff_request <= 1'b1;
//                            $display("[TOP] B3 WAITING FOR B2 ROW -> B2 request FIFO_ROWS=%0d B2_ROWS=%0d",
//                                     b2b3_fifo_rows, b2_rows_produced);

                        // Once B3 has completed all 96 output rows, it is done.
                        // B4 must drain the final two rows from the row FIFO.
                        end else if (b3_complete_safe) begin
                            stage_completed_mask[2] <= 1'b1;
                            last_completed_block <= 3'd2;
                            last_completed_source_count <= b3_source_count;
                            last_completed_output_count <= b3_output_count;
                            handoff_target <= 3'd3;
                            handoff_request <= 1'b1;
                            source_fire_count <= 32'd0;
                            output_fire_count <= 32'd0;
//                            $display("[TOP] B3 ALL ROWS COMPLETE -> B4 request ROW_FIFO_ROWS=%0d", b3b4_fifo_rows);

                        // Normal Stage-3 time-multiplexing: give B4 two complete
                        // B3 rows, then let B4 consume them.
                        end else if (b3_should_yield_b4) begin
                            handoff_target <= 3'd3;
                            handoff_request <= 1'b1;
//                            $display("[TOP] B3 -> B4 ROW BURST request FIFO_ROWS=%0d B3_ROWS=%0d",
//                                     b3b4_fifo_rows, b3_rows_produced);
                        end

                        if (handoff_request && b3_pause_safe_arb) begin
                            handoff_pending <= 1'b1;
                            handoff_request <= 1'b0;
                        end
                    end
                end

                S_B4: begin
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd2) begin
                                // Stage-3 internal handoff: refill the B3->B4 FIFO.
                                state <= S_B3;
                            end else begin
                                // Stage-4 handoff: B5 starts consuming B4 rows.
                                state <= S_B5;
//                                $display("[TOP] B4 -> B5 ROW STREAM START FIFO_ROWS=%0d B4_ROWS=%0d",
//                                         b4b5_fifo_rows, b4_rows_produced);
                            end
                        end
                    end else if (b4_complete_safe) begin
                        stage_completed_mask[3] <= 1'b1;
                        last_completed_block <= 3'd3;
                        last_completed_source_count <= b4_source_count;
                        last_completed_output_count <= b4_output_count;
                        handoff_target <= 3'd4;
                        handoff_request <= 1'b1;
                        source_fire_count <= 32'd0;
                        output_fire_count <= 32'd0;
//                        $display("[TOP] B4 ALL ROWS COMPLETE -> B5 request FIFO_ROWS=%0d",
//                                 b4b5_fifo_rows);
                    end else if (b4_should_yield_b3) begin
                        handoff_target <= 3'd2;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B4 WAITING FOR B3 ROWS -> B3 request FIFO_ROWS=%0d B3_ROWS=%0d",
//                                 b3b4_fifo_rows, b3_rows_produced);
                    end else if (b4_should_yield_b5) begin
                        handoff_target <= 3'd4;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B4 -> B5 ROW BURST request FIFO_ROWS=%0d B4_ROWS=%0d",
//                                 b4b5_fifo_rows, b4_rows_produced);
                    end

                    if (handoff_request && b4_pause_safe_arb) begin
                        handoff_pending <= 1'b1;
                        handoff_request <= 1'b0;
                    end
                end

                S_B5: begin
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd3) begin
                                state <= S_B4;
                            end else begin
                                // Stage-5 handoff: B6 starts consuming B5 rows.
                                state <= S_B6;
//                                $display("[TOP] B5 -> B6 ROW STREAM START FIFO_ROWS=%0d B5_ROWS=%0d",
//                                         b5b6_fifo_rows, b5_rows_produced);
                            end
                        end
                    end else if (b5_complete_safe) begin
                        stage_completed_mask[4] <= 1'b1;
                        last_completed_block <= 3'd4;
                        last_completed_source_count <= b5_source_count;
                        last_completed_output_count <= b5_output_count;
                        handoff_target <= 3'd5;
                        handoff_request <= 1'b1;
                        source_fire_count <= 32'd0;
                        output_fire_count <= 32'd0;
//                        $display("[TOP] B5 ALL ROWS COMPLETE -> B6 request");
                    end else if (b5_should_yield_b4) begin
                        handoff_target <= 3'd3;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B5 WAITING FOR B4 ROWS -> B4 request FIFO_ROWS=%0d B4_ROWS=%0d",
//                                 b4b5_fifo_rows, b4_rows_produced);
                    end else if (b5_should_yield_b6) begin
                        handoff_target <= 3'd5;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B5 -> B6 ROW BURST request FIFO_ROWS=%0d B5_ROWS=%0d",
//                                 b5b6_fifo_rows, b5_rows_produced);
                    end

                    if (handoff_request && b5_pause_safe_arb) begin
                        handoff_pending <= 1'b1;
                        handoff_request <= 1'b0;
                    end
                end

                S_B6: begin
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            active_block <= handoff_target;
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd4) begin
                                state <= S_B5;
                            end else begin
                                state <= S_B7;
                                // IMPORTANT: B6 <-> B7 is time-multiplexed.
                                // Do NOT reset B7 row counters on every handoff.
                                // b7_rows_consumed and b7_source_count are cumulative
                                // for the entire B7 input frame and are initialized
                                // only when a new frame enters S_IDLE.
//                                $display("[TOP] B6 -> B7 ROW STREAM START FIFO_ROWS=%0d B6_ROWS=%0d",
//                                         b6b7_fifo_rows, b6_rows_produced);
                            end
                        end
                    end else if (b6_complete_safe) begin
                        stage_completed_mask[5] <= 1'b1;
                        last_completed_block <= 3'd5;
                        last_completed_source_count <= b6_source_count + (source_fire ? 32'd1 : 32'd0);
                        last_completed_output_count <= b6_output_count + (active_output_fire ? 32'd1 : 32'd0);
                        handoff_target <= 3'd6;
                        handoff_request <= 1'b1;
                        source_fire_count <= 32'd0;
                        output_fire_count <= 32'd0;
//                        $display("[TOP] B6 ALL ROWS COMPLETE -> B7 request FIFO_ROWS=%0d B6_ROWS=%0d",
//                                 b6b7_fifo_rows, b6_rows_produced);
                    end else if (b6_should_yield_b5) begin
                        handoff_target <= 3'd4;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B6 WAITING FOR B5 ROWS -> B5 request FIFO_ROWS=%0d B5_ROWS=%0d",
//                                 b5b6_fifo_rows, b5_rows_produced);
                    end else if (b6_should_yield_b7) begin
                        handoff_target <= 3'd6;
                        handoff_request <= 1'b1;
//                        $display("[TOP] B6 -> B7 ROW BURST request FIFO_ROWS=%0d B6_ROWS=%0d",
//                                 b6b7_fifo_rows, b6_rows_produced);
                    end

                    if (handoff_request && b6_pause_safe_arb) begin
                        handoff_pending <= 1'b1;
                        handoff_request <= 1'b0;
                    end
                end

                S_B7: begin
                    if (handoff_pending) begin
                        if (shared_engine_idle) begin
                            handoff_pending <= 1'b0;
                            handoff_request <= 1'b0;
                            if (handoff_target == 3'd5) begin
                                active_block <= 3'd5;
                                state <= S_B6;
//                                $display("[TOP] B7 -> B6 ROW STREAM RESUME FIFO_ROWS=%0d B6_ROWS=%0d",
//                                         b6b7_fifo_rows, b6_rows_produced);
                            end else begin
                                active_block <= 3'd0;
                                state <= S_FINISH;
                            end
                        end
                    end else if (active_output_fire) begin
                        b7_head_count <= b7_head_count + 1'b1;

                        if (b7_head_count == B7_HEAD_TOTAL-1) begin
                            stage_completed_mask[6] <= 1'b1;
                            last_completed_block <= 3'd6;
                            last_completed_source_count <= source_fire_count + (source_fire ? 32'd1 : 32'd0);
                            last_completed_output_count <= output_fire_count + (active_output_fire ? 32'd1 : 32'd0);
                            handoff_target <= 3'd7;
                            handoff_request <= 1'b1;
                            source_fire_count <= 32'd0;
                            output_fire_count <= 32'd0;
                            $display("[TOP] B7 -> HEAD input COMPLETE (%0d transfers)", B7_HEAD_TOTAL);
                        end
                    end else if (b7_should_yield_b6) begin
                        handoff_target <= 3'd5;
                        handoff_request <= 1'b1;
                        $display("[TOP] B7 WAITING FOR B6 ROWS -> B6 request FIFO_ROWS=%0d B6_ROWS=%0d",
                                 b6b7_fifo_rows, b6_rows_produced);
                    end

                    if (handoff_request && b7_pause_safe_arb) begin
                        handoff_pending <= 1'b1;
                        handoff_request <= 1'b0;
                    end
                end

                S_FINISH: begin
                    if (fc_frame_done) begin
                        cnn_done_r <= 1'b1;
                        state <= S_DONE;
                        $display("[TOP] FC FRAME DONE - full flow complete");
                    end
                end

                S_DONE: begin
                    // One frame per reset. Keep final status stable.
                    state <= S_DONE;
                end

                default: begin
                    state <= S_IDLE;
                    active_block <= 3'd0;
                end
            endcase
        end
    end

    assign cnn_busy =
        (state != S_IDLE) &&
        (state != S_DONE);

    // Sticky completion status: do not expose only the one-cycle FC pulse.
    assign cnn_done = cnn_done_r;

endmodule

// ============================================================================
// TOP INTER-STAGE HWC FRAME BUFFER
// ============================================================================
module top_hwc_frame_buffer #(
    parameter integer WIDTH = 96,
    parameter integer HEIGHT = 96,
    parameter integer CHANNELS = 24
)(
    input wire clk,
    input wire rst_n,

    input wire       wr_valid,
    input wire [7:0] wr_pixel,
    input wire [7:0] wr_ch_idx,
    output wire      wr_ready,
    output reg       write_done,

    input wire       start_read,
    output wire      rd_valid,
    output wire [7:0] rd_pixel,
    output wire [7:0] rd_ch_idx,
    input wire       rd_ready,
    output reg       read_done
);
    localparam integer TOTAL = WIDTH*HEIGHT*CHANNELS;
    localparam integer ADDR_W = (TOTAL <= 2) ? 1 : $clog2(TOTAL);

    (* ramstyle = "M10K" *)
    reg [7:0] mem [0:TOTAL-1];

    reg [7:0] wr_ch;
    reg [31:0] wr_pixel_idx;
    reg write_complete;

    reg read_active;
    reg [31:0] rd_pixel_idx;
    reg [7:0] rd_ch;

    wire [31:0] wr_addr = wr_pixel_idx*CHANNELS + wr_ch_idx;
    wire [31:0] rd_addr = rd_pixel_idx*CHANNELS + rd_ch;

    assign wr_ready = rst_n && !write_complete && !read_active;
    assign rd_valid = read_active;
    assign rd_pixel = (read_active && rd_addr < TOTAL) ? mem[rd_addr] : 8'd0;
    assign rd_ch_idx = rd_ch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ch <= 8'd0;
            wr_pixel_idx <= 32'd0;
            write_complete <= 1'b0;
            read_active <= 1'b0;
            rd_pixel_idx <= 32'd0;
            rd_ch <= 8'd0;
            write_done <= 1'b0;
            read_done <= 1'b0;
        end else begin
            write_done <= 1'b0;
            read_done <= 1'b0;

            if (wr_valid && wr_ready) begin
                if (wr_ch_idx < CHANNELS && wr_pixel_idx < WIDTH*HEIGHT) begin
                    mem[wr_addr] <= wr_pixel;

                    if (wr_ch_idx == CHANNELS-1) begin
                        wr_ch <= 8'd0;
                        if (wr_pixel_idx == WIDTH*HEIGHT-1) begin
                            write_complete <= 1'b1;
                            write_done <= 1'b1;
                        end else begin
                            wr_pixel_idx <= wr_pixel_idx + 1'b1;
                        end
                    end else begin
                        wr_ch <= wr_ch_idx + 1'b1;
                    end
                end else begin
                    $display("[TOP_FRAME][ERROR] write index out of range: pixel=%0d ch=%0d", wr_pixel_idx, wr_ch_idx);
                end
            end

            if (start_read && write_complete && !read_active) begin
                read_active <= 1'b1;
                rd_pixel_idx <= 32'd0;
                rd_ch <= 8'd0;
            end

            if (rd_valid && rd_ready) begin
                if (rd_ch == CHANNELS-1) begin
                    rd_ch <= 8'd0;
                    if (rd_pixel_idx == WIDTH*HEIGHT-1) begin
                        read_active <= 1'b0;
                        read_done <= 1'b1;
                    end else begin
                        rd_pixel_idx <= rd_pixel_idx + 1'b1;
                    end
                end else begin
                    rd_ch <= rd_ch + 1'b1;
                end
            end
        end
    end
endmodule

// NOTE: Active top instances use top_residual_vector_store_row4_streaming.
// The legacy top_residual_vector_store below is retained only for compatibility
// with older modules and is not instantiated by this top.

// ============================================================================
// TOP RESIDUAL VECTOR STORE
// ============================================================================
module top_residual_vector_store #(
    parameter integer WIDTH = 96,
    parameter integer HEIGHT = 96,
    parameter integer IN_CH = 24
)(
    input wire clk,
    input wire rst_n,

    input wire       wr_valid,
    input wire [7:0] wr_pixel,
    input wire [7:0] wr_ch_idx,
    output wire      wr_ready,

    output wire [IN_CH*8-1:0] rd_data,
    output wire              empty,
    input wire               rd_en
);
    localparam integer PIXELS = WIDTH*HEIGHT;
    localparam integer IDX_W = (PIXELS <= 2) ? 1 : $clog2(PIXELS);

    (* ramstyle = "M10K" *)
    reg [IN_CH*8-1:0] mem [0:PIXELS-1];

    reg [IDX_W-1:0] wr_pixel_idx;
    reg [IDX_W:0] rd_index;
    reg write_complete;

    assign wr_ready = rst_n && !write_complete;
    assign empty = !write_complete || (rd_index >= PIXELS);
    assign rd_data = (rd_index < PIXELS) ? mem[rd_index] : {IN_CH*8{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_pixel_idx <= {IDX_W{1'b0}};
            rd_index <= {(IDX_W+1){1'b0}};
            write_complete <= 1'b0;
        end else begin
            if (wr_valid && wr_ready) begin
                if (wr_ch_idx < IN_CH && wr_pixel_idx < PIXELS) begin
                    mem[wr_pixel_idx][wr_ch_idx*8 +: 8] <= wr_pixel;

                    if (wr_ch_idx == IN_CH-1) begin
                        if (wr_pixel_idx == PIXELS-1) begin
                            write_complete <= 1'b1;
                        end else begin
                            wr_pixel_idx <= wr_pixel_idx + 1'b1;
                        end
                    end
                end
            end

            if (rd_en && !empty) begin
                if (rd_index < PIXELS)
                    rd_index <= rd_index + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
