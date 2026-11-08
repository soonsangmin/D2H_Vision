module handseg_camera_system #(
    parameter integer USE_EXTERNAL_DDR = 0
)(
    // ========================================================================
    // CAMERA DOMAIN
    // ========================================================================
    input  logic        cam_pclk_i,
    input  logic        cam_rstn_i,
    input  logic        cam_frame_rst_i,
    input  logic [15:0] cam_pixel_data_i,
    input  logic        cam_pixel_valid_i,

    // ========================================================================
    // AI DOMAIN
    // ========================================================================
    input  logic        ai_clk_i,
    input  logic        ai_rstn_i,

    // AI-frame lifetime is now controlled externally.  The detector result
    // is cropped into BRAM96 and the temporary classifier/HDMI consumer must
    // finish before the camera frame gate is released.
    input  logic        release_request_ai_i,

    // Ordered AI DDR service from the patched soc_system wrapper.
    output logic        ddr_rd_req_valid_o,
    input  logic        ddr_rd_req_ready_i,
    output logic [31:0] ddr_rd_req_addr_o,
    input  logic        ddr_rd_rsp_valid_i,
    output logic        ddr_rd_rsp_ready_o,
    input  logic [63:0] ddr_rd_rsp_data_i,
    output logic        ddr_wr_req_valid_o,
    input  logic        ddr_wr_req_ready_i,
    output logic [31:0] ddr_wr_req_addr_o,
    output logic [63:0] ddr_wr_req_data_o,

    // ========================================================================
    // HDMI PIXEL DOMAIN
    // ========================================================================
    input  logic        hdmi_clk_i,
    input  logic        hdmi_rstn_i,

    // ROI snapshot ready for existing hdmi_module / roi_overlay_rgb565.
    output logic        roi_update_hdmi_o,
    output logic        roi_valid_hdmi_o,
    output logic [9:0]  roi_xmin_hdmi_o,
    output logic [8:0]  roi_ymin_hdmi_o,
    output logic [9:0]  roi_xmax_hdmi_o,
    output logic [8:0]  roi_ymax_hdmi_o,

    // Debug / SignalTap
    output logic        ai_busy_o,
    output logic        inference_done_ai_o,
    output logic        presence_keep_ai_o,
    output logic [7:0]  presence_q_ai_o,
    output logic [12:0] positive_cells_ai_o,
    output logic [6:0]  raw_xmin_ai_o,
    output logic [5:0]  raw_ymin_ai_o,
    output logic [6:0]  raw_xmax_ai_o,
    output logic [5:0]  raw_ymax_ai_o,
    output logic        preprocess_fifo_overflow_o,
    output logic        frame_locked_cam_o,
    output logic        capture_active_cam_o,

    // Mapped detector ROI kept in the 50-MHz AI domain for the DDR cropper.
    output logic        roi_valid_ai_o,
    output logic [9:0]  roi_xmin_ai_o,
    output logic [8:0]  roi_ymin_ai_o,
    output logic [9:0]  roi_xmax_ai_o,
    output logic [8:0]  roi_ymax_ai_o,

    output logic        params_ready_ai_o
);

    // ========================================================================
    // CAMERA FRAME GATE
    //
    // Exactly one 640x480 camera frame is accepted. Following frames are
    // ignored until the AI inference finishes and releases the gate.
    // ========================================================================

    logic [15:0] gated_rgb565;
    logic        gated_valid;
    logic        capture_start_cam;
    logic        capture_done_cam;
    logic        capture_active_cam;
    logic        release_cam;

    // Parameters are loaded by HPS into reserved DDR. Do not lock/capture a
    // frame until the external parameter store has observed the ready magic.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic params_ready_cam_meta_r, params_ready_cam_sync_r;
    always_ff @(posedge cam_pclk_i or negedge cam_rstn_i) begin
        if (!cam_rstn_i) begin
            params_ready_cam_meta_r <= 1'b0;
            params_ready_cam_sync_r <= 1'b0;
        end
        else begin
            params_ready_cam_meta_r <= params_ready_ai_o;
            params_ready_cam_sync_r <= params_ready_cam_meta_r;
        end
    end

    camera_frame_gate #(
        .XRES(640),
        .YRES(480)
    ) u_frame_gate (
        .cam_pclk_i       (cam_pclk_i),
        .rstn_i           (cam_rstn_i),
        .cam_frame_rst_i  (cam_frame_rst_i),
        .enable_i         (params_ready_cam_sync_r),
        .pixel_data_i     (cam_pixel_data_i),
        .pixel_valid_i    (cam_pixel_valid_i),
        .release_i        (release_cam),
        .pixel_data_o     (gated_rgb565),
        .pixel_valid_o    (gated_valid),
        .frame_start_o    (capture_start_cam),
        .frame_done_o     (capture_done_cam),
        .capture_active_o (capture_active_cam),
        .frame_locked_o   (frame_locked_cam_o)
    );

    assign capture_active_cam_o = capture_active_cam;

    // ========================================================================
    // NEW PREPROCESS
    //
    // 640x480 RGB565
    //   -> RGB888 bit replication
    //   -> integer YCbCr
    //   -> exact AREA2x2 = 320x240
    //   -> 8 rows top + 8 rows bottom = 320x256
    // ========================================================================

    logic        prep_valid_cam;
    logic [23:0] prep_ycbcr_cam;
    logic        prep_done_cam;
    logic        prep_busy_cam;
    logic        prep_fifo_overflow_internal;

    camera_preprocess_320x256 u_preprocess (
        .clk_i                 (cam_pclk_i),
        .rstn_i                (cam_rstn_i),
        .cam_start_frame_i     (capture_start_cam),
        .cam_pixel_valid_i     (gated_valid),
        .cam_rgb565_i          (gated_rgb565),
        .pixel_valid_o         (prep_valid_cam),
        .pixel_ycbcr_o         (prep_ycbcr_cam),
        .frame_done_o          (prep_done_cam),
        .busy_o                (prep_busy_cam),
        .fifo_overflow_o       (prep_fifo_overflow_internal)
    );

    // ========================================================================
    // CAMERA -> AI CDC FIFO
    //
    // V2 used a complete 320x256x24 frame RAM (~1.97 Mbit). It duplicated the
    // model input and consumed a large fraction of Cyclone-V M10K. The new
    // design streams preprocessed pixels through only a 4096-word async FIFO.
    // The AI writes them directly to BANK_A in HPS DDR.
    // ========================================================================

    logic        ai_input_valid;
    logic        ai_input_ready;
    logic [23:0] ai_input_ycbcr;
    logic        ai_input_frame_start;
    logic        cdc_fifo_overflow;

    pulse_sync_toggle u_capture_start_sync (
        .src_clk_i   (cam_pclk_i),
        .src_rstn_i  (cam_rstn_i),
        .src_pulse_i (capture_start_cam),
        .dst_clk_i   (ai_clk_i),
        .dst_rstn_i  (ai_rstn_i),
        .dst_pulse_o (ai_input_frame_start)
    );

    handseg_async_pixel_fifo #(
        .WIDTH(24),
        .ADDR_BITS(12)
    ) u_pixel_cdc_fifo (
        .wr_clk_i      (cam_pclk_i),
        .wr_rstn_i     (cam_rstn_i),
        .wr_valid_i    (prep_valid_cam),
        .wr_data_i     (prep_ycbcr_cam),
        .wr_ready_o    (),
        .wr_overflow_o (cdc_fifo_overflow),
        .rd_clk_i      (ai_clk_i),
        .rd_rstn_i     (ai_rstn_i),
        .rd_valid_o    (ai_input_valid),
        .rd_ready_i    (ai_input_ready),
        .rd_data_o     (ai_input_ycbcr)
    );

    assign preprocess_fifo_overflow_o = cdc_fifo_overflow | prep_fifo_overflow_internal;

    // ========================================================================
    // HANDSEG-FPGA-STREAM V1.4.1 LIVE NETWORK
    // ========================================================================

    logic        roi_update_ai;
    logic        raw_roi_valid_ai;
    logic [6:0]  current_pc_ai;

    handseg_live_top #(
        .USE_EXTERNAL_DDR(USE_EXTERNAL_DDR)
    ) u_handseg (
        .clk_i              (ai_clk_i),
        .rstn_i             (ai_rstn_i),
        .frame_start_i      (ai_input_frame_start),
        .pixel_valid_i      (ai_input_valid),
        .pixel_ready_o      (ai_input_ready),
        .pixel_ycbcr_i      (ai_input_ycbcr),

        .ddr_rd_req_valid_o (ddr_rd_req_valid_o),
        .ddr_rd_req_ready_i (ddr_rd_req_ready_i),
        .ddr_rd_req_addr_o  (ddr_rd_req_addr_o),
        .ddr_rd_rsp_valid_i (ddr_rd_rsp_valid_i),
        .ddr_rd_rsp_ready_o (ddr_rd_rsp_ready_o),
        .ddr_rd_rsp_data_i  (ddr_rd_rsp_data_i),
        .ddr_wr_req_valid_o (ddr_wr_req_valid_o),
        .ddr_wr_req_ready_i (ddr_wr_req_ready_i),
        .ddr_wr_req_addr_o  (ddr_wr_req_addr_o),
        .ddr_wr_req_data_o  (ddr_wr_req_data_o),
        .params_ready_o     (params_ready_ai_o),

        .busy_o             (ai_busy_o),
        .inference_done_o   (inference_done_ai_o),
        .roi_update_o       (roi_update_ai),
        .presence_keep_o    (presence_keep_ai_o),
        .presence_q_o       (presence_q_ai_o),

        .roi_valid_o        (raw_roi_valid_ai),
        .positive_cells_o   (positive_cells_ai_o),
        .xmin_o             (raw_xmin_ai_o),
        .ymin_o             (raw_ymin_ai_o),
        .xmax_o             (raw_xmax_ai_o),
        .ymax_o             (raw_ymax_ai_o),
        .current_pc_o       (current_pc_ai)
    );

    // ========================================================================
    // RAW 80x64 MASK ROI -> CAMERA 640x480 COORDINATES
    // ========================================================================

    logic       roi_valid_camcoords_ai;
    logic [9:0] roi_xmin_ai;
    logic [8:0] roi_ymin_ai;
    logic [9:0] roi_xmax_ai;
    logic [8:0] roi_ymax_ai;

    handseg_roi_mapper_80x64_to_640x480 u_roi_mapper (
        .roi_valid_i  (raw_roi_valid_ai),
        .xmin_cell_i  (raw_xmin_ai_o),
        .ymin_cell_i  (raw_ymin_ai_o),
        .xmax_cell_i  (raw_xmax_ai_o),
        .ymax_cell_i  (raw_ymax_ai_o),
        .roi_valid_o  (roi_valid_camcoords_ai),
        .xmin_o       (roi_xmin_ai),
        .ymin_o       (roi_ymin_ai),
        .xmax_o       (roi_xmax_ai),
        .ymax_o       (roi_ymax_ai)
    );

    assign roi_valid_ai_o = roi_valid_camcoords_ai;
    assign roi_xmin_ai_o  = roi_xmin_ai;
    assign roi_ymin_ai_o  = roi_ymin_ai;
    assign roi_xmax_ai_o  = roi_xmax_ai;
    assign roi_ymax_ai_o  = roi_ymax_ai;

    // ========================================================================
    // EXTERNAL AI-FRAME RELEASE -> CAMERA DOMAIN
    // ========================================================================
    // Previous versions released the gate directly on inference_done.  V5.6
    // intentionally keeps 0x3200_0000 frozen until the ROI crop is in BRAM96
    // and, in SW1 debug mode, that BRAM image has been consumed by HDMI.
    pulse_sync_toggle u_release_sync (
        .src_clk_i   (ai_clk_i),
        .src_rstn_i  (ai_rstn_i),
        .src_pulse_i (release_request_ai_i),
        .dst_clk_i   (cam_pclk_i),
        .dst_rstn_i  (cam_rstn_i),
        .dst_pulse_o (release_cam)
    );

    // ========================================================================
    // ROI SNAPSHOT 50 MHz -> HDMI PIXEL CLOCK DOMAIN
    //
    // Existing roi_cdc_snapshot also carries a 16-bit score. The new model's
    // presence q-value is placed in the high byte for debug; HDMI overlay uses
    // only valid/xmin/ymin/xmax/ymax.
    // ========================================================================

    logic [15:0] unused_score_hdmi;

    roi_cdc_snapshot u_roi_to_hdmi (
        .src_clk_i       (ai_clk_i),
        .src_rstn_i      (ai_rstn_i),
        .src_update_i    (roi_update_ai),
        .src_valid_i     (roi_valid_camcoords_ai),
        .src_xmin_i      (roi_xmin_ai),
        .src_ymin_i      (roi_ymin_ai),
        .src_xmax_i      (roi_xmax_ai),
        .src_ymax_i      (roi_ymax_ai),
        .src_score_q16_i ({presence_q_ai_o, 8'h00}),

        .dst_clk_i       (hdmi_clk_i),
        .dst_rstn_i      (hdmi_rstn_i),
        .dst_update_o    (roi_update_hdmi_o),
        .dst_valid_o     (roi_valid_hdmi_o),
        .dst_xmin_o      (roi_xmin_hdmi_o),
        .dst_ymin_o      (roi_ymin_hdmi_o),
        .dst_xmax_o      (roi_xmax_hdmi_o),
        .dst_ymax_o      (roi_ymax_hdmi_o),
        .dst_score_q16_o (unused_score_hdmi)
    );

endmodule
