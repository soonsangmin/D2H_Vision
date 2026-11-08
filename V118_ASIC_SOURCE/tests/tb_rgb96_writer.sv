`timescale 1ns/1ps
module tb_rgb96_writer;
  reg clk=0; always #5 clk=~clk;
  reg rstn=0,frame_start=0,frame_end=0,pvalid=0,wready=0;
  reg [13:0] paddr=0;
  reg [15:0] pdata=0;
  wire pready,wvalid,finished,error;
  wire [31:0] waddr;
  wire [63:0] wdata;
  integer sent=0,received=0,cycle=0;
  reg pixel_fire,write_fire,end_sent=0;
  reg [63:0] expected_data;
  asic_rgb96_ddr_writer dut(
    .clk_i(clk),.rstn_i(rstn),.frame_start_i(frame_start),
    .frame_end_i(frame_end),.pixel_valid_i(pvalid),.pixel_ready_o(pready),
    .pixel_addr_i(paddr),.pixel_data_i(pdata),.wr_valid_o(wvalid),
    .wr_ready_i(wready),.wr_addr_o(waddr),.wr_data_o(wdata),
    .finished_o(finished),.alignment_error_o(error)
  );
  function [15:0] pixel_pattern(input integer n);
    pixel_pattern = (n ^ (n<<3) ^ 16'hA5C3);
  endfunction
  initial begin
    repeat(4) @(negedge clk);
    rstn=1;
    @(negedge clk); frame_start=1;
    @(negedge clk); frame_start=0;
    while (!finished && cycle<90000) begin
      // Drive stimuli at negedge; DUT consumes on following posedge.
      wready=((cycle%11)!=0 && (cycle%11)!=1 && (cycle%19)!=0);
      pvalid=(sent<9216) && ((cycle%7)!=3);
      paddr=sent;
      pdata=pixel_pattern(sent);
      #1;
      pixel_fire=pvalid && pready;
      write_fire=wvalid && wready;
      if (write_fire) begin
        expected_data = {pixel_pattern(received*4+3),pixel_pattern(received*4+2),
                         pixel_pattern(received*4+1),pixel_pattern(received*4)};
        if (waddr!==32'h36000000+received*8 || wdata!==expected_data)
          $fatal(1,"DDR word mismatch idx=%0d address=%h got=%h expected=%h",received,waddr,wdata,expected_data);
      end
      @(posedge clk);
      if (pixel_fire) sent=sent+1;
      if (write_fire) received=received+1;
      @(negedge clk);
      cycle=cycle+1;
      frame_end=(sent==9216 && !end_sent);
      if (frame_end) end_sent=1;
    end
    if (!finished || error || sent!=9216 || received!=2304)
      $fatal(1,"FAIL finish=%b error=%b sent=%0d received=%0d",finished,error,sent,received);
    $display("PASS tb_rgb96_writer: sent=%0d writes=%0d cycles=%0d",sent,received,cycle);
    $finish;
  end
endmodule
