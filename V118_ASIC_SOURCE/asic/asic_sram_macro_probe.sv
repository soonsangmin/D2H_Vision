`timescale 1ns/1ps
`default_nettype none
// Integration PROBE only: one byte-addressed SRAM macro, NOT the AI chip.
module asic_sram_macro_probe (
   input wire clk_i,
   input wire wr_en_i,
   input wire [9:0] wr_addr_i,
   input wire [7:0] wr_data_i,
   input wire rd_en_i,
   input wire [9:0] rd_addr_i,
   output wire [7:0] rd_data_o
);
   asic_sram_1r1w #(.DATA_WIDTH(8),.DEPTH(1024),.ADDR_WIDTH(10)) u_sram (
     .clk_i(clk_i),.wr_en_i(wr_en_i),.wr_addr_i(wr_addr_i),
     .wr_data_i(wr_data_i),.rd_en_i(rd_en_i),.rd_addr_i(rd_addr_i),
     .rd_data_o(rd_data_o)
   );
endmodule
`default_nettype wire
