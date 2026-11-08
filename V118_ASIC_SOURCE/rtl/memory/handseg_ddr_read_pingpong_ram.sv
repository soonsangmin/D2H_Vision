module handseg_ddr_read_pingpong_ram (
    input  logic         clk_i,

    input  logic         wr_en_i,
    input  logic [3:0]   wr_addr_i,
    input  logic [255:0] wr_data_i,

    input  logic [3:0]   rd_addr_i,
    output logic [255:0] rd_data_o
);
    // V5.1: two 256-byte DDR read lines in one M10K-style RAM.
    // Address bit [3] selects ping/pong bank, [2:0] selects one of 8
    // 256-bit Avalon beats inside that bank.
    (* ramstyle = "MLAB" *)
    logic [255:0] mem [0:15];

    always_ff @(posedge clk_i) begin
        if (wr_en_i)
            mem[wr_addr_i] <= wr_data_i;
        rd_data_o <= mem[rd_addr_i];
    end
endmodule
