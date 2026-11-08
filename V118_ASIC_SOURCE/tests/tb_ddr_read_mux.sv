`timescale 1ns/1ps
module tb_ddr_read_mux;
  reg clk=0; always #5 clk=~clk;
  reg rstn=0,crop_sel=0,cls_sel=0;
  reg det_valid=0,crop_valid=0,cls_valid=0,mem_ready=1,rsp_valid=0;
  reg det_rsp_ready=1,crop_rsp_ready=1,cls_rsp_ready=1;
  wire det_ready,crop_ready,cls_ready;
  wire det_rsp_valid,crop_rsp_valid,cls_rsp_valid,mem_valid,mem_rsp_ready;
  wire [31:0] mem_addr;
  reg [63:0] rsp_data=64'h89ABCDEF_12345678;
  wire [63:0] det_data,crop_data,cls_data;
  ai_ddr_read_mux dut(
    .clk_i(clk),.rstn_i(rstn),.crop_select_i(crop_sel),.classifier_select_i(cls_sel),
    .cls_rd_req_valid_i(cls_valid),.cls_rd_req_ready_o(cls_ready),
    .cls_rd_req_addr_i(32'h36000000),.cls_rd_rsp_valid_o(cls_rsp_valid),
    .cls_rd_rsp_ready_i(cls_rsp_ready),.cls_rd_rsp_data_o(cls_data),
    .det_rd_req_valid_i(det_valid),.det_rd_req_ready_o(det_ready),
    .det_rd_req_addr_i(32'h34000000),.det_rd_rsp_valid_o(det_rsp_valid),
    .det_rd_rsp_ready_i(det_rsp_ready),.det_rd_rsp_data_o(det_data),
    .crop_rd_req_valid_i(crop_valid),.crop_rd_req_ready_o(crop_ready),
    .crop_rd_req_addr_i(32'h32000000),.crop_rd_rsp_valid_o(crop_rsp_valid),
    .crop_rd_rsp_ready_i(crop_rsp_ready),.crop_rd_rsp_data_o(crop_data),
    .ddr_rd_req_valid_o(mem_valid),.ddr_rd_req_ready_i(mem_ready),
    .ddr_rd_req_addr_o(mem_addr),.ddr_rd_rsp_valid_i(rsp_valid),
    .ddr_rd_rsp_ready_o(mem_rsp_ready),.ddr_rd_rsp_data_i(rsp_data)
  );
  initial begin
    repeat(3) @(negedge clk);
    rstn=1;
    det_valid=1;
    #1; if (!mem_valid || mem_addr!==32'h34000000 || !det_ready) $fatal(1,"Detector request not granted");
    @(negedge clk); det_valid=0;crop_sel=1;crop_valid=1;
    rsp_valid=1;det_rsp_ready=0;
    #1; if (mem_valid || !det_rsp_valid || crop_rsp_valid || mem_rsp_ready)
      $fatal(1,"Ownership changed while detector response was stalled");
    @(negedge clk); det_rsp_ready=1;
    #1; if(!det_rsp_valid || !mem_rsp_ready || det_data!==rsp_data) $fatal(1,"Detector response lost");
    @(negedge clk); rsp_valid=0;
    #1; if(!mem_valid || mem_addr!==32'h32000000) $fatal(1,"Crop not granted");
    @(negedge clk); crop_valid=0;cls_sel=1;cls_valid=1;rsp_valid=1;
    #1; if(!crop_rsp_valid || cls_rsp_valid || mem_valid) $fatal(1,"Crop response misrouted");
    @(negedge clk); rsp_valid=0;
    #1; if(!mem_valid || mem_addr!==32'h36000000) $fatal(1,"Classifier not granted");
    @(negedge clk); cls_valid=0;rsp_valid=1;
    #1; if(!cls_rsp_valid || crop_rsp_valid || det_rsp_valid) $fatal(1,"Classifier response misrouted");
    @(negedge clk);
    $display("PASS tb_ddr_read_mux: detector/crop/classifier ownership protected");
    $finish;
  end
endmodule
