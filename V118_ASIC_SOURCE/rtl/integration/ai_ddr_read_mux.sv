`timescale 1ns/1ps
`default_nettype none
// ASIC V1.02: single-outstanding ordered read arbiter.
// A transaction is owned by the selected client from the accepted request
// until its final response handshake, even if crop/classifier selection changes.
// Memory contract: one response per accepted read, response not combinational
// in the same cycle as request, and response stable under !ready.
module ai_ddr_read_mux (
    input logic clk_i,
    input logic rstn_i,
    input logic crop_select_i,
    input logic classifier_select_i,
    input logic cls_rd_req_valid_i,
    output logic cls_rd_req_ready_o,
    input logic [31:0] cls_rd_req_addr_i,
    output logic cls_rd_rsp_valid_o,
    input logic cls_rd_rsp_ready_i,
    output logic [63:0] cls_rd_rsp_data_o,
    input logic det_rd_req_valid_i,
    output logic det_rd_req_ready_o,
    input logic [31:0] det_rd_req_addr_i,
    output logic det_rd_rsp_valid_o,
    input logic det_rd_rsp_ready_i,
    output logic [63:0] det_rd_rsp_data_o,
    input logic crop_rd_req_valid_i,
    output logic crop_rd_req_ready_o,
    input logic [31:0] crop_rd_req_addr_i,
    output logic crop_rd_rsp_valid_o,
    input logic crop_rd_rsp_ready_i,
    output logic [63:0] crop_rd_rsp_data_o,
    output logic ddr_rd_req_valid_o,
    input logic ddr_rd_req_ready_i,
    output logic [31:0] ddr_rd_req_addr_o,
    input logic ddr_rd_rsp_valid_i,
    output logic ddr_rd_rsp_ready_o,
    input logic [63:0] ddr_rd_rsp_data_i
);
    localparam logic [1:0] C_DET=2'd0, C_CROP=2'd1, C_CLASS=2'd2;
    logic pending_r;
    logic [1:0] owner_r;
    logic [1:0] choose_c;
    always_comb begin
        if (classifier_select_i) choose_c=C_CLASS;
        else if (crop_select_i) choose_c=C_CROP;
        else choose_c=C_DET;
    end
    always_comb begin
        cls_rd_req_ready_o=1'b0;
        det_rd_req_ready_o=1'b0;
        crop_rd_req_ready_o=1'b0;
        cls_rd_rsp_valid_o=1'b0;
        det_rd_rsp_valid_o=1'b0;
        crop_rd_rsp_valid_o=1'b0;
        cls_rd_rsp_data_o=ddr_rd_rsp_data_i;
        det_rd_rsp_data_o=ddr_rd_rsp_data_i;
        crop_rd_rsp_data_o=ddr_rd_rsp_data_i;
        ddr_rd_req_valid_o=1'b0;
        ddr_rd_req_addr_o=32'd0;
        ddr_rd_rsp_ready_o=1'b0;
        if (!pending_r) begin
            case (choose_c)
                C_CLASS: begin
                    ddr_rd_req_valid_o=cls_rd_req_valid_i;
                    ddr_rd_req_addr_o=cls_rd_req_addr_i;
                    cls_rd_req_ready_o=ddr_rd_req_ready_i;
                end
                C_CROP: begin
                    ddr_rd_req_valid_o=crop_rd_req_valid_i;
                    ddr_rd_req_addr_o=crop_rd_req_addr_i;
                    crop_rd_req_ready_o=ddr_rd_req_ready_i;
                end
                default: begin
                    ddr_rd_req_valid_o=det_rd_req_valid_i;
                    ddr_rd_req_addr_o=det_rd_req_addr_i;
                    det_rd_req_ready_o=ddr_rd_req_ready_i;
                end
            endcase
        end else begin
            case (owner_r)
                C_CLASS: begin
                    cls_rd_rsp_valid_o=ddr_rd_rsp_valid_i;
                    ddr_rd_rsp_ready_o=cls_rd_rsp_ready_i;
                end
                C_CROP: begin
                    crop_rd_rsp_valid_o=ddr_rd_rsp_valid_i;
                    ddr_rd_rsp_ready_o=crop_rd_rsp_ready_i;
                end
                default: begin
                    det_rd_rsp_valid_o=ddr_rd_rsp_valid_i;
                    ddr_rd_rsp_ready_o=det_rd_rsp_ready_i;
                end
            endcase
        end
    end
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            pending_r<=1'b0;
            owner_r<=C_DET;
        end else if (!pending_r) begin
            if (ddr_rd_req_valid_o && ddr_rd_req_ready_i) begin
                pending_r<=1'b1;
                owner_r<=choose_c;
            end
        end else if (ddr_rd_rsp_valid_i && ddr_rd_rsp_ready_o) begin
            pending_r<=1'b0;
        end
    end
endmodule
`default_nettype wire
