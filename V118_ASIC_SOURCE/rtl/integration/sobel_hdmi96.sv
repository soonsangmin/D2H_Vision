// -----------------------------------------------------------------------------
// HDMI debug consumer for the Sobel classifier input image.
// SW1=1 displays the 96x96 binary Sobel image enlarged exactly 5x to 480x480,
// centered inside 640x480 (80 black pixels at left and right).
// -----------------------------------------------------------------------------
module sobel_hdmi96 (
    input  logic        clk_i,
    input  logic        rstn_i,

    input  logic        enable_i,
    input  logic        sobel96_ready_pulse_i,
    input  logic        source_busy_i,

    input  logic        req_valid_i,
    input  logic [9:0]  req_x_i,
    input  logic [8:0]  req_y_i,

    input  logic        out_valid_i,
    input  logic [9:0]  out_x_i,
    input  logic [8:0]  out_y_i,

    output logic [13:0] bram_rd_addr_o,
    input  logic [7:0]  bram_rd_data_i,

    output logic        override_o,
    output logic [15:0] override_pixel_o,
    output logic        sobel96_consumed_o
);
    logic has_image_r;
    logic wait_next_frame_r;
    logic displaying_new_frame_r;

    logic req_inside_c;
    logic out_inside_c;
    logic [9:0] rel_x_c;
    logic [6:0] src_x_c;
    logic [6:0] src_y_c;

    always_comb begin
        req_inside_c = req_valid_i &&
                       (req_x_i >= 10'd80) && (req_x_i <= 10'd559) &&
                       (req_y_i <= 9'd479);

        rel_x_c = (req_x_i >= 10'd80) ? (req_x_i - 10'd80) : 10'd0;
        src_x_c = req_inside_c ? (rel_x_c / 10'd5) : 7'd0;
        src_y_c = req_inside_c ? ({1'b0, req_y_i} / 10'd5) : 7'd0;

        bram_rd_addr_o = ({7'd0, src_y_c} << 6)
                       + ({7'd0, src_y_c} << 5)
                       + src_x_c;

        out_inside_c = out_valid_i &&
                       (out_x_i >= 10'd80) && (out_x_i <= 10'd559) &&
                       (out_y_i <= 9'd479);

        override_o = enable_i;

        // Sobel is 8-bit grayscale/binary. Convert to RGB565. The current
        // golden convolution emits only 8'h00 or 8'hFF, therefore this becomes
        // exact black/white on HDMI.
        if (enable_i && has_image_r && !source_busy_i && out_inside_c)
            override_pixel_o = {bram_rd_data_i[7:3],
                                bram_rd_data_i[7:2],
                                bram_rd_data_i[7:3]};
        else
            override_pixel_o = 16'h0000;
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            has_image_r            <= 1'b0;
            wait_next_frame_r      <= 1'b0;
            displaying_new_frame_r <= 1'b0;
            sobel96_consumed_o     <= 1'b0;
        end else begin
            sobel96_consumed_o <= 1'b0;

            if (sobel96_ready_pulse_i) begin
                has_image_r            <= 1'b1;
                wait_next_frame_r      <= 1'b1;
                displaying_new_frame_r <= 1'b0;
            end

            // Acknowledge only after a complete HDMI frame displaying the new
            // Sobel image, preserving the V5.6 consumer semantics.
            if (enable_i && wait_next_frame_r && out_valid_i &&
                (out_x_i == 10'd0) && (out_y_i == 9'd0)) begin
                wait_next_frame_r      <= 1'b0;
                displaying_new_frame_r <= 1'b1;
            end

            if (enable_i && displaying_new_frame_r && out_valid_i &&
                (out_x_i == 10'd639) && (out_y_i == 9'd479)) begin
                displaying_new_frame_r <= 1'b0;
                sobel96_consumed_o     <= 1'b1;
            end
        end
    end
endmodule
