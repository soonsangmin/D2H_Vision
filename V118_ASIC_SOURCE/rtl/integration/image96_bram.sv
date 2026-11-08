// ASIC portability: same synchronous read contract as FPGA V6.23 image96_bram.
// This describes 9216x16 logical bits. In standard-cell-only SKY130 flow,
// Yosys may map the memory to a *very large* number of gates and flops.
// A tapeout must use a characterized SRAM macro (or redesign as SDRAM tile)
// and re-run equivalence, STA, DRC/LVS. Do not claim this is a SRAM macro.
module image96_bram (
    input  logic        wr_clk_i,
    input  logic        wr_en_i,
    input  logic [13:0] wr_addr_i,
    input  logic [15:0] wr_data_i,
    input  logic        rd_clk_i,
    input  logic [13:0] rd_addr_i,
    output logic [15:0] rd_data_o
);
    logic [15:0] mem [0:9215];
    always_ff @(posedge wr_clk_i) begin
        if (wr_en_i && (wr_addr_i < 14'd9216))
            mem[wr_addr_i] <= wr_data_i;
    end
    always_ff @(posedge rd_clk_i) begin
        if (rd_addr_i < 14'd9216)
            rd_data_o <= mem[rd_addr_i];
        else
            rd_data_o <= 16'd0;
    end
endmodule
