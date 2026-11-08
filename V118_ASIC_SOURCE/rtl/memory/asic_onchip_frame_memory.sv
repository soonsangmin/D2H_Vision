`timescale 1ns/1ps
`default_nettype none
// V1.05: true full-depth on-chip snapshot + ROI frame buffers.
// No off-chip DDR, no memory mocking. 64-bit little-endian memory words.
// SNAPSHOT: packed RGB565 640x480, 4 pixels/word. Host cannot write weights;
// detector parameters are synthesized separately from local parameter_store_v141.
// RGB96: 96x96 pixels, packed by existing asic_rgb96_ddr_writer.
// NOTE: large inferred SRAMs still require actual physical implementation.
module asic_onchip_frame_memory #(
    parameter integer SNAPSHOT_PIXELS = 640*480,
    parameter integer RGB96_WORDS = 2304
) (
    input  wire clk_i,
    input  wire rstn_i,
    input  wire cam_capture_active_i,
    input  wire cam_pixel_valid_i,
    input  wire [15:0] cam_pixel_rgb565_i,
    output wire snapshot_ready_o,
    output reg  access_error_o,
    input  wire rd_req_valid_i,
    output wire rd_req_ready_o,
    input  wire [31:0] rd_req_addr_i,
    output reg  rd_rsp_valid_o,
    input  wire rd_rsp_ready_i,
    output reg  [63:0] rd_rsp_data_o,
    input  wire wr_req_valid_i,
    output wire wr_req_ready_o,
    input  wire [31:0] wr_req_addr_i,
    input  wire [63:0] wr_req_data_i
);
    localparam logic [31:0] SNAP_BASE = 32'h3200_0000;
    localparam logic [31:0] RGB_BASE  = 32'h3600_0000;
    localparam integer SNAP_WORDS = (SNAPSHOT_PIXELS + 3) / 4;
    localparam integer COUNT_W = (SNAPSHOT_PIXELS < 2 ? 1 : $clog2(SNAPSHOT_PIXELS + 1));
    // Inferred on-chip storage. Full-depth synthesis MUST retain all words.
    (* ram_style = "block" *) reg [63:0] snapshot_mem [0:SNAP_WORDS-1];
    (* ram_style = "block" *) reg [63:0] rgb96_mem [0:RGB96_WORDS-1];
    reg [63:0] snap_partial_r;
    reg [COUNT_W-1:0] snap_count_r;
    reg active_last_r;
    reg snapshot_ready_r;
    wire snap_start = cam_capture_active_i && !active_last_r;
    assign snapshot_ready_o = snapshot_ready_r;

    // Snapshot writes are on an INDEPENDENT memory port, so camera pixels
    // cannot be backpressured or lost to RGB96 write traffic.
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            snap_count_r <= '0;
            snap_partial_r <= 64'd0;
            active_last_r <= 1'b0;
            snapshot_ready_r <= 1'b0;
        end else begin
            active_last_r <= cam_capture_active_i;
            if (snap_start) begin
                snap_count_r <= '0;
                snap_partial_r <= 64'd0;
                snapshot_ready_r <= 1'b0;
                if (cam_pixel_valid_i) begin
                    snap_partial_r <= {48'd0,cam_pixel_rgb565_i};
                    snap_count_r <= 1;
                end
            end else if (cam_capture_active_i && cam_pixel_valid_i &&
                         snap_count_r < SNAPSHOT_PIXELS) begin
                if (snap_count_r[1:0] == 2'd3) begin
                    snapshot_mem[snap_count_r >> 2] <=
                        {cam_pixel_rgb565_i,snap_partial_r[47:0]};
                    if (snap_count_r == SNAPSHOT_PIXELS - 1)
                        snapshot_ready_r <= 1'b1;
                end else begin
                    case (snap_count_r[1:0])
                        2'd0: snap_partial_r[15:0]  <= cam_pixel_rgb565_i;
                        2'd1: snap_partial_r[31:16] <= cam_pixel_rgb565_i;
                        2'd2: snap_partial_r[47:32] <= cam_pixel_rgb565_i;
                        default: ;
                    endcase
                end
                snap_count_r <= snap_count_r + 1'b1;
            end
        end
    end
    // Single outstanding ordered read response, 1 clock synchronous latency.
    wire snap_rd_hit = (rd_req_addr_i >= SNAP_BASE) &&
                       (rd_req_addr_i < SNAP_BASE + SNAP_WORDS*8) &&
                       (rd_req_addr_i[2:0] == 0);
    wire rgb_rd_hit = (rd_req_addr_i >= RGB_BASE) &&
                      (rd_req_addr_i < RGB_BASE + RGB96_WORDS*8) &&
                      (rd_req_addr_i[2:0] == 0);
    wire rgb_wr_hit = (wr_req_addr_i >= RGB_BASE) &&
                      (wr_req_addr_i < RGB_BASE + RGB96_WORDS*8) &&
                      (wr_req_addr_i[2:0] == 0);
    assign rd_req_ready_o = !rd_rsp_valid_o || rd_rsp_ready_i;
    assign wr_req_ready_o = 1'b1;

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            rd_rsp_valid_o <= 1'b0;
            rd_rsp_data_o <= 64'd0;
            access_error_o <= 1'b0;
        end else begin
            if (wr_req_valid_i && wr_req_ready_o) begin
                if (rgb_wr_hit)
                    rgb96_mem[(wr_req_addr_i - RGB_BASE) >> 3] <= wr_req_data_i;
                else
                    access_error_o <= 1'b1;
            end
            if (rd_req_ready_o) begin
                rd_rsp_valid_o <= rd_req_valid_i;
                if (rd_req_valid_i) begin
                    if (snap_rd_hit)
                        rd_rsp_data_o <= snapshot_mem[(rd_req_addr_i - SNAP_BASE) >> 3];
                    else if (rgb_rd_hit)
                        rd_rsp_data_o <= rgb96_mem[(rd_req_addr_i - RGB_BASE) >> 3];
                    else begin
                        rd_rsp_data_o <= 64'd0;
                        access_error_o <= 1'b1;
                    end
                end
            end
        end
    end
`ifndef SYNTHESIS
    initial begin
        if ((SNAPSHOT_PIXELS % 4) != 0)
            $fatal(1,"SNAPSHOT_PIXELS must be divisible by four");
        if (SNAPSHOT_PIXELS <= 0 || RGB96_WORDS <= 0)
            $fatal(1,"Invalid memory depths");
    end
    always @(posedge clk_i) begin
        if (rstn_i && rd_req_valid_i && rd_req_ready_o && !(snap_rd_hit || rgb_rd_hit))
            $fatal(1,"On-chip read outside memory map %h", rd_req_addr_i);
        if (rstn_i && wr_req_valid_i && !rgb_wr_hit)
            $fatal(1,"On-chip write outside RGB96 memory map %h", wr_req_addr_i);
    end
`endif
endmodule
`default_nettype wire
