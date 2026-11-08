`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// RGB565 BRAM -> streaming cnn_ip_rgb_sobel bridge.
//
// The previous cnn_rgb565_gray_sobel_cnn_top owned the framebuffer read
// address and performed Gray/Sobel preprocessing internally.  The replacement
// cnn_ip_rgb_sobel has a streaming RGB565 ready/valid input instead.
//
// This bridge preserves the existing DE10_NANO top-level BRAM interface:
//   * image_ready_pulse_i starts one inference on a frozen 96x96 RGB565 frame.
//   * bram_read_active_o selects this bridge as the RGB BRAM address owner.
//   * bram_rd_addr_o requests pixels 0..9215 in row-major order.
//   * image96_bram is synchronous-read; one pending-read register captures the
//     BRAM response, then a holding register keeps it stable until rgb_ready.
//   * Exactly 96*96 accepted RGB565 pixels are sent to cnn_ip_rgb_sobel.
//
// The CNN wrapper performs its own exact RGB565 -> Gray/Sobel preprocessing.
// Existing debug outputs are preserved for classifier_debug_monitor.
// -----------------------------------------------------------------------------
module classifier_rgb565_bridge #(
    parameter integer FRAME_W       = 96,
    parameter integer FRAME_H       = 96,
    parameter integer FRAME_ADDR_W  = 14
)(
    input  logic        clk_i,
    input  logic        rstn_i,

    input  logic        image_ready_pulse_i,

    // Synchronous one-cycle RGB565 BRAM read port.
    output logic        bram_read_active_o,
    output logic [FRAME_ADDR_W-1:0] bram_rd_addr_o,
    input  logic [15:0] bram_rd_data_i,

    output logic        busy_o,
    output logic        done_pulse_o,
    output logic [2:0]  predicted_class_o,
    output logic        alignment_error_o,

    output wire         debug_input_pair_fire_o,
    output wire         debug_fc_valid_o,
    output wire [2:0]   debug_fc_index_o,
    output wire signed [31:0] debug_fc_value_o,
    output wire         debug_fc_frame_done_o,
    output wire [6:0]   debug_stage_mask_o,
    output wire [2:0]   debug_active_block_o
);
    localparam integer FRAME_PIXELS = FRAME_W * FRAME_H;

    localparam logic [2:0]
        S_IDLE      = 3'd0,
        S_START     = 3'd1,
        S_FEED      = 3'd2,
        S_WAIT_CORE = 3'd3,
        S_REPORT    = 3'd4;

    logic [2:0] state_r;

    // Next address to request from the synchronous RGB565 BRAM.
    logic [FRAME_ADDR_W-1:0] rd_addr_q;
    logic [FRAME_ADDR_W-1:0] rd_pending_addr_q;
    logic [FRAME_ADDR_W-1:0] accepted_count_q;

    // BRAM address is registered inside image96_bram.  rd_pending_q marks the
    // response arriving one clock after its address was issued.
    logic        rd_pending_q;
    logic [15:0] rgb_data_q;
    logic        rgb_valid_q;

    wire core_frame_start;
    wire [15:0] core_rgb_data;
    wire        core_rgb_valid;
    wire        core_rgb_ready;
    wire        core_done;
    wire [2:0]  core_predicted_class;

    wire rgb_fire = rgb_valid_q && core_rgb_ready;

    // Issue another BRAM read only when there is no outstanding response and
    // the one-entry response register is empty or being consumed this cycle.
    // This deliberately favors simple, lossless flow control over peak BRAM
    // bandwidth; the Sobel preprocessor itself has multi-cycle output stalls.
    wire bram_read_issue =
        (state_r == S_FEED) &&
        !rd_pending_q &&
        (!rgb_valid_q || rgb_fire) &&
        (rd_addr_q < FRAME_PIXELS);

    assign core_frame_start = (state_r == S_START);
    assign core_rgb_data    = rgb_data_q;
    assign core_rgb_valid   = rgb_valid_q;

    // Keep BRAM ownership for the complete feed phase.  rd_addr_q advances
    // only on a new request and is held stable whenever the reader is stalled.
    always_comb begin
        bram_read_active_o = (state_r == S_FEED);
        // Avoid presenting address FRAME_PIXELS (out of range) after the last
        // request while its response is being accepted by the CNN.
        if (rd_addr_q < FRAME_PIXELS)
            bram_rd_addr_o = rd_addr_q;
        else
            bram_rd_addr_o = FRAME_PIXELS - 1;
        busy_o = (state_r != S_IDLE);
    end

    cnn_ip_rgb_sobel #(
        .WIDTH  (FRAME_W),
        .HEIGHT (FRAME_H)
    ) u_classifier_stream (
        .clk                    (clk_i),
        .rst_n                  (rstn_i),
        .frame_start            (core_frame_start),
        .rgb_data               (core_rgb_data),
        .rgb_valid              (core_rgb_valid),
        .rgb_ready              (core_rgb_ready),
        .busy                   (),
        .done                   (core_done),
        .predicted_class        (core_predicted_class),
        .predicted_score        (),
        .debug_input_pair_fire_o(debug_input_pair_fire_o),
        .debug_fc_valid_o       (debug_fc_valid_o),
        .debug_fc_index_o       (debug_fc_index_o),
        .debug_fc_value_o       (debug_fc_value_o),
        .debug_fc_frame_done_o  (debug_fc_frame_done_o),
        .debug_stage_mask_o     (debug_stage_mask_o),
        .debug_active_block_o   (debug_active_block_o)
    );

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r             <= S_IDLE;
            rd_addr_q           <= '0;
            rd_pending_addr_q   <= '0;
            accepted_count_q    <= '0;
            rd_pending_q        <= 1'b0;
            rgb_data_q          <= 16'd0;
            rgb_valid_q         <= 1'b0;
            done_pulse_o        <= 1'b0;
            predicted_class_o   <= 3'd0;
            alignment_error_o   <= 1'b0;
        end else begin
            done_pulse_o <= 1'b0;

            // Complete a synchronous BRAM read.  At this edge the BRAM output
            // still contains the word for rd_pending_addr_q; its next address
            // update occurs after this edge.
            if (rd_pending_q) begin
                rgb_data_q  <= bram_rd_data_i;
                rgb_valid_q <= 1'b1;
                rd_pending_q <= 1'b0;

                // Requests are issued and accepted in strict row-major order.
                if (rd_pending_addr_q != accepted_count_q)
                    alignment_error_o <= 1'b1;
            end

            // Handshake to cnn_ip_rgb_sobel.  The response register is held
            // unchanged for as many cycles as the preprocessing stage stalls.
            if (rgb_fire) begin
                rgb_valid_q <= 1'b0;
                if (accepted_count_q < FRAME_PIXELS)
                    accepted_count_q <= accepted_count_q + 1'b1;
                else
                    alignment_error_o <= 1'b1;
            end

            // Start one synchronous BRAM transaction.  The BRAM captures the
            // current rd_addr_q on this edge; the data is captured above on the
            // following edge while rd_pending_q is asserted.
            if (bram_read_issue) begin
                rd_pending_q      <= 1'b1;
                rd_pending_addr_q <= rd_addr_q;
                rd_addr_q         <= rd_addr_q + 1'b1;
            end

            case (state_r)
                S_IDLE: begin
                    if (image_ready_pulse_i) begin
                        rd_addr_q         <= '0;
                        rd_pending_addr_q <= '0;
                        accepted_count_q  <= '0;
                        rd_pending_q      <= 1'b0;
                        rgb_data_q        <= 16'd0;
                        rgb_valid_q       <= 1'b0;
                        alignment_error_o <= 1'b0;
                        state_r           <= S_START;
                    end
                end

                // One-cycle frame_start pulse. cnn_ip_rgb_sobel performs its
                // own local reset/kick sequence before asserting rgb_ready.
                S_START: begin
                    state_r <= S_FEED;
                end

                S_FEED: begin
                    if (rgb_fire && (accepted_count_q == FRAME_PIXELS-1)) begin
                        // All input pixels have been accepted exactly once.
                        state_r <= S_WAIT_CORE;
                    end

                    // Defensive check: the CNN must not finish before all RGB
                    // pixels have been accepted by its streaming input.
                    if (core_done) begin
                        if (accepted_count_q != FRAME_PIXELS)
                            alignment_error_o <= 1'b1;
                        predicted_class_o <= core_predicted_class;
                        state_r <= S_REPORT;
                    end
                end

                S_WAIT_CORE: begin
                    if (core_done) begin
                        if (accepted_count_q != FRAME_PIXELS)
                            alignment_error_o <= 1'b1;
                        predicted_class_o <= core_predicted_class;
                        state_r <= S_REPORT;
                    end
                end

                S_REPORT: begin
                    done_pulse_o <= 1'b1;
                    state_r      <= S_IDLE;
                end

                default: begin
                    state_r <= S_IDLE;
                    alignment_error_o <= 1'b1;
                end
            endcase
        end
    end

    // Existing top-level debug ports are driven directly by cnn_ip_rgb_sobel.
    // The legacy spatial-tag checker is replaced by sequential read-tag and
    // accepted-count checks because preprocessing is now an input stream.

endmodule

`default_nettype wire
