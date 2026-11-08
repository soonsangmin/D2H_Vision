// V1.06: per-bank allocation derived from 82-entry schedule, 65 layer and
// 3 concat descriptors; see scripts/v106_bank_depth_audit.py.
// Address units = 64-bit words. All depths are multiples of 128 words (1 KiB),
// to support later byte-lane macro banking. This is NOT SRAM macro mapping.
// `DEPTH_WORDS > 0` explicitly forces the old same-depth allocation for
// comparison/legacy simulation; default 0 selects schedule-bounded depths.
module reference_feature_memory #(
    parameter integer DEPTH_WORDS = 0,
    parameter BANK0_INIT_FILE = "golden/stage_hex/02_model_input_u8x8_320x256.hex"
)(
    input  logic clk_i,
    input  logic rstn_i,

    input  logic        rd0_req_valid_i,
    output logic        rd0_req_ready_o,
    input  logic [2:0]  rd0_req_bank_i,
    input  logic [16:0] rd0_req_addr_i,
    output logic        rd0_rsp_valid_o,
    input  logic        rd0_rsp_ready_i,
    output logic [63:0] rd0_rsp_data_o,

    input  logic        rd1_req_valid_i,
    output logic        rd1_req_ready_o,
    input  logic [2:0]  rd1_req_bank_i,
    input  logic [16:0] rd1_req_addr_i,
    output logic        rd1_rsp_valid_o,
    input  logic        rd1_rsp_ready_i,
    output logic [63:0] rd1_rsp_data_o,

    input  logic        wr_valid_i,
    output logic        wr_ready_o,
    input  logic [2:0]  wr_bank_i,
    input  logic [16:0] wr_addr_i,
    input  logic [63:0] wr_data_i
);
    localparam integer B0_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 122880; // bank0 960 KiB
    localparam integer B1_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 61440; // bank1 480 KiB
    localparam integer B2_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 46080; // bank2 360 KiB
    localparam integer B3_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 5120; // bank3 40 KiB
    localparam integer B4_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 1280; // bank4 10 KiB
    localparam integer B5_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 384; // bank5 3 KiB
    localparam integer B6_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 46080; // bank6 360 KiB
    localparam integer B7_WORDS = (DEPTH_WORDS > 0) ? DEPTH_WORDS : 5120; // bank7 40 KiB

    // Physical feature-memory path is opt-in at compile time.
    // The reference/golden initialization path remains inferred RAM.
`ifdef V107_HARD_FEATURE_SRAM
    localparam integer HARD_FEATURE_ENABLED = (BANK0_INIT_FILE == "");
`else
    localparam integer HARD_FEATURE_ENABLED = 0;
`endif
    generate if (HARD_FEATURE_ENABLED) begin : g_v107_physical
`ifdef V109_SINGLE_COPY_SRAM
        v109_handseg_feature_memory_macro #(
`else
        v107_handseg_feature_memory_macro #(
`endif
            .B0(B0_WORDS), .B1(B1_WORDS), .B2(B2_WORDS), .B3(B3_WORDS),
            .B4(B4_WORDS), .B5(B5_WORDS), .B6(B6_WORDS), .B7(B7_WORDS)
        ) u_physical (
            .clk_i(clk_i), .rstn_i(rstn_i),
            .rd0_req_valid_i(rd0_req_valid_i), .rd0_req_ready_o(rd0_req_ready_o),
            .rd0_req_bank_i(rd0_req_bank_i), .rd0_req_addr_i(rd0_req_addr_i),
            .rd0_rsp_valid_o(rd0_rsp_valid_o), .rd0_rsp_ready_i(rd0_rsp_ready_i),
            .rd0_rsp_data_o(rd0_rsp_data_o),
            .rd1_req_valid_i(rd1_req_valid_i), .rd1_req_ready_o(rd1_req_ready_o),
            .rd1_req_bank_i(rd1_req_bank_i), .rd1_req_addr_i(rd1_req_addr_i),
            .rd1_rsp_valid_o(rd1_rsp_valid_o), .rd1_rsp_ready_i(rd1_rsp_ready_i),
            .rd1_rsp_data_o(rd1_rsp_data_o),
            .wr_valid_i(wr_valid_i), .wr_ready_o(wr_ready_o),
            .wr_bank_i(wr_bank_i), .wr_addr_i(wr_addr_i), .wr_data_i(wr_data_i)
        );
    end else begin : g_v106_reference

    logic [63:0] bank0_mem [0:B0_WORDS-1];
    logic [63:0] bank1_mem [0:B1_WORDS-1];
    logic [63:0] bank2_mem [0:B2_WORDS-1];
    logic [63:0] bank3_mem [0:B3_WORDS-1];
    logic [63:0] bank4_mem [0:B4_WORDS-1];
    logic [63:0] bank5_mem [0:B5_WORDS-1];
    logic [63:0] bank6_mem [0:B6_WORDS-1];
    logic [63:0] bank7_mem [0:B7_WORDS-1];

    initial begin
        if (BANK0_INIT_FILE != "")
            $readmemh(BANK0_INIT_FILE, bank0_mem);
    end

    function automatic [63:0] bank_read(input logic [2:0] bank, input logic [16:0] addr);
        begin
            case (bank)
                3'd0: bank_read = bank0_mem[addr];
                3'd1: bank_read = bank1_mem[addr];
                3'd2: bank_read = bank2_mem[addr];
                3'd3: bank_read = bank3_mem[addr];
                3'd4: bank_read = bank4_mem[addr];
                3'd5: bank_read = bank5_mem[addr];
                3'd6: bank_read = bank6_mem[addr];
                default: bank_read = bank7_mem[addr];
            endcase
        end
    endfunction

    task automatic bank_write(input logic [2:0] bank, input logic [16:0] addr, input logic [63:0] data);
        begin
            case (bank)
                3'd0: bank0_mem[addr] <= data;
                3'd1: bank1_mem[addr] <= data;
                3'd2: bank2_mem[addr] <= data;
                3'd3: bank3_mem[addr] <= data;
                3'd4: bank4_mem[addr] <= data;
                3'd5: bank5_mem[addr] <= data;
                3'd6: bank6_mem[addr] <= data;
                default: bank7_mem[addr] <= data;
            endcase
        end
    endtask


