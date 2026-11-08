`timescale 1ns/1ps
module tb_asic_sram_1r1w;
reg clk=0; always #5 clk=~clk;
reg we=0,re=0; reg [3:0] wa=0,ra=0; reg [7:0] wd=0;
wire [7:0] q;
asic_sram_1r1w #(.DATA_WIDTH(8),.DEPTH(16),.ADDR_WIDTH(4)) dut
(.clk_i(clk),.wr_en_i(we),.wr_addr_i(wa),.wr_data_i(wd),
 .rd_en_i(re),.rd_addr_i(ra),.rd_data_o(q));
initial begin
  @(negedge clk); we=1;wa=3;wd=8'h5a;re=0;
  @(negedge clk); we=0;re=1;ra=3;
  @(posedge clk); #1; if(q!==8'h5a) $fatal(1,"read back mismatch");
  @(negedge clk);we=1;wa=3;wd=8'h7c;re=1;ra=3;
  @(posedge clk); #1; if(q!==8'h5a) $fatal(1,"read-during-write must return old data");
  @(negedge clk);we=0;re=1;ra=3;
  @(posedge clk); #1; if(q!==8'h7c) $fatal(1,"updated data mismatch");
  @(negedge clk);re=0;
  @(posedge clk); #1; if(q!==8'h7c) $fatal(1,"read output must hold when disabled");
  $display("PASS tb_asic_sram_1r1w: enable/hold/read-old collision"); $finish;
end
endmodule
