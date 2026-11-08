`timescale 1ns/1ps
`default_nettype none
// ASIC migration top of the *actual* FPGA V6.23 detector + 96x96 crop + CNN.
// No DE10/HPS/PLL/HDMI/Intel memory primitives in the instantiated hierarchy.
// All clocks unified to clk_i for this first ASIC characterization.
// The external DDR pins below are an ABSTRACT 64-bit transaction interface,
// NOT JEDEC DDR3 pins: board implementation still requires a DDR controller,
// DDR PHY, dedicated I/O cells, clocking and power integrity signoff.
// Memory contract: ordered single-outstanding read response, valid/ready,
// 64-bit little-endian data, byte addresses aligned to 8 for 64-bit accesses.
// Host must preload HandSeg parameters and RGB565 snapshot memory.
module asic_ai_top (
    input  wire        clk_i,
    input  wire        rstn_i,
    input  wire        cam_frame_start_i, // pulse before 640x480 pixels
    input  wire        cam_pixel_valid_i,
    input  wire [15:0] cam_pixel_rgb565_i,
    output wire        cam_capture_active_o,
    output wire        cam_frame_locked_o,
    output wire        input_fifo_overflow_o,

    output wire        mem_rd_valid_o,
    input  wire        mem_rd_ready_i,
    output wire [31:0] mem_rd_addr_o,
    input  wire        mem_rsp_valid_i,
    output wire        mem_rsp_ready_o,
    input  wire [63:0] mem_rsp_data_i,
    output wire        mem_wr_valid_o,
    input  wire        mem_wr_ready_i,
    // Assert only once all previously accepted writes are globally readable.
    input  wire        mem_wr_drain_done_i,
    output wire [31:0] mem_wr_addr_o,
    output wire [63:0] mem_wr_data_o,

    output wire        model_params_ready_o,
    output wire        detector_busy_o,
    output wire        detector_done_o,
    output wire        presence_keep_o,
    output wire [7:0]  presence_q_o,
    output wire [12:0] positive_cells_o,
    output wire        roi_valid_o,
    output wire [9:0]  roi_xmin_o,
    output wire [8:0]  roi_ymin_o,
    output wire [9:0]  roi_xmax_o,
    output wire [8:0]  roi_ymax_o,
    output wire        crop_busy_o,
    output wire        crop_alignment_error_o,
    output wire        classifier_busy_o,
    output wire        classifier_done_o,
    output wire [2:0]  classifier_class_o,
    output wire        classifier_no_hand_o,
    output wire        classifier_alignment_error_o
);
    wire det_rd_valid, det_rd_ready, det_rsp_valid, det_rsp_ready;
    wire [31:0] det_rd_addr;
    wire [63:0] det_rsp_data;
    wire det_wr_valid, det_wr_ready;
    wire [31:0] det_wr_addr;
    wire [63:0] det_wr_data;
    wire crop_rd_valid, crop_rd_ready, crop_rsp_valid, crop_rsp_ready;
    wire [31:0] crop_rd_addr;
    wire [63:0] crop_rsp_data;
    wire release_ai_frame, inference_done;
    wire crop_start, crop_done, classifier_start;
    wire crop_raw_done, crop_raw_busy;
    wire rgb96_stored, rgb96_write_error;
    wire rgb96_pixel_ready;
    wire rgb96_wr_valid,rgb96_wr_ready;
    wire [31:0] rgb96_wr_addr;
    wire [63:0] rgb96_wr_data;
    wire cls_rd_valid,cls_rd_ready,cls_rsp_valid,cls_rsp_ready;
    wire [31:0] cls_rd_addr;
    wire [63:0] cls_rsp_data;
    wire sobel_unused_start, waiting_unused;
    wire [6:0] raw_xmin,raw_xmax;
    wire [5:0] raw_ymin,raw_ymax;
    wire roi_update_unused,roi_valid_hdmi_unused;
    wire [9:0] hdmi_xmin_unused,hdmi_xmax_unused;
    wire [8:0] hdmi_ymin_unused,hdmi_ymax_unused;
    // Camera front end supplies already decoded RGB565; no FPGA sensor IP.
    handseg_camera_system #(.USE_EXTERNAL_DDR(1)) u_detector (
        .cam_pclk_i(clk_i),
        .cam_rstn_i(rstn_i),
        .cam_frame_rst_i(cam_frame_start_i),
        .cam_pixel_data_i(cam_pixel_rgb565_i),
        .cam_pixel_valid_i(cam_pixel_valid_i),
        .ai_clk_i(clk_i),
        .ai_rstn_i(rstn_i),
        .release_request_ai_i(release_ai_frame),
        .ddr_rd_req_valid_o(det_rd_valid),
        .ddr_rd_req_ready_i(det_rd_ready),
        .ddr_rd_req_addr_o(det_rd_addr),
        .ddr_rd_rsp_valid_i(det_rsp_valid),
        .ddr_rd_rsp_ready_o(det_rsp_ready),
        .ddr_rd_rsp_data_i(det_rsp_data),
        .ddr_wr_req_valid_o(det_wr_valid),
        .ddr_wr_req_ready_i(det_wr_ready),
        .ddr_wr_req_addr_o(det_wr_addr),
        .ddr_wr_req_data_o(det_wr_data),
        .hdmi_clk_i(clk_i),
        .hdmi_rstn_i(rstn_i),
        .roi_update_hdmi_o(roi_update_unused),
        .roi_valid_hdmi_o(roi_valid_hdmi_unused),
        .roi_xmin_hdmi_o(hdmi_xmin_unused),
        .roi_ymin_hdmi_o(hdmi_ymin_unused),
        .roi_xmax_hdmi_o(hdmi_xmax_unused),
        .roi_ymax_hdmi_o(hdmi_ymax_unused),
        .ai_busy_o(detector_busy_o),
        .inference_done_ai_o(inference_done),
        .presence_keep_ai_o(presence_keep_o),
        .presence_q_ai_o(presence_q_o),
        .positive_cells_ai_o(positive_cells_o),
        .raw_xmin_ai_o(raw_xmin),.raw_ymin_ai_o(raw_ymin),
        .raw_xmax_ai_o(raw_xmax),.raw_ymax_ai_o(raw_ymax),
        .preprocess_fifo_overflow_o(input_fifo_overflow_o),
        .frame_locked_cam_o(cam_frame_locked_o),
        .capture_active_cam_o(cam_capture_active_o),
        .roi_valid_ai_o(roi_valid_o),
        .roi_xmin_ai_o(roi_xmin_o),.roi_ymin_ai_o(roi_ymin_o),
        .roi_xmax_ai_o(roi_xmax_o),.roi_ymax_ai_o(roi_ymax_o),
        .params_ready_ai_o(model_params_ready_o)
    );
    assign detector_done_o = inference_done;
    // Original V6.23 snapshot controller sequencing, bypass HDMI-only Sobel:
    // Classifier computes exact Gray + Sobel internally.
    ai_snapshot_controller u_sequence (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .inference_done_i(inference_done),
        .roi_valid_i(roi_valid_o),
        .crop_done_i(crop_done),
        .sobel_done_i(1'b1),
        .classifier_done_i(classifier_done_o),
        .crop_start_o(crop_start),
        .sobel_start_o(sobel_unused_start),
        .sobel96_ready_pulse_o(classifier_start),
        .release_ai_frame_o(release_ai_frame),
        .waiting_for_consumer_o(waiting_unused),
        .no_hand_o(classifier_no_hand_o)
    );

    wire crop_mem_wr_en;
    wire [13:0] crop_mem_wr_addr;
    wire [15:0] crop_mem_wr_data;
    ai_roi_reader_resize_96x96 u_crop (
        .clk_i(clk_i), .rstn_i(rstn_i), .start_i(crop_start),
        .roi_xmin_i(roi_xmin_o),.roi_ymin_i(roi_ymin_o),
        .roi_xmax_i(roi_xmax_o),.roi_ymax_i(roi_ymax_o),
        .rd_req_valid_o(crop_rd_valid),
        .rd_req_ready_i(crop_rd_ready),
        .rd_req_addr_o(crop_rd_addr),
        .rd_rsp_valid_i(crop_rsp_valid),
        .rd_rsp_ready_o(crop_rsp_ready),
        .rd_rsp_data_i(crop_rsp_data),
        .bram_wr_ready_i(rgb96_pixel_ready),
        .bram_wr_en_o(crop_mem_wr_en),
        .bram_wr_addr_o(crop_mem_wr_addr),
        .bram_wr_data_o(crop_mem_wr_data),
        .busy_o(crop_raw_busy),.done_o(crop_raw_done)
    );
    // V1.02: RGB96 frame is held in off-chip SDRAM, not 9216x16 SRAM.
    // Three-part commit protocol: crop sent all pixels, writer accepted all
    // 64-bit transactions, external controller confirms write drain.
    asic_rgb96_ddr_writer u_rgb96_writer (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .frame_start_i(crop_start),.frame_end_i(crop_raw_done),
        .pixel_valid_i(crop_mem_wr_en),.pixel_ready_o(rgb96_pixel_ready),
        .pixel_addr_i(crop_mem_wr_addr),.pixel_data_i(crop_mem_wr_data),
        .wr_valid_o(rgb96_wr_valid),.wr_ready_i(rgb96_wr_ready),
        .wr_addr_o(rgb96_wr_addr),.wr_data_o(rgb96_wr_data),
        .finished_o(rgb96_stored),.alignment_error_o(rgb96_write_error)
    );
    assign crop_alignment_error_o=rgb96_write_error;
    assign crop_done=rgb96_stored && mem_wr_drain_done_i && !rgb96_write_error;
    logic crop_frame_inflight_r;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) crop_frame_inflight_r<=1'b0;
        else if (crop_start) crop_frame_inflight_r<=1'b1;
        else if (crop_done) crop_frame_inflight_r<=1'b0;
    end
    assign crop_busy_o=crop_raw_busy || (crop_frame_inflight_r && !crop_done);
    asic_rgb96_ddr_classifier u_classifier (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .image_ready_pulse_i(classifier_start),
        .rd_req_valid_o(cls_rd_valid),.rd_req_ready_i(cls_rd_ready),
        .rd_req_addr_o(cls_rd_addr),
        .rd_rsp_valid_i(cls_rsp_valid),.rd_rsp_ready_o(cls_rsp_ready),
        .rd_rsp_data_i(cls_rsp_data),
        .busy_o(classifier_busy_o),
        .done_pulse_o(classifier_done_o),
        .predicted_class_o(classifier_class_o),
        .alignment_error_o(classifier_alignment_error_o),
        .debug_input_pair_fire_o(),.debug_fc_valid_o(),
        .debug_fc_index_o(),.debug_fc_value_o(),
        .debug_fc_frame_done_o(),.debug_stage_mask_o(),
        .debug_active_block_o()
    );

    // Same original read owner selection as DE10_NANO.sv:
    // read requests may be arbitrarily stalled, single outstanding response.
    ai_ddr_read_mux u_read_mux (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .crop_select_i(crop_raw_busy),.classifier_select_i(classifier_busy_o),
        .cls_rd_req_valid_i(cls_rd_valid),.cls_rd_req_ready_o(cls_rd_ready),
        .cls_rd_req_addr_i(cls_rd_addr),.cls_rd_rsp_valid_o(cls_rsp_valid),
        .cls_rd_rsp_ready_i(cls_rsp_ready),.cls_rd_rsp_data_o(cls_rsp_data),
        .det_rd_req_valid_i(det_rd_valid),
        .det_rd_req_ready_o(det_rd_ready),
        .det_rd_req_addr_i(det_rd_addr),
        .det_rd_rsp_valid_o(det_rsp_valid),
        .det_rd_rsp_ready_i(det_rsp_ready),
        .det_rd_rsp_data_o(det_rsp_data),
        .crop_rd_req_valid_i(crop_rd_valid),
        .crop_rd_req_ready_o(crop_rd_ready),
        .crop_rd_req_addr_i(crop_rd_addr),
        .crop_rd_rsp_valid_o(crop_rsp_valid),
        .crop_rd_rsp_ready_i(crop_rsp_ready),
        .crop_rd_rsp_data_o(crop_rsp_data),
        .ddr_rd_req_valid_o(mem_rd_valid_o),
        .ddr_rd_req_ready_i(mem_rd_ready_i),
        .ddr_rd_req_addr_o(mem_rd_addr_o),
        .ddr_rd_rsp_valid_i(mem_rsp_valid_i),
        .ddr_rd_rsp_ready_o(mem_rsp_ready_o),
        .ddr_rd_rsp_data_i(mem_rsp_data_i)
    );
    // Detector priority; the two write clients are distinct in normal frame
    // sequencing but arbiter handles overlap without dropping transactions.
    assign mem_wr_valid_o=det_wr_valid || rgb96_wr_valid;
    assign mem_wr_addr_o=det_wr_valid ? det_wr_addr : rgb96_wr_addr;
    assign mem_wr_data_o=det_wr_valid ? det_wr_data : rgb96_wr_data;
    assign det_wr_ready=mem_wr_ready_i;
    assign rgb96_wr_ready=mem_wr_ready_i && !det_wr_valid;
endmodule
`default_nettype wire