`ifndef SYNTHESIS
    // Simulation-only guard: never silently alias out-of-range addresses.
    // Only accepted requests are checked. No gate-level logic is added.
    function automatic integer bank_depth(input logic [2:0] bank);
        case (bank)
            3'd0: bank_depth = B0_WORDS;
            3'd1: bank_depth = B1_WORDS;
            3'd2: bank_depth = B2_WORDS;
            3'd3: bank_depth = B3_WORDS;
            3'd4: bank_depth = B4_WORDS;
            3'd5: bank_depth = B5_WORDS;
            3'd6: bank_depth = B6_WORDS;
            default: bank_depth = B7_WORDS;
        endcase
    endfunction

    always @(posedge clk_i) begin
        if (rstn_i) begin
            if (rd0_req_valid_i && rd0_req_ready_o &&
                ($unsigned(rd0_req_addr_i) >= bank_depth(rd0_req_bank_i)))
                $fatal(1, "V106 OOB read0 bank=%0d addr=%0d depth=%0d",
                       rd0_req_bank_i, rd0_req_addr_i, bank_depth(rd0_req_bank_i));
            if (rd1_req_valid_i && rd1_req_ready_o &&
                ($unsigned(rd1_req_addr_i) >= bank_depth(rd1_req_bank_i)))
                $fatal(1, "V106 OOB read1 bank=%0d addr=%0d depth=%0d",
                       rd1_req_bank_i, rd1_req_addr_i, bank_depth(rd1_req_bank_i));
            if (wr_valid_i && wr_ready_o &&
                ($unsigned(wr_addr_i) >= bank_depth(wr_bank_i)))
                $fatal(1, "V106 OOB write bank=%0d addr=%0d depth=%0d",
                       wr_bank_i, wr_addr_i, bank_depth(wr_bank_i));
        end
    end
`endif

    logic rd0_valid_r, rd1_valid_r;
    assign rd0_rsp_valid_o = rd0_valid_r;
    assign rd1_rsp_valid_o = rd1_valid_r;
    assign rd0_req_ready_o = ~rd0_valid_r | rd0_rsp_ready_i;
    assign rd1_req_ready_o = ~rd1_valid_r | rd1_rsp_ready_i;
    assign wr_ready_o = 1'b1;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            rd0_valid_r <= 1'b0;
            rd1_valid_r <= 1'b0;
        end else begin
            if (rd0_req_ready_o) begin
                rd0_valid_r <= rd0_req_valid_i;
                if (rd0_req_valid_i)
                    rd0_rsp_data_o <= bank_read(rd0_req_bank_i, rd0_req_addr_i);
            end
            if (rd1_req_ready_o) begin
                rd1_valid_r <= rd1_req_valid_i;
                if (rd1_req_valid_i)
                    rd1_rsp_data_o <= bank_read(rd1_req_bank_i, rd1_req_addr_i);
            end
            if (wr_valid_i)
                bank_write(wr_bank_i, wr_addr_i, wr_data_i);
        end
    end
    end endgenerate
endmodule
