// V117: NONFUNCTIONAL SRAM payload placeholders ONLY.
// These are NOT working memories and must NEVER be submitted for fabrication.
(* blackbox *) module v117_MISSING_ROW_RAM (
  input CLK, input WE, input [15:0] WADDR, input [7:0] WDATA,
  input [15:0] RADDR, output [7:0] RDATA);
endmodule
(* blackbox *) module v117_MISSING_VECTOR_RAM192 (
  input CLK, input WE, input [9:0] WADDR, input [191:0] WDATA,
  input [9:0] RADDR, output [191:0] RDATA);
endmodule
(* blackbox *) module v117_MISSING_VECTOR_RAM256 (
  input CLK, input WE, input [9:0] WADDR, input [255:0] WDATA,
  input [9:0] RADDR, output [255:0] RDATA);
endmodule
(* blackbox *) module v117_MISSING_VECTOR_RAM512 (
  input CLK, input WE, input [9:0] WADDR, input [511:0] WDATA,
  input [9:0] RADDR, output [511:0] RDATA);
endmodule
(* blackbox *) module v117_MISSING_VECTOR_RAM1024 (
  input CLK, input WE, input [9:0] WADDR, input [1023:0] WDATA,
  input [9:0] RADDR, output [1023:0] RDATA);
endmodule
