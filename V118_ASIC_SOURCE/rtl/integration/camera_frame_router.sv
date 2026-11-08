module camera_frame_router (
    input  logic cam_pclk_i,
    input  logic writer_clk_i,
    input  logic rstn_i,

    // High only while the HandSeg frame gate is forwarding the one frame
    // selected for AI processing.
    input  logic ai_capture_active_cam_i,

    // Synchronized destination level for the single camera SDRAM writer.
    // 0 -> 0x3000_0000 (HDMI current frame)
    // 1 -> 0x3200_0000 (frozen AI snapshot)
    output logic write_sel_ai_o,

    // Camera-domain observability. Exactly one destination is asserted.
    output logic frame_to_hdmi_cam_o,
    output logic frame_to_ai_cam_o
);
    logic ai_meta_r;

    assign frame_to_ai_cam_o   = ai_capture_active_cam_i;
    assign frame_to_hdmi_cam_o = ~ai_capture_active_cam_i;

    // The camera stream itself is not duplicated.  This synchronizer only
    // transports the selected destination to the 50-MHz writer.  The writer
    // latches it when the first packed word of a frame is accepted.
    always_ff @(posedge writer_clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            ai_meta_r      <= 1'b0;
            write_sel_ai_o <= 1'b0;
        end else begin
            ai_meta_r      <= ai_capture_active_cam_i;
            write_sel_ai_o <= ai_meta_r;
        end
    end

    // cam_pclk_i is intentionally present in the interface to make the source
    // domain explicit for integration / CDC review.
    logic unused_cam_clk;
    assign unused_cam_clk = cam_pclk_i;
endmodule
