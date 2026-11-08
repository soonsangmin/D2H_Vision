`timescale 1ns/1ps
module tb_v104_byte_addressing;
  localparam integer DEPTH=2083; // three banks, incomplete last bank
  localparam integer AW=$clog2(DEPTH);
  reg clk=0;
  always #5 clk=~clk;
  reg we=0, re=0;
  reg [AW-1:0] wa=0, ra=0;
  reg [7:0] wd=0;
  wire [7:0] q;
  integer i;
  reg [7:0] expected;
  asic_sram_1r1w #(.DATA_WIDTH(8), .DEPTH(DEPTH), .ADDR_WIDTH(AW)) dut (
    .clk_i(clk), .wr_en_i(we), .wr_addr_i(wa), .wr_data_i(wd),
    .rd_en_i(re), .rd_addr_i(ra), .rd_data_o(q)
  );
  function [7:0] val(input integer idx);
    begin val = ((idx*73) ^ (idx>>3) ^ 8'hA9) & 8'hFF; end
  endfunction
  initial begin
    // Write every byte, exercising all four mask lanes and three banks.
    for(i=0;i<DEPTH;i=i+1) begin
      @(negedge clk); we=1; re=0; wa=i; wd=val(i);
    end
    @(negedge clk); we=0;
    // Check exact value, bank crossing, and hold on disabled cycles.
    for(i=0;i<DEPTH;i=i+1) begin
      @(negedge clk); re=1; ra=i;
      @(posedge clk); #1;
      expected=val(i);
      if(q !== expected)
        $fatal(1,"SRAM mismatch byte=%0d got=%02h want=%02h",i,q,expected);
      @(negedge clk); re=0;
      @(posedge clk); #1;
      if(q !== expected)
        $fatal(1,"SRAM read-hold mismatch byte=%0d",i);
    end
    $display("PASS tb_v104_byte_addressing: bytes=%0d banks=3",DEPTH);
    $finish;
  end
endmodule
