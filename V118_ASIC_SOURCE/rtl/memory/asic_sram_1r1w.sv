`timescale 1ns/1ps
`default_nettype none
// V1.04: 1 read / 1 write byte RAM interface.
// Default mode = V1.03 full-depth behavioral memory (read-first, hold).
// ASIC_USE_SKY130_SRAM = physical-macro boundary for *DATA_WIDTH=8 ONLY*.
// One 1024-byte bank = sky130_sram_1kbyte_1rw1r_32x256_8.
// The hard macro does NOT guarantee read-old on simultaneous same-word R/W.
// Caller must avoid same 32-bit word read/write collisions; the CNN completed-
// row FIFO never exposes a row until producer completes its writes.
// The simulation model used for tests is not a Liberty/timing/signoff model.
(* keep_hierarchy = "yes" *)
module asic_sram_1r1w #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH = 9216,
    parameter integer ADDR_WIDTH = (DEPTH <= 2 ? 1 : $clog2(DEPTH))
)(
    input wire clk_i,
    input wire wr_en_i,
    input wire [ADDR_WIDTH-1:0] wr_addr_i,
    input wire [DATA_WIDTH-1:0] wr_data_i,
    input wire rd_en_i,
    input wire [ADDR_WIDTH-1:0] rd_addr_i,
    output wire [DATA_WIDTH-1:0] rd_data_o
);
`ifdef ASIC_USE_SKY130_SRAM
    // The storage mapping below is a byte-oriented banked adapter, not SRAM
    // inference. Macro can service a read and write on independent ports.
    localparam integer BYTES_PER_BANK = 1024;
    localparam integer BANKS = (DEPTH + BYTES_PER_BANK - 1) / BYTES_PER_BANK;
    localparam integer BANK_W = (BANKS <= 2 ? 1 : $clog2(BANKS));
    // Every legal address is < DEPTH. This bank index is constant zero for
    // small-memory testcases and is optimized by synthesis in that case.
    wire [ADDR_WIDTH-1:0] wr_bank_index = wr_addr_i >> 10;
    wire [ADDR_WIDTH-1:0] rd_bank_index = rd_addr_i >> 10;
    wire [7:0] wr_word_index = (wr_addr_i >> 2);
    wire [7:0] rd_word_index = (rd_addr_i >> 2);
    wire [3:0] wr_mask = 4'b0001 << wr_addr_i[1:0];
    wire [31:0] wr_word = {4{wr_data_i}};
    wire [31:0] bank_q [0:BANKS-1];
    reg [BANK_W-1:0] rd_bank_q;
    reg [1:0] rd_lane_q;
    reg [31:0] selected_word;
    reg [7:0] held_byte_q;
    reg previous_read_en_q;
    wire [7:0] selected_byte;
    integer sel;
    genvar b;
    generate
      if (DATA_WIDTH == 8 && DEPTH >= 1 && ADDR_WIDTH >= 2) begin : g_byte_macro
        for (b = 0; b < BANKS; b = b + 1) begin : g_bank
          wire wr_this_bank = wr_en_i && (wr_bank_index == b);
          wire rd_this_bank = rd_en_i && (rd_bank_index == b);
          // OpenRAM native interface: port 0 = write, port 1 = read.
          // Use byte-masked writes to avoid read-modify-write for each pixel.
          sky130_sram_1kbyte_1rw1r_32x256_8 u_macro (
              .clk0(clk_i), .csb0(~wr_this_bank), .web0(1'b0),
              .wmask0(wr_mask), .addr0(wr_word_index),
              .din0(wr_word), .dout0(),
              .clk1(clk_i), .csb1(~rd_this_bank),
              .addr1(rd_word_index), .dout1(bank_q[b])
          );
        end
        always @(posedge clk_i) begin
          // When idle, some OpenRAM models invalidate dout1 at the clock
          // edge. Preserve the LAST completed read value in a flop.
          // Data from the prior active read is stable at this edge.
          if (previous_read_en_q) held_byte_q <= selected_byte;
          previous_read_en_q <= rd_en_i;
          if (rd_en_i) begin
            rd_bank_q <= rd_bank_index[BANK_W-1:0];
            rd_lane_q <= rd_addr_i[1:0];
          end
        end
        always @* begin
          selected_word = 32'h00000000;
          for (sel = 0; sel < BANKS; sel = sel + 1)
            if (rd_bank_q == sel) selected_word = bank_q[sel];
        end
        assign selected_byte = selected_word[8*rd_lane_q +: 8];
        // Active read passes through macro; idle returns registered hold.
        assign rd_data_o = previous_read_en_q ? selected_byte : held_byte_q;
      end else begin : g_invalid_params
        // Fail explicitly rather than silently producing an unimplementable
        // large inferred RAM in the hard-macro configuration.
        initial $fatal(1, "SKY130 macro adapter requires 8-bit data and ADDR_WIDTH >= 2");
        assign rd_data_o = {DATA_WIDTH{1'bx}};
      end
    endgenerate
`ifndef SYNTHESIS
    // OpenRAM 1rw1r collision behavior must not be used as a source of data.
    // Check at 32-bit word granularity, including different byte lanes.
    always @(posedge clk_i) begin
      if (wr_en_i && rd_en_i && (wr_addr_i >> 2) == (rd_addr_i >> 2))
        $fatal(1,"V104 SRAM macro same-word read/write collision");
      if (wr_en_i && (wr_addr_i >= DEPTH))
        $fatal(1,"V104 SRAM macro write address outside DEPTH");
      if (rd_en_i && (rd_addr_i >= DEPTH))
        $fatal(1,"V104 SRAM macro read address outside DEPTH");
    end
`endif
`else
    // Preserved V1.03 reference functionality; no memory mocking.
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] q;
    always @(posedge clk_i) begin
        if (wr_en_i) mem[wr_addr_i] <= wr_data_i;
        if (rd_en_i) q <= mem[rd_addr_i];
    end
    assign rd_data_o = q;
`endif
endmodule
`default_nettype wire
