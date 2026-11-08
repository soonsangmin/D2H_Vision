`timescale 1ns/1ps
`default_nettype none
// DDR-backed RGB565 stream bridge. Same cnn_ip_rgb_sobel core as FPGA V6.23.
// Exact 96x96 row-major RGB565; 4 pixels per 64-bit ordered DDR response.
// Supports arbitrary read latency and downstream backpressure. Throughput
// deliberately limited to one outstanding read, pending full architecture test.
module asic_rgb96_ddr_classifier #(
    parameter logic [31:0] FRAME_BASE=32'h3600_0000
)(
    input logic clk_i, rstn_i,
    input logic image_ready_pulse_i,
    output logic rd_req_valid_o,
    input logic rd_req_ready_i,
    output logic [31:0] rd_req_addr_o,
    input logic rd_rsp_valid_i,
    output logic rd_rsp_ready_o,
    input logic [63:0] rd_rsp_data_i,
    output logic busy_o,
    output logic done_pulse_o,
    output logic [2:0] predicted_class_o,
    output logic alignment_error_o,
    output wire debug_input_pair_fire_o,
    output wire debug_fc_valid_o,
    output wire [2:0] debug_fc_index_o,
    output wire signed [31:0] debug_fc_value_o,
    output wire debug_fc_frame_done_o,
    output wire [6:0] debug_stage_mask_o,
    output wire [2:0] debug_active_block_o
);
    localparam integer FRAME_WORDS=2304, FRAME_PIXELS=9216;
    localparam logic [2:0] S_IDLE=3'd0,S_START=3'd1,S_FEED=3'd2,S_WAIT=3'd3,S_REPORT=3'd4;
    logic [2:0] state_r;
    logic [11:0] word_req_index_r;
    logic [13:0] pixel_sent_r;
    logic read_pending_r,word_valid_r;
    logic [1:0] pixel_lane_r;
    logic [63:0] word_data_r;
    wire rgb_ready,core_done;
    wire [2:0] core_class;
    wire rgb_valid=(state_r==S_FEED)&&word_valid_r&&(pixel_sent_r<FRAME_PIXELS);
    logic [15:0] rgb_data;
    always_comb begin
        case(pixel_lane_r)
            2'd0: rgb_data=word_data_r[15:0];
            2'd1: rgb_data=word_data_r[31:16];
            2'd2: rgb_data=word_data_r[47:32];
            default: rgb_data=word_data_r[63:48];
        endcase
    end
    wire rgb_fire=rgb_valid && rgb_ready;
    assign busy_o=(state_r!=S_IDLE);
    assign rd_req_valid_o=(state_r==S_FEED)&&!word_valid_r&&!read_pending_r&&(word_req_index_r<FRAME_WORDS);
    assign rd_req_addr_o=FRAME_BASE+({20'd0,word_req_index_r}<<3);
    assign rd_rsp_ready_o=read_pending_r&&!word_valid_r;

    cnn_ip_rgb_sobel #(.WIDTH(96),.HEIGHT(96)) u_classifier_stream (
        .clk(clk_i),.rst_n(rstn_i),.frame_start(state_r==S_START),
        .rgb_data(rgb_data),.rgb_valid(rgb_valid),.rgb_ready(rgb_ready),
        .busy(),.done(core_done),.predicted_class(core_class),.predicted_score(),
        .debug_input_pair_fire_o(debug_input_pair_fire_o),
        .debug_fc_valid_o(debug_fc_valid_o),
        .debug_fc_index_o(debug_fc_index_o),
        .debug_fc_value_o(debug_fc_value_o),
        .debug_fc_frame_done_o(debug_fc_frame_done_o),
        .debug_stage_mask_o(debug_stage_mask_o),
        .debug_active_block_o(debug_active_block_o)
    );
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r<=S_IDLE;
            word_req_index_r<=12'd0;
            pixel_sent_r<=14'd0;
            read_pending_r<=1'b0;
            word_valid_r<=1'b0;
            pixel_lane_r<=2'd0;
            word_data_r<=64'd0;
            done_pulse_o<=1'b0;
            predicted_class_o<=3'd0;
            alignment_error_o<=1'b0;
        end else begin
            done_pulse_o<=1'b0;
            if (rd_req_valid_o&&rd_req_ready_i) begin
                read_pending_r<=1'b1;
                word_req_index_r<=word_req_index_r+12'd1;
            end
            if (rd_rsp_valid_i&&rd_rsp_ready_o) begin
                word_data_r<=rd_rsp_data_i;
                read_pending_r<=1'b0;
                word_valid_r<=1'b1;
                pixel_lane_r<=2'd0;
            end
            if (rgb_fire) begin
                pixel_sent_r<=pixel_sent_r+14'd1;
                if (pixel_lane_r==2'd3) begin
                    word_valid_r<=1'b0;
                    pixel_lane_r<=2'd0;
                end else pixel_lane_r<=pixel_lane_r+2'd1;
            end
            case (state_r)
                S_IDLE: if (image_ready_pulse_i) begin
                    word_req_index_r<=12'd0;
                    pixel_sent_r<=14'd0;
                    read_pending_r<=1'b0;
                    word_valid_r<=1'b0;
                    pixel_lane_r<=2'd0;
                    alignment_error_o<=1'b0;
                    state_r<=S_START;
                end
                S_START: state_r<=S_FEED;
                S_FEED: begin
                    if (core_done) begin
                        if (pixel_sent_r!=FRAME_PIXELS)
                            alignment_error_o<=1'b1;
                        predicted_class_o<=core_class;
                        state_r<=S_REPORT;
                    end else if (rgb_fire&&pixel_sent_r==FRAME_PIXELS-1)
                        state_r<=S_WAIT;
                end
                S_WAIT: if (core_done) begin
                    if (pixel_sent_r!=FRAME_PIXELS || word_req_index_r!=FRAME_WORDS || read_pending_r || word_valid_r)
                        alignment_error_o<=1'b1;
                    predicted_class_o<=core_class;
                    state_r<=S_REPORT;
                end
                S_REPORT: begin
                    done_pulse_o<=1'b1;
                    state_r<=S_IDLE;
                end
                default: state_r<=S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
