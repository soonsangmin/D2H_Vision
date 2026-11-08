module handseg_ddr_feature_memory #(
    parameter logic [31:0] FEATURE_BASE = 32'h3400_0000,
    parameter logic [31:0] BANK_STRIDE  = 32'h0010_0000,
    // V6.0.1: default LOW-M10K mode.  Set to 1 only if there is enough M10K
    // headroom and lower DDR traffic is more important than FPGA RAM usage.
    parameter bit          USE_LOCAL_SKIP_RAM = 1'b0
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
    input  logic [63:0] wr_data_i,

    output logic        ddr_rd_req_valid_o,
    input  logic        ddr_rd_req_ready_i,
    output logic [31:0] ddr_rd_req_addr_o,
    input  logic        ddr_rd_rsp_valid_i,
    output logic        ddr_rd_rsp_ready_o,
    input  logic [63:0] ddr_rd_rsp_data_i,

    output logic        ddr_wr_req_valid_o,
    input  logic        ddr_wr_req_ready_i,
    output logic [31:0] ddr_wr_req_addr_o,
    output logic [63:0] ddr_wr_req_data_o
);

    // =====================================================================
    // V4.2 HYBRID FEATURE MEMORY POLICY
    // =====================================================================
    // Large ping-pong/work banks stay in HPS DDR3:
    //   BANK_A    (0) -> FEATURE_BASE + 0 * BANK_STRIDE
    //   BANK_B    (1) -> FEATURE_BASE + 1 * BANK_STRIDE
    //   BANK_TEMP (2) -> FEATURE_BASE + 2 * BANK_STRIDE
    //   BANK_AUX  (6) -> FEATURE_BASE + 6 * BANK_STRIDE
    //
    // V6.0.1 LOW-M10K default:
    // Persistent decoder skip maps and the final mask are routed to HPS DDR3
    // as well.  Earlier revisions kept these four tensors in M10K to reduce
    // DDR traffic, but the combined HandSeg + classifier design exceeds the
    // 553 physical M10K locations of the target device.  USE_LOCAL_SKIP_RAM
    // can restore the old behavior for experiments with a larger device.
    //
    // IMPORTANT: all local memories use CLOCKED/SYNCHRONOUS reads.  The older
    // V4 implementation used asynchronous array reads; Quartus 18.1 therefore
    // failed to infer RAM and expanded them into registers.  This version has
    // no asynchronous access to any local memory array.
    //
    // Packed 64-bit depths from the frozen HandSeg V1.4.1 topology:
    //   SKIP80 : 80 * 64 * 1 group = 5120 words = 40 KiB
    //   SKIP40 : 40 * 32 * 1 group = 1280 words = 10 KiB
    //   SKIP20 : 20 * 16 * 1 group =  320 words = 2.5 KiB
    //   MASK   : 80 * 64 * 1 group = 5120 words = 40 KiB
    // =====================================================================

    localparam logic [2:0] BANK_A      = 3'd0;
    localparam logic [2:0] BANK_B      = 3'd1;
    localparam logic [2:0] BANK_TEMP   = 3'd2;
    localparam logic [2:0] BANK_SKIP80 = 3'd3;
    localparam logic [2:0] BANK_SKIP40 = 3'd4;
    localparam logic [2:0] BANK_SKIP20 = 3'd5;
    localparam logic [2:0] BANK_AUX    = 3'd6;
    localparam logic [2:0] BANK_MASK   = 3'd7;

    localparam integer SKIP80_DEPTH = 5120;
    localparam integer SKIP40_DEPTH = 1280;
    localparam integer SKIP20_DEPTH = 320;
    localparam integer MASK_DEPTH   = 5120;

    // ASIC V1.03: preserve original local SRAM behavior when enabled.
    // With USE_LOCAL_SKIP_RAM==0, do not elaborate unused FPGA RAM arrays;
    // drive q ports to known zero to prevent undriven nets in Yosys.
    wire [63:0] skip80_q_r, skip40_q_r, skip20_q_r, mask_q_r;

    function automatic logic is_local_bank(input logic [2:0] bank);
        begin
            if (!USE_LOCAL_SKIP_RAM) begin
                is_local_bank = 1'b0;
            end
            else begin
                case (bank)
                    BANK_SKIP80,
                    BANK_SKIP40,
                    BANK_SKIP20,
                    BANK_MASK: is_local_bank = 1'b1;
                    default:   is_local_bank = 1'b0;
                endcase
            end
        end
    endfunction

    // BANK_STRIDE is compile-time constant.  Explicit decode avoids a generic
    // variable multiply in the address path.
    function automatic logic [31:0] bank_base(input logic [2:0] bank);
        begin
            case (bank)
                BANK_A:      bank_base = FEATURE_BASE;
                BANK_B:      bank_base = FEATURE_BASE + BANK_STRIDE;
                BANK_TEMP:   bank_base = FEATURE_BASE + (BANK_STRIDE << 1);
                BANK_SKIP80: bank_base = FEATURE_BASE + (BANK_STRIDE << 1) + BANK_STRIDE;
                BANK_SKIP40: bank_base = FEATURE_BASE + (BANK_STRIDE << 2);
                BANK_SKIP20: bank_base = FEATURE_BASE + (BANK_STRIDE << 2) + BANK_STRIDE;
                BANK_AUX:    bank_base = FEATURE_BASE + (BANK_STRIDE << 2) + (BANK_STRIDE << 1);
                default:     bank_base = FEATURE_BASE + (BANK_STRIDE << 2) +
                                           (BANK_STRIDE << 1) + BANK_STRIDE;
            endcase
        end
    endfunction

    function automatic logic [31:0] word_addr(
        input logic [2:0]  bank,
        input logic [16:0] addr
    );
        begin
            // addr is a packed 64-bit word index -> byte address = addr * 8.
            word_addr = bank_base(bank) + {12'd0, addr, 3'b000};
        end
    endfunction

    // =====================================================================
    // LOCAL M10K WRITE PORTS + SYNCHRONOUS READ PORTS
    // =====================================================================

    logic        local_rd_en_c;
    logic [2:0]  local_rd_bank_c;
    logic [16:0] local_rd_addr_c;
    logic [63:0] local_q_c;

    generate if (USE_LOCAL_SKIP_RAM) begin : g_local_skip_enabled
        // Identical 1R1W synchronous FPGA RAM access as V1.02.
        (* ramstyle = "M10K, no_rw_check" *) logic [63:0] skip80_mem [0:SKIP80_DEPTH-1];
        (* ramstyle = "M10K, no_rw_check" *) logic [63:0] skip40_mem [0:SKIP40_DEPTH-1];
        (* ramstyle = "M10K, no_rw_check" *) logic [63:0] skip20_mem [0:SKIP20_DEPTH-1];
        (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mask_mem [0:MASK_DEPTH-1];
        logic [63:0] skip80_q, skip40_q, skip20_q, mask_q;
        always_ff @(posedge clk_i) begin
            if (wr_valid_i && (wr_bank_i == BANK_SKIP80))
                skip80_mem[wr_addr_i[12:0]] <= wr_data_i;
            if (local_rd_en_c && (local_rd_bank_c == BANK_SKIP80))
                skip80_q <= skip80_mem[local_rd_addr_c[12:0]];
        end
        always_ff @(posedge clk_i) begin
            if (wr_valid_i && (wr_bank_i == BANK_SKIP40))
                skip40_mem[wr_addr_i[10:0]] <= wr_data_i;
            if (local_rd_en_c && (local_rd_bank_c == BANK_SKIP40))
                skip40_q <= skip40_mem[local_rd_addr_c[10:0]];
        end
        always_ff @(posedge clk_i) begin
            if (wr_valid_i && (wr_bank_i == BANK_SKIP20))
                skip20_mem[wr_addr_i[8:0]] <= wr_data_i;
            if (local_rd_en_c && (local_rd_bank_c == BANK_SKIP20))
                skip20_q <= skip20_mem[local_rd_addr_c[8:0]];
        end
        always_ff @(posedge clk_i) begin
            if (wr_valid_i && (wr_bank_i == BANK_MASK))
                mask_mem[wr_addr_i[12:0]] <= wr_data_i;
            if (local_rd_en_c && (local_rd_bank_c == BANK_MASK))
                mask_q <= mask_mem[local_rd_addr_c[12:0]];
        end
        assign skip80_q_r=skip80_q;
        assign skip40_q_r=skip40_q;
        assign skip20_q_r=skip20_q;
        assign mask_q_r=mask_q;
    end else begin : g_local_skip_disabled
        assign skip80_q_r = 64'd0;
        assign skip40_q_r = 64'd0;
        assign skip20_q_r = 64'd0;
        assign mask_q_r   = 64'd0;
    end endgenerate

    always_comb begin
        case (local_rd_bank_c)
            BANK_SKIP80: local_q_c = skip80_q_r;
            BANK_SKIP40: local_q_c = skip40_q_r;
            BANK_SKIP20: local_q_c = skip20_q_r;
            BANK_MASK:   local_q_c = mask_q_r;
            default:     local_q_c = 64'd0;
        endcase
    end

    // Local writes complete in one FPGA clock.  DDR writes retain the existing
    // ready/valid backpressure and ordering.
    assign ddr_wr_req_valid_o = wr_valid_i && !is_local_bank(wr_bank_i);
    assign ddr_wr_req_addr_o  = word_addr(wr_bank_i, wr_addr_i);
    assign ddr_wr_req_data_o  = wr_data_i;
    assign wr_ready_o         = is_local_bank(wr_bank_i) ? 1'b1
                                                         : ddr_wr_req_ready_i;

    // =====================================================================
    // ORDERED TWO-CLIENT READ FSM
    // =====================================================================
    // rd0/rd1 are accepted together in IDLE, exactly as in V4.1.  rd0 is
    // serviced first, then a captured rd1 request.  A request is dispatched to
    // either a synchronous M10K read or the ordered DDR read interface.
    // Keeping one read in flight at a time makes the memory semantics simple
    // and deterministic and is acceptable because the design trades latency
    // for low FPGA resource use.

    typedef enum logic [3:0] {
        R_IDLE,
        R0_DISPATCH,
        R0_DREQ,
        R0_DWAIT,
        R0_LWAIT,
        R0_HOLD,
        R1_DISPATCH,
        R1_DREQ,
        R1_DWAIT,
        R1_LWAIT,
        R1_HOLD
    } rstate_t;

    rstate_t rstate_r;

    logic [2:0]  r0_bank_r;
    logic [2:0]  r1_bank_r;
    logic [16:0] r0_addr_r;
    logic [16:0] r1_addr_r;
    logic        have1_r;
    logic [63:0] rsp0_data_r;
    logic [63:0] rsp1_data_r;

    assign rd0_req_ready_o = (rstate_r == R_IDLE);
    assign rd1_req_ready_o = (rstate_r == R_IDLE);

    assign rd0_rsp_valid_o = (rstate_r == R0_HOLD);
    assign rd1_rsp_valid_o = (rstate_r == R1_HOLD);
    assign rd0_rsp_data_o  = rsp0_data_r;
    assign rd1_rsp_data_o  = rsp1_data_r;

    always_comb begin
        ddr_rd_req_valid_o = 1'b0;
        ddr_rd_req_addr_o  = 32'd0;
        ddr_rd_rsp_ready_o = 1'b0;

        local_rd_en_c   = 1'b0;
        local_rd_bank_c = 3'd0;
        local_rd_addr_c = 17'd0;

        case (rstate_r)
            R0_DISPATCH: begin
                if (is_local_bank(r0_bank_r)) begin
                    local_rd_en_c   = 1'b1;
                    local_rd_bank_c = r0_bank_r;
                    local_rd_addr_c = r0_addr_r;
                end
            end

            R0_DREQ: begin
                ddr_rd_req_valid_o = 1'b1;
                ddr_rd_req_addr_o  = word_addr(r0_bank_r, r0_addr_r);
            end

            R0_DWAIT: begin
                ddr_rd_rsp_ready_o = 1'b1;
            end

            R0_LWAIT: begin
                // Keep bank/address selected so local_q_c selects the proper
                // registered M10K output during response capture.
                local_rd_bank_c = r0_bank_r;
                local_rd_addr_c = r0_addr_r;
            end

            R1_DISPATCH: begin
                if (is_local_bank(r1_bank_r)) begin
                    local_rd_en_c   = 1'b1;
                    local_rd_bank_c = r1_bank_r;
                    local_rd_addr_c = r1_addr_r;
                end
            end

            R1_DREQ: begin
                ddr_rd_req_valid_o = 1'b1;
                ddr_rd_req_addr_o  = word_addr(r1_bank_r, r1_addr_r);
            end

            R1_DWAIT: begin
                ddr_rd_rsp_ready_o = 1'b1;
            end

            R1_LWAIT: begin
                local_rd_bank_c = r1_bank_r;
                local_rd_addr_c = r1_addr_r;
            end

            default: begin end
        endcase
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            rstate_r    <= R_IDLE;
            r0_bank_r   <= 3'd0;
            r1_bank_r   <= 3'd0;
            r0_addr_r   <= 17'd0;
            r1_addr_r   <= 17'd0;
            have1_r     <= 1'b0;
            rsp0_data_r <= 64'd0;
            rsp1_data_r <= 64'd0;
        end
        else begin
            case (rstate_r)
                R_IDLE: begin
                    if (rd0_req_valid_i || rd1_req_valid_i) begin
                        have1_r <= rd0_req_valid_i && rd1_req_valid_i;

                        if (rd0_req_valid_i) begin
                            r0_bank_r <= rd0_req_bank_i;
                            r0_addr_r <= rd0_req_addr_i;
                        end

                        if (rd1_req_valid_i) begin
                            r1_bank_r <= rd1_req_bank_i;
                            r1_addr_r <= rd1_req_addr_i;
                        end

                        if (rd0_req_valid_i)
                            rstate_r <= R0_DISPATCH;
                        else
                            rstate_r <= R1_DISPATCH;
                    end
                end

                R0_DISPATCH: begin
                    if (is_local_bank(r0_bank_r))
                        rstate_r <= R0_LWAIT;
                    else
                        rstate_r <= R0_DREQ;
                end

                R0_DREQ: begin
                    if (ddr_rd_req_ready_i)
                        rstate_r <= R0_DWAIT;
                end

                R0_DWAIT: begin
                    if (ddr_rd_rsp_valid_i) begin
                        rsp0_data_r <= ddr_rd_rsp_data_i;
                        rstate_r    <= R0_HOLD;
                    end
                end

                R0_LWAIT: begin
                    rsp0_data_r <= local_q_c;
                    rstate_r    <= R0_HOLD;
                end

                R0_HOLD: begin
                    if (rd0_rsp_ready_i) begin
                        if (have1_r)
                            rstate_r <= R1_DISPATCH;
                        else
                            rstate_r <= R_IDLE;
                    end
                end

                R1_DISPATCH: begin
                    if (is_local_bank(r1_bank_r))
                        rstate_r <= R1_LWAIT;
                    else
                        rstate_r <= R1_DREQ;
                end

                R1_DREQ: begin
                    if (ddr_rd_req_ready_i)
                        rstate_r <= R1_DWAIT;
                end

                R1_DWAIT: begin
                    if (ddr_rd_rsp_valid_i) begin
                        rsp1_data_r <= ddr_rd_rsp_data_i;
                        rstate_r    <= R1_HOLD;
                    end
                end

                R1_LWAIT: begin
                    rsp1_data_r <= local_q_c;
                    rstate_r    <= R1_HOLD;
                end

                R1_HOLD: begin
                    if (rd1_rsp_ready_i) begin
                        have1_r <= 1'b0;
                        rstate_r <= R_IDLE;
                    end
                end

                default: begin
                    have1_r  <= 1'b0;
                    rstate_r <= R_IDLE;
                end
            endcase
        end
    end

endmodule
