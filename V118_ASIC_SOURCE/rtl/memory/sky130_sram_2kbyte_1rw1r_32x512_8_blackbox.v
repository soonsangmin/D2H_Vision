`default_nettype none
// Synthesis-only blackbox declaration. NOT a simulation SRAM model.
// Replace at simulation with the upstream OpenRAM .v view.
(* blackbox *) module sky130_sram_2kbyte_1rw1r_32x512_8 (
`ifdef USE_POWER_PINS
    inout wire vccd1, vssd1,
`endif
    input wire clk0, csb0, web0,
    input wire [3:0] wmask0,
    input wire [8:0] addr0,
    input wire [31:0] din0,
    output wire [31:0] dout0,
    input wire clk1, csb1,
    input wire [8:0] addr1,
    output wire [31:0] dout1
);
endmodule
`default_nettype wire
