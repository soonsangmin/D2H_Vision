`timescale 1ns/1ps
`default_nettype none

// Modular wrapper preserving the older external stream interface while using
// the current dual-input CNN algorithm:
// RGB565 -> exact Gray + exact Sobel -> current cnn_top_ip (Gray/Sobel pair).
//
// External contract is intentionally the same as the previous cnn_ip_rgb_sobel:
// clk, rst_n, frame_start, rgb_data/rgb_valid/rgb_ready, busy, done,
// predicted_class and predicted_score.
module cnn_ip_rgb_sobel #(
    // Retained for source/constraint compatibility with the previous wrapper.
    // The current cnn_top_ip has its own locked engine configuration.
    parameter integer DW_PARALLEL_TAP   = 3,
    parameter integer PW_PARALLEL_OUT   = 8,
    parameter integer FC_PARALLEL_CLASS = 2,
    parameter integer WIDTH             = 96,
    parameter integer HEIGHT            = 96
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_start,
    input  wire [15:0]        rgb_data,
    input  wire               rgb_valid,
    output wire               rgb_ready,
    output wire               busy,
    output wire               done,
    output reg  [2:0]         predicted_class,
    output reg signed [31:0]  predicted_score,

    // Debug outputs retained for the DE10-Nano classifier monitor.
    output wire               debug_input_pair_fire_o,
    output wire               debug_fc_valid_o,
    output wire [2:0]         debug_fc_index_o,
    output wire signed [31:0] debug_fc_value_o,
    output wire               debug_fc_frame_done_o,
    output wire [6:0]         debug_stage_mask_o,
    output wire [2:0]         debug_active_block_o
);
    localparam [2:0] CTRL_IDLE  = 3'd0,
                     CTRL_RESET = 3'd1,
                     CTRL_KICK  = 3'd2,
                     CTRL_RUN   = 3'd3,
                     CTRL_DONE  = 3'd4;

    reg [2:0] ctrl_state_q;
    reg       frame_start_d_q;
    wire      frame_start_rise = frame_start && !frame_start_d_q;

    // Reset just the preprocessor and single-frame CNN IP between frames.
    // The external reset and previous displayed result remain unaffected.
    wire local_rst_n = rst_n && (ctrl_state_q != CTRL_RESET);
    wire frame_start_local = (ctrl_state_q == CTRL_KICK);

    wire [7:0] pre_gray;
    wire [7:0] pre_sobel;
    wire       pre_pixel_valid;
    wire       pre_pixel_ready;
    wire       pre_busy;
    wire       pre_done;
    wire       core_done;
    wire [2:0] core_predicted_class;

    wire       debug_fc_valid;
    wire [2:0] debug_fc_index;
    wire signed [31:0] debug_fc_value;
    wire       debug_fc_frame_done;
    wire [6:0] debug_stage_mask;
    wire [2:0] debug_active_block;

    reg signed [31:0] fc_logits [0:6];
    reg [6:0] fc_seen_mask_q;
    integer i;
    wire pre_rgb_ready;

    assign rgb_ready = (ctrl_state_q == CTRL_RUN) && pre_rgb_ready;
    assign busy = (ctrl_state_q == CTRL_RESET) ||
                  (ctrl_state_q == CTRL_KICK)  ||
                  (ctrl_state_q == CTRL_RUN);
    assign done = (ctrl_state_q == CTRL_DONE);

    // The preprocessor's output ready is connected directly to cnn_top_ip's
    // pixel_ready, so this pulse means one aligned Gray/Sobel pair was accepted.
    assign debug_input_pair_fire_o =
        (ctrl_state_q == CTRL_RUN) && pre_pixel_valid && pre_pixel_ready;
    assign debug_fc_valid_o       = debug_fc_valid;
    assign debug_fc_index_o       = debug_fc_index;
    assign debug_fc_value_o       = debug_fc_value;
    assign debug_fc_frame_done_o  = debug_fc_frame_done;
    assign debug_stage_mask_o     = debug_stage_mask;
    assign debug_active_block_o   = debug_active_block;

    sobel_rgb_preprocessor #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_preprocess (
        .clk         (clk),
        .rst_n       (local_rst_n),
        .frame_start (frame_start_local),
        .rgb_data    (rgb_data),
        .rgb_valid   (rgb_valid && (ctrl_state_q == CTRL_RUN)),
        .rgb_ready   (pre_rgb_ready),
        .pixel_out   (pre_sobel),
        .gray_out    (pre_gray),
        .pixel_valid (pre_pixel_valid),
        .pixel_ready (pre_pixel_ready),
        .busy        (pre_busy),
        .done        (pre_done)
    );

    cnn_top_ip u_current_cnn (
        .clk                  (clk),
        .rst_n                (local_rst_n),
        .frame_valid          (frame_start_local),
        .pixel_valid          (pre_pixel_valid && (ctrl_state_q == CTRL_RUN)),
        .pixel_ready          (pre_pixel_ready),
        .gray_pixel           (pre_gray),
        .sobel_pixel          (pre_sobel),
        .predicted_class      (core_predicted_class),
        .done                 (core_done),
        .debug_fc_valid_o     (debug_fc_valid),
        .debug_fc_index_o     (debug_fc_index),
        .debug_fc_value_o     (debug_fc_value),
        .debug_fc_frame_done_o(debug_fc_frame_done),
        .debug_stage_mask_o   (debug_stage_mask),
        .debug_active_block_o (debug_active_block)
    );

    // Keep external result stable while the next inference is running.
    // Capture all seven FC scores for the legacy predicted_score output.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_state_q    <= CTRL_IDLE;
            frame_start_d_q <= 1'b0;
            predicted_class <= 3'd0;
            predicted_score <= 32'sd0;
        end else begin
            frame_start_d_q <= frame_start;
            case (ctrl_state_q)
                CTRL_IDLE: begin
                    if (frame_start_rise)
                        ctrl_state_q <= CTRL_RESET;
                end
                CTRL_RESET: begin
                    // local_rst_n is low for this full cycle.
                    ctrl_state_q <= CTRL_KICK;
                end
                CTRL_KICK: begin
                    // One-cycle start pulse for the preprocessor and cnn_top_ip.
                    ctrl_state_q <= CTRL_RUN;
                end
                CTRL_RUN: begin
                    if (core_done) begin
                        predicted_class <= core_predicted_class;
                        predicted_score <= fc_logits[core_predicted_class];
                        ctrl_state_q <= CTRL_DONE;
                    end
                end
                CTRL_DONE: begin
                    if (frame_start_rise)
                        ctrl_state_q <= CTRL_RESET;
                end
                default: ctrl_state_q <= CTRL_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_seen_mask_q <= 7'd0;
            for (i = 0; i < 7; i = i + 1)
                fc_logits[i] <= 32'sd0;
        end else if (ctrl_state_q == CTRL_RESET) begin
            fc_seen_mask_q <= 7'd0;
            for (i = 0; i < 7; i = i + 1)
                fc_logits[i] <= 32'sd0;
        end else if (debug_fc_valid && (debug_fc_index <= 3'd6)) begin
            fc_logits[debug_fc_index] <= debug_fc_value;
            fc_seen_mask_q[debug_fc_index] <= 1'b1;
        end
    end
endmodule

`default_nettype wire
