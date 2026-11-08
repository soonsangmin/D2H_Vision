`timescale 1ns/1ps
`default_nettype none
// V110: Actual V109 memory subsystem, FULL eight banks and all 1,128 macros.
// This is NOT an AI compute top. Every read/write interface is top-observable,
// preventing synthesis from legally pruning unused SRAM branches.
module v110_handseg_8bank_sram_probe (
    input wire clk_i, input wire rstn_i,
    input wire rd0_req_valid_i, output wire rd0_req_ready_o,
    input wire [2:0] rd0_req_bank_i,
    input wire [16:0] rd0_req_addr_i,
    output wire rd0_rsp_valid_o,
    input wire rd0_rsp_ready_i,
    output wire [63:0] rd0_rsp_data_o,
    input wire rd1_req_valid_i, output wire rd1_req_ready_o,
    input wire [2:0] rd1_req_bank_i,
    input wire [16:0] rd1_req_addr_i,
    output wire rd1_rsp_valid_o,
    input wire rd1_rsp_ready_i,
    output wire [63:0] rd1_rsp_data_o,
    input wire wr_valid_i, output wire wr_ready_o,
    input wire [2:0] wr_bank_i,
    input wire [16:0] wr_addr_i,
    input wire [63:0] wr_data_i
);
    // EMPTY INIT deliberately enables the physical SRAM branch.
    // DO NOT alter depths or delete ports for synthesis convenience.
    reference_feature_memory #(.BANK0_INIT_FILE("")) u_feature_memory (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .rd0_req_valid_i(rd0_req_valid_i),
        .rd0_req_ready_o(rd0_req_ready_o),
        .rd0_req_bank_i(rd0_req_bank_i),
        .rd0_req_addr_i(rd0_req_addr_i),
        .rd0_rsp_valid_o(rd0_rsp_valid_o),
        .rd0_rsp_ready_i(rd0_rsp_ready_i),
        .rd0_rsp_data_o(rd0_rsp_data_o),
        .rd1_req_valid_i(rd1_req_valid_i),
        .rd1_req_ready_o(rd1_req_ready_o),
        .rd1_req_bank_i(rd1_req_bank_i),
        .rd1_req_addr_i(rd1_req_addr_i),
        .rd1_rsp_valid_o(rd1_rsp_valid_o),
        .rd1_rsp_ready_i(rd1_rsp_ready_i),
        .rd1_rsp_data_o(rd1_rsp_data_o),
        .wr_valid_i(wr_valid_i),
        .wr_ready_o(wr_ready_o),
        .wr_bank_i(wr_bank_i),
        .wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i)
    );
endmodule
`default_nettype wire
