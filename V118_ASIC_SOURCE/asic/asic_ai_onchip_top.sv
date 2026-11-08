`timescale 1ns/1ps
`default_nettype none
// V1.05 self-contained AI top: camera RGB565 input, class output;
// all feature maps, weights, snapshot and ROI image are on-chip.
// No DDR address/data pins, no FPGA, no host parameter download.
// Physical implementation must provide SRAM macros or sufficient stdcell area.
module asic_ai_onchip_top (
    input  wire clk_i,
    input  wire rstn_i,
    input  wire cam_frame_start_i,
    input  wire cam_pixel_valid_i,
    input  wire [15:0] cam_pixel_rgb565_i,
    output wire cam_capture_active_o,
    output wire cam_frame_locked_o,
    output wire input_fifo_overflow_o,
    output wire model_params_ready_o,
    output wire detector_busy_o,
    output wire detector_done_o,
    output wire presence_keep_o,
    output wire [7:0] presence_q_o,
    output wire [12:0] positive_cells_o,
    output wire roi_valid_o,
    output wire [9:0] roi_xmin_o,
    output wire [8:0] roi_ymin_o,
    output wire [9:0] roi_xmax_o,
    output wire [8:0] roi_ymax_o,
    output wire crop_busy_o,
    output wire crop_alignment_error_o,
    output wire classifier_busy_o,
    output wire classifier_done_o,
    output wire [2:0] classifier_class_o,
    output wire classifier_no_hand_o,
    output wire classifier_alignment_error_o,
    output wire snapshot_ready_o,
    output wire memory_access_error_o
);
    wire mem_rd_valid, mem_rd_ready, mem_rsp_valid, mem_rsp_ready;
    wire [31:0] mem_rd_addr;
    wire [63:0] mem_rsp_data;
    wire mem_wr_valid, mem_wr_ready;
    wire [31:0] mem_wr_addr;
    wire [63:0] mem_wr_data;

    asic_ai_local_core u_ai (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .cam_frame_start_i(cam_frame_start_i),
        .cam_pixel_valid_i(cam_pixel_valid_i),
        .cam_pixel_rgb565_i(cam_pixel_rgb565_i),
        .cam_capture_active_o(cam_capture_active_o),
        .cam_frame_locked_o(cam_frame_locked_o),
        .input_fifo_overflow_o(input_fifo_overflow_o),
        .mem_rd_valid_o(mem_rd_valid),.mem_rd_ready_i(mem_rd_ready),
        .mem_rd_addr_o(mem_rd_addr),.mem_rsp_valid_i(mem_rsp_valid),
        .mem_rsp_ready_o(mem_rsp_ready),.mem_rsp_data_i(mem_rsp_data),
        .mem_wr_valid_o(mem_wr_valid),.mem_wr_ready_i(mem_wr_ready),
        // All acknowledged on-chip writes commit on the same clock edge.
        .mem_wr_drain_done_i(1'b1),
        .mem_wr_addr_o(mem_wr_addr),.mem_wr_data_o(mem_wr_data),
        .model_params_ready_o(model_params_ready_o),
        .detector_busy_o(detector_busy_o),.detector_done_o(detector_done_o),
        .presence_keep_o(presence_keep_o),.presence_q_o(presence_q_o),
        .positive_cells_o(positive_cells_o),
        .roi_valid_o(roi_valid_o),.roi_xmin_o(roi_xmin_o),
        .roi_ymin_o(roi_ymin_o),.roi_xmax_o(roi_xmax_o),
        .roi_ymax_o(roi_ymax_o),.crop_busy_o(crop_busy_o),
        .crop_alignment_error_o(crop_alignment_error_o),
        .classifier_busy_o(classifier_busy_o),
        .classifier_done_o(classifier_done_o),
        .classifier_class_o(classifier_class_o),
        .classifier_no_hand_o(classifier_no_hand_o),
        .classifier_alignment_error_o(classifier_alignment_error_o)
    );
    asic_onchip_frame_memory u_frame_mem (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .cam_capture_active_i(cam_capture_active_o),
        .cam_pixel_valid_i(cam_pixel_valid_i),
        .cam_pixel_rgb565_i(cam_pixel_rgb565_i),
        .snapshot_ready_o(snapshot_ready_o),
        .access_error_o(memory_access_error_o),
        .rd_req_valid_i(mem_rd_valid),.rd_req_ready_o(mem_rd_ready),
        .rd_req_addr_i(mem_rd_addr),
        .rd_rsp_valid_o(mem_rsp_valid),.rd_rsp_ready_i(mem_rsp_ready),
        .rd_rsp_data_o(mem_rsp_data),
        .wr_req_valid_i(mem_wr_valid),.wr_req_ready_o(mem_wr_ready),
        .wr_req_addr_i(mem_wr_addr),.wr_req_data_i(mem_wr_data)
    );
endmodule
`default_nettype wire
