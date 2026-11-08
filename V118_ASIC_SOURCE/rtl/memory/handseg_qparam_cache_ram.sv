module handseg_qparam_cache_ram #(
    parameter integer DEPTH  = 32,
    parameter integer ADDR_W = 5,
    parameter integer WIDTH  = 904
) (
    input  logic                  clk_i,
    input  logic                  wr_en_i,
    input  logic [ADDR_W-1:0]     wr_addr_i,
    input  logic [WIDTH-1:0]      wr_data_i,
    input  logic [ADDR_W-1:0]     rd_addr_i,
    output logic [WIDTH-1:0]      rd_data_o
);
    // V6.0.5: the 32-deep x 904-wide banks fragment M10Ks heavily.
    // Map these tiny-depth tables into MLAB to reclaim block RAMs.
    // This exchanges some ALM/MLAB capacity for M10K; validate Quartus placement.
    (* ramstyle = "MLAB" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk_i) begin
        if (wr_en_i)
            mem[wr_addr_i] <= wr_data_i;
        rd_data_o <= mem[rd_addr_i];
    end
endmodule
