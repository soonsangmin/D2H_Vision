`timescale 1ns/1ps
// V1.04 PROTOCOL-LEVEL TEST MODEL ONLY. Not OpenRAM timing model.
// Synchronous outputs held if chip-select is inactive. Undefined collisions
// are deliberately rejected instead of pretending to model their behavior.
module sky130_sram_1kbyte_1rw1r_32x256_8 (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input clk0,
    input csb0,
    input web0,
    input [3:0] wmask0,
    input [7:0] addr0,
    input [31:0] din0,
    output reg [31:0] dout0,
    input clk1,
    input csb1,
    input [7:0] addr1,
    output reg [31:0] dout1
);
    reg [31:0] mem [0:255];
    integer k;
    always @(posedge clk0) begin
      if (!csb0) begin
        if (!web0) begin
          for(k=0;k<4;k=k+1)
            if(wmask0[k]) mem[addr0][8*k +: 8] <= din0[8*k +: 8];
        end else dout0 <= mem[addr0];
      end
    end
    always @(posedge clk1) begin
      if (!csb1) dout1 <= mem[addr1];
      else dout1 <= 32'hxxxxxxxx; // exercise hold adapter; not timing-accurate
    end
endmodule
