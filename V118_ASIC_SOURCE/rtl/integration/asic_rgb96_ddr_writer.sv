`timescale 1ns/1ps
`default_nettype none
// Pack 96x96 RGB565 pixels into 2304 64-bit transactions.
// One pixel accepted only when pixel_valid && pixel_ready.
// Source must produce monotonically increasing pixel addresses 0..9215.
// finished_o means ALL writes accepted by the external adapter; it does not
// guarantee DRAM commit. Top-level additionally gates on mem_wr_drain_done_i.
module asic_rgb96_ddr_writer #(
    parameter logic [31:0] FRAME_BASE=32'h3600_0000
)(
    input logic clk_i, rstn_i,
    input logic frame_start_i,
    input logic frame_end_i,
    input logic pixel_valid_i,
    output logic pixel_ready_o,
    input logic [13:0] pixel_addr_i,
    input logic [15:0] pixel_data_i,
    output logic wr_valid_o,
    input logic wr_ready_i,
    output logic [31:0] wr_addr_o,
    output logic [63:0] wr_data_o,
    output logic finished_o,
    output logic alignment_error_o
);
    localparam integer FRAME_WORDS=2304;
    logic [1:0] lane_r;
    logic [63:0] partial_r;
    logic [11:0] word_index_r;
    logic [13:0] pixel_index_r;
    logic end_seen_r;
    assign pixel_ready_o = !wr_valid_o && !finished_o && !end_seen_r && !frame_start_i;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            lane_r<=2'd0;
            partial_r<=64'd0;
            word_index_r<=12'd0;
            pixel_index_r<=14'd0;
            end_seen_r<=1'b0;
            wr_valid_o<=1'b0;
            wr_addr_o<=32'd0;
            wr_data_o<=64'd0;
            finished_o<=1'b0;
            alignment_error_o<=1'b0;
        end else if (frame_start_i) begin
            lane_r<=2'd0;
            partial_r<=64'd0;
            word_index_r<=12'd0;
            pixel_index_r<=14'd0;
            end_seen_r<=1'b0;
            wr_valid_o<=1'b0;
            wr_addr_o<=FRAME_BASE;
            wr_data_o<=64'd0;
            finished_o<=1'b0;
            alignment_error_o<=1'b0;
        end else begin
            if (frame_end_i) begin
                end_seen_r<=1'b1;
                if (pixel_index_r!=14'd9216 || lane_r!=0)
                    alignment_error_o<=1'b1;
            end
            if (pixel_valid_i && pixel_ready_o) begin
                if (pixel_addr_i!=pixel_index_r || pixel_index_r>=14'd9216)
                    alignment_error_o<=1'b1;
                pixel_index_r<=pixel_index_r+14'd1;
                if (lane_r==2'd3) begin
                    wr_data_o<={pixel_data_i, partial_r[47:0]};
                    wr_addr_o<=FRAME_BASE+({20'd0,word_index_r}<<3);
                    wr_valid_o<=1'b1;
                    lane_r<=2'd0;
                end else begin
                    case (lane_r)
                        2'd0: partial_r[15:0]<=pixel_data_i;
                        2'd1: partial_r[31:16]<=pixel_data_i;
                        2'd2: partial_r[47:32]<=pixel_data_i;
                        default: partial_r[63:48]<=pixel_data_i;
                    endcase
                    lane_r<=lane_r+2'd1;
                end
            end
            if (wr_valid_o && wr_ready_i) begin
                wr_valid_o<=1'b0;
                word_index_r<=word_index_r+12'd1;
                if (word_index_r==FRAME_WORDS-1 && (end_seen_r || frame_end_i))
                    finished_o<=1'b1;
            end
            if (end_seen_r && !wr_valid_o && word_index_r==FRAME_WORDS && lane_r==0)
                finished_o<=1'b1;
        end
    end
endmodule
`default_nettype wire
