`timescale 1ns/1ps
`default_nettype none
// A physical verification top for ONE 64-bit x 512 feature tile:
// exactly TWO physical 2KiB SRAMs, not a stand-in for the AI top.
module v109_handseg_feature_2macro_probe (
    input wire clk_i, input wire rstn_i,
    input wire rd0_fire_i, input wire [16:0] rd0_addr_i,
    input wire rd1_fire_i, input wire [16:0] rd1_addr_i,
    input wire wr_fire_i, input wire [16:0] wr_addr_i,
    input wire [63:0] wr_data_i,
    output wire [63:0] rd0_data_o, output wire [63:0] rd1_data_o
);
    v109_handseg_feature_sram_bank #(.WORDS(512)) u_bank (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire_i),.rd0_addr_i(rd0_addr_i),
        .rd1_fire_i(rd1_fire_i),.rd1_addr_i(rd1_addr_i),
        .wr_fire_i(wr_fire_i),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),
        .rd0_data_o(rd0_data_o),.rd1_data_o(rd1_data_o)
    );
endmodule
`default_nettype wire
