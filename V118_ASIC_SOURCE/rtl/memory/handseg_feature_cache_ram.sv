module handseg_feature_cache_ram #(
    parameter integer DEPTH  = 2048,
    parameter integer ADDR_W = 11,
    parameter integer WIDTH  = 74
)(
    input  logic                  clk_i,
    input  logic [ADDR_W-1:0]     rd_addr_i,
    output logic [WIDTH-1:0]      rd_data_o,
    input  logic                  wr_en_i,
    input  logic [ADDR_W-1:0]     wr_addr_i,
    input  logic [WIDTH-1:0]      wr_data_i
);
    // One synchronous read port + one write port.  Keeping the read fully
    // clocked is important for Quartus 18.1 M10K inference.
    (* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk_i) begin
        rd_data_o <= mem[rd_addr_i];
        if (wr_en_i)
            mem[wr_addr_i] <= wr_data_i;
    end
endmodule
