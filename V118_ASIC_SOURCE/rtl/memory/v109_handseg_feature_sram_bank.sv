`timescale 1ns/1ps
`default_nettype none
// V109: single-copy 64-bit x N bank with two 32-bit x 512 macro lanes.
// Macro port0 is RW, used either for read0 or write; port1 is read1.
// The parent v109 wrapper guarantees no write and read0 are asserted
// for the same 512-word tile in one cycle. It also blocks same-word
// collisions between read1 and write (undefined in vendor model).
// This halves macro count while keeping both read ports simultaneous;
// writes may stall more often than the V107 mirrored implementation.
module v109_handseg_feature_sram_bank #(
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
    assign rd0_data_o = data0[selected0_r];
    assign rd1_data_o = data1[selected1_r];

    genvar b;
    generate for (b=0; b<BLOCKS; b=b+1) begin : g_tile
        wire r0_active = rd0_fire_i && (rd0_block == b);
        wire r1_active = rd1_fire_i && (rd1_block == b);
        wire wr_active = wr_fire_i && (wr_block == b);
        wire rw_selected = r0_active || wr_active;
        wire [8:0] rw_addr = wr_active ? wr_addr_i[8:0] : rd0_addr_i[8:0];
        wire [31:0] d0_lo, d0_hi, d1_lo, d1_hi;
        // Port 0 read when web0=1; write when web0=0 (both active low).
        sky130_sram_2kbyte_1rw1r_32x512_8 u_lo (
            .clk0(clk_i), .csb0(~rw_selected), .web0(~wr_active),
            .wmask0(4'b1111), .addr0(rw_addr),
            .din0(wr_data_i[31:0]), .dout0(d0_lo),
            .clk1(clk_i), .csb1(~r1_active), .addr1(rd1_addr_i[8:0]),
            .dout1(d1_lo)
        );
        sky130_sram_2kbyte_1rw1r_32x512_8 u_hi (
            .clk0(clk_i), .csb0(~rw_selected), .web0(~wr_active),
            .wmask0(4'b1111), .addr0(rw_addr),
            .din0(wr_data_i[63:32]), .dout0(d0_hi),
            .clk1(clk_i), .csb1(~r1_active), .addr1(rd1_addr_i[8:0]),
            .dout1(d1_hi)
        );
        assign data0[b] = {d0_hi, d0_lo};
        assign data1[b] = {d1_hi, d1_lo};
`ifndef SYNTHESIS
        always @(posedge clk_i) if (rstn_i) begin
            if (r0_active && wr_active)
                $fatal(1, "V109 invalid simultaneous RW read0/write tile=%0d", b);
            if (r1_active && wr_active && (rd1_addr_i[8:0] == wr_addr_i[8:0]))
                $fatal(1, "V109 forbidden same-word read1/write tile=%0d", b);
        end
`endif
    end endgenerate
`ifndef SYNTHESIS
    initial begin
        if (WORDS < 1 || WORDS > 131072)
            $fatal(1,"v109 invalid WORDS=%0d",WORDS);
    end
`endif
endmodule
`default_nettype wire
