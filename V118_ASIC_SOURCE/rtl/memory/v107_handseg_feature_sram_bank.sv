`timescale 1ns/1ps
`default_nettype none
// One 64-bit logical feature bank implemented in 32-bit x 512 SKY130 macros.
// 1RW1R copies are MIRRORED so that read0 and read1 can occur concurrently
// with a write. Every write is committed into all replicas on the same edge.
// The upstream block must prevent same-address read/write collisions.
module v107_handseg_feature_sram_bank #(
    parameter integer WORDS = 512
)(
    input wire clk_i, input wire rstn_i,
    input wire rd0_fire_i, input wire [16:0] rd0_addr_i,
    input wire rd1_fire_i, input wire [16:0] rd1_addr_i,
    input wire wr_fire_i, input wire [16:0] wr_addr_i,
    input wire [63:0] wr_data_i,
    output wire [63:0] rd0_data_o, output wire [63:0] rd1_data_o
);
    localparam integer BLOCK_WORDS = 512;
    localparam integer BLOCKS = (WORDS + BLOCK_WORDS - 1) / BLOCK_WORDS;
    localparam integer SELW = (BLOCKS <= 1) ? 1 : $clog2(BLOCKS);
    reg [SELW-1:0] selected0_r, selected1_r;
    wire [63:0] data0 [0:BLOCKS-1];
    wire [63:0] data1 [0:BLOCKS-1];
    wire [7:0] rd0_block = rd0_addr_i[16:9];
    wire [7:0] rd1_block = rd1_addr_i[16:9];
    wire [7:0] wr_block  = wr_addr_i[16:9];

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            selected0_r <= {SELW{1'b0}};
            selected1_r <= {SELW{1'b0}};
        end else begin
            if (rd0_fire_i) selected0_r <= rd0_block[SELW-1:0];
            if (rd1_fire_i) selected1_r <= rd1_block[SELW-1:0];
        end
    end
    // Data is supplied by the macro read port. It becomes valid after the
    // macro's clock-to-Q delay, NOT combinationally at the sampling edge.
    // Hold the selected tile while a response is stalled.
    assign rd0_data_o = data0[selected0_r];
    assign rd1_data_o = data1[selected1_r];

    genvar b;
    generate for (b=0; b<BLOCKS; b=b+1) begin : g_tile
        wire r0_active = rd0_fire_i && (rd0_block == b);
        wire r1_active = rd1_fire_i && (rd1_block == b);
        wire wr_active = wr_fire_i && (wr_block == b);
        wire [31:0] d0_lo, d0_hi, d1_lo, d1_hi;
        // Duplicate copy A: read port 0, write port 0.
        sky130_sram_2kbyte_1rw1r_32x512_8 u_r0_lo (
            .clk0(clk_i), .csb0(~wr_active), .web0(1'b0),
            .wmask0(4'b1111), .addr0(wr_addr_i[8:0]),
            .din0(wr_data_i[31:0]), .dout0(),
            .clk1(clk_i), .csb1(~r0_active), .addr1(rd0_addr_i[8:0]),
            .dout1(d0_lo)
        );
        sky130_sram_2kbyte_1rw1r_32x512_8 u_r0_hi (
            .clk0(clk_i), .csb0(~wr_active), .web0(1'b0),
            .wmask0(4'b1111), .addr0(wr_addr_i[8:0]),
            .din0(wr_data_i[63:32]), .dout0(),
            .clk1(clk_i), .csb1(~r0_active), .addr1(rd0_addr_i[8:0]),
            .dout1(d0_hi)
        );
        // Duplicate copy B: independent read port 1, SAME writes as copy A.
        sky130_sram_2kbyte_1rw1r_32x512_8 u_r1_lo (
            .clk0(clk_i), .csb0(~wr_active), .web0(1'b0),
            .wmask0(4'b1111), .addr0(wr_addr_i[8:0]),
            .din0(wr_data_i[31:0]), .dout0(),
            .clk1(clk_i), .csb1(~r1_active), .addr1(rd1_addr_i[8:0]),
            .dout1(d1_lo)
        );
        sky130_sram_2kbyte_1rw1r_32x512_8 u_r1_hi (
            .clk0(clk_i), .csb0(~wr_active), .web0(1'b0),
            .wmask0(4'b1111), .addr0(wr_addr_i[8:0]),
            .din0(wr_data_i[63:32]), .dout0(),
            .clk1(clk_i), .csb1(~r1_active), .addr1(rd1_addr_i[8:0]),
            .dout1(d1_hi)
        );
        assign data0[b] = {d0_hi, d0_lo};
        assign data1[b] = {d1_hi, d1_lo};
    end endgenerate

`ifndef SYNTHESIS
    initial begin
        if (WORDS < 1 || WORDS > 131072)
            $fatal(1,"v107 invalid WORDS=%0d",WORDS);
    end
`endif
endmodule
`default_nettype wire
