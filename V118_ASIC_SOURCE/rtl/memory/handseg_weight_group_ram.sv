// V6.1.6 - Physical banking for long M10K weight caches.
// API and one-cycle read behavior match V6.1.5 for all in-range addresses.
// USE_BANKED_M10K can be switched off to isolate RAM-banking regressions.
module handseg_weight_group_ram #(
    parameter integer DEPTH = 512,
    parameter integer ADDR_W = 9,
    parameter bit USE_MLAB = 1'b0,
    parameter bit USE_BANKED_M10K = 1'b1
) (
    input  logic              clk_i,
    input  logic              wr_en_i,
    input  logic [ADDR_W-1:0] wr_addr_i,
    input  logic [63:0]       wr_data_i,
    input  logic [ADDR_W-1:0] rd_addr_i,
    output logic [63:0]       rd_data_o
);
    generate
        if (USE_MLAB) begin : gen_mlab
            (* ramstyle = "MLAB" *) logic [63:0] mem [0:DEPTH-1];
            always_ff @(posedge clk_i) begin
                if (wr_en_i)
                    mem[wr_addr_i] <= wr_data_i;
                rd_data_o <= mem[rd_addr_i];
            end
        end else if (USE_BANKED_M10K && DEPTH > 1024 && ADDR_W >= 11) begin : gen_banked_m10k
            localparam integer BANK_COUNT = (DEPTH + 1023) / 1024;
            localparam integer BANK_W = ADDR_W - 10;
            wire [BANK_W-1:0] rd_bank = rd_addr_i[ADDR_W-1:10];
            wire [BANK_W-1:0] wr_bank = wr_addr_i[ADDR_W-1:10];
            logic [BANK_W-1:0] rd_bank_q;
            wire [63:0] rd_q [0:BANK_COUNT-1];
            genvar bank_idx;
            for (bank_idx=0; bank_idx<BANK_COUNT; bank_idx=bank_idx+1) begin : g_bank
                (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mem [0:1023];
                logic [63:0] data_q;
                always_ff @(posedge clk_i) begin
                    if (wr_en_i && wr_bank == bank_idx)
                        mem[wr_addr_i[9:0]] <= wr_data_i;
                    if (rd_bank == bank_idx)
                        data_q <= mem[rd_addr_i[9:0]];
                end
                assign rd_q[bank_idx] = data_q;
            end
            always_ff @(posedge clk_i) begin
                rd_bank_q <= rd_bank;
            end
            always_comb begin
                rd_data_o = rd_q[rd_bank_q];
            end
        end else begin : gen_m10k
            (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mem [0:DEPTH-1];
            always_ff @(posedge clk_i) begin
                if (wr_en_i)
                    mem[wr_addr_i] <= wr_data_i;
                rd_data_o <= mem[rd_addr_i];
            end
        end
    endgenerate
endmodule
