`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// COMPLETED-ROW FIFO - SCALAR-BYTE RAM IMPLEMENTATION
//
// Resource change versus the supplied source:
//   - Stores each accepted HWC byte directly in RAM.
//   - Removes the CHANNELS*DATA_WIDTH-bit wr_vec and rd_vec registers.
//   - Changes RAM shape from DEPTH*WIDTH words x CHANNELS*8 bits to
//     DEPTH*WIDTH*CHANNELS words x DATA_WIDTH bits.
//   - Keeps the external interface and the accepted HWC byte sequence.
//
// The RAM has one synchronous write and one synchronous read port. The output
// is a one-byte ready/valid register with one-byte look-ahead: a new RAM read
// is issued when the current output is empty or is accepted on this cycle.
// This permits one output byte per clock after startup when rd_ready is high.
//
// NOTE: RAM packing/block count must be confirmed in Quartus Fitter. Bit-exact
// ordering must be checked with tb_fifo_scalar_ram_bitexact.sv and the full
// MobileNet regression before replacing the known-good source.
// ============================================================================
module stream_interstage_row_fifo_hwc_stage2 #(
    parameter integer WIDTH      = 96,
    parameter integer HEIGHT     = 96,
    parameter integer CHANNELS   = 24,
    parameter integer DEPTH      = 3,
    parameter integer DATA_WIDTH = 8
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          wr_valid,
    input  wire [DATA_WIDTH-1:0]         wr_pixel,
    input  wire [DATA_WIDTH-1:0]         wr_ch_idx,
    output wire                          wr_ready,

    output wire [7:0]                    completed_rows,

    output wire                          rd_valid,
    output wire [DATA_WIDTH-1:0]         rd_pixel,
    output wire [DATA_WIDTH-1:0]         rd_ch_idx,
    output wire [7:0]                    rd_row_idx,
    input  wire                          rd_ready,

    output wire                          empty,
    output wire                          full
);
    localparam integer COL_W       = (WIDTH <= 2) ? 1 : $clog2(WIDTH);
    localparam integer SLOT_W      = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer CH_W        = (CHANNELS <= 2) ? 1 : $clog2(CHANNELS);
    localparam integer ROW_BYTES   = WIDTH * CHANNELS;
    localparam integer MEM_DEPTH   = DEPTH * ROW_BYTES;
    localparam integer ADDR_W      = (MEM_DEPTH <= 2) ? 1 : $clog2(MEM_DEPTH);

    // Narrow word width improves aspect-ratio packing for the M10Ks. In
    // particular, B6->B7 no longer asks Quartus for a 1024-bit-wide RAM word.
    // ASIC V1.03: memory payload is accessed only through a 1R1W SRAM boundary.
    // It remains a full-depth behavioral model until mapped to physical SRAM.
    wire [DATA_WIDTH-1:0] row_mem_rd_data;

    reg [DEPTH-1:0] row_valid;

    // Producer-side row assembly state (only metadata; payload goes directly
    // into row_mem on every accepted scalar).
    reg [SLOT_W-1:0] wr_slot;
    reg [COL_W-1:0]  wr_col;
    reg              wr_active;

    // Read issue pointer advances when a scalar is issued from synchronous
    // RAM, not when it is consumed. At most one byte can be outstanding, so
    // this pointer can be only one accepted output ahead of the consumer.
    reg [SLOT_W-1:0] issue_slot;
    reg [COL_W-1:0]  issue_col;
    reg [CH_W-1:0]   issue_ch;
    reg [7:0]        issue_row_abs;

    wire [DATA_WIDTH-1:0] rd_byte;
    reg                  rd_byte_valid;
    reg [SLOT_W-1:0]     rd_out_slot;
    reg [COL_W-1:0]      rd_out_col;
    reg [CH_W-1:0]       rd_out_ch;
    reg [7:0]            rd_out_row_abs;

    integer s;
    integer valid_rows_int;

    wire wr_fire = wr_valid && wr_ready && (wr_ch_idx < CHANNELS);
    wire rd_fire = rd_byte_valid && rd_ready;
    wire rd_issue = rst_n && (!rd_byte_valid || rd_fire) && row_valid[issue_slot];

    // Address generation uses parameter-constant multiplies. Quartus can fold
    // the channel scale and row size into shift/add logic; no DSP is required.
    function [ADDR_W-1:0] flatten_addr;
        input [SLOT_W-1:0] slot;
        input [COL_W-1:0] col;
        input [CH_W-1:0] ch;
        reg [ADDR_W-1:0] slot_ext;
        reg [ADDR_W-1:0] col_ext;
        reg [ADDR_W-1:0] ch_ext;
        reg [ADDR_W-1:0] slot_base;
        reg [ADDR_W-1:0] col_base;
        begin
            slot_ext = slot;
            col_ext  = col;
            ch_ext   = ch;
            slot_base = slot_ext * ROW_BYTES;
            case (CHANNELS)
                24:     col_base = (col_ext << 4) + (col_ext << 3);
                32:     col_base = (col_ext << 5);
                48:     col_base = (col_ext << 5) + (col_ext << 4);
                64:     col_base = (col_ext << 6);
                128:    col_base = (col_ext << 7);
                256:    col_base = (col_ext << 8);
                default: col_base = col_ext * CHANNELS;
            endcase
            flatten_addr = slot_base + col_base + ch_ext;
        end
    endfunction

    wire [ADDR_W-1:0] wr_mem_addr = flatten_addr(
        wr_slot, wr_col, wr_ch_idx[CH_W-1:0]
    );
    wire [ADDR_W-1:0] rd_mem_addr = flatten_addr(
        issue_slot, issue_col, issue_ch
    );

    assign wr_ready = rst_n && (wr_active || !row_valid[wr_slot]);
    assign rd_valid = rd_byte_valid;
    assign rd_pixel = rd_byte;
    assign rd_ch_idx = rd_out_ch;
    assign rd_row_idx = rd_out_row_abs;

    always @(*) begin
        valid_rows_int = 0;
        for (s = 0; s < DEPTH; s = s + 1)
            valid_rows_int = valid_rows_int + row_valid[s];
    end
    assign completed_rows = valid_rows_int[7:0];
    assign empty = (valid_rows_int == 0);
    assign full  = (valid_rows_int >= DEPTH) && !wr_active;

    // RAM is not reset. A synchronous read is issued only when downstream
    // can accept/refill rd_byte. External interface and FIFO state unchanged.
    asic_sram_1r1w #(
        .DATA_WIDTH(DATA_WIDTH), .DEPTH(MEM_DEPTH), .ADDR_WIDTH(ADDR_W)
    ) u_payload_sram (
        .clk_i(clk),
        .wr_en_i(wr_fire), .wr_addr_i(wr_mem_addr), .wr_data_i(wr_pixel),
        .rd_en_i(rd_issue), .rd_addr_i(rd_mem_addr), .rd_data_o(row_mem_rd_data)
    );
    assign rd_byte = row_mem_rd_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_valid      <= {DEPTH{1'b0}};
            wr_slot        <= {SLOT_W{1'b0}};
            wr_col         <= {COL_W{1'b0}};
            wr_active      <= 1'b0;

            issue_slot     <= {SLOT_W{1'b0}};
            issue_col      <= {COL_W{1'b0}};
            issue_ch       <= {CH_W{1'b0}};
            issue_row_abs  <= 8'd0;
            rd_byte_valid  <= 1'b0;
            rd_out_slot    <= {SLOT_W{1'b0}};
            rd_out_col     <= {COL_W{1'b0}};
            rd_out_ch      <= {CH_W{1'b0}};
            rd_out_row_abs <= 8'd0;
        end else begin
            // ---------------------------------------------------------------
            // PRODUCER: one RAM write for every accepted HWC scalar.
            // ---------------------------------------------------------------
            if (wr_fire) begin
                if (!wr_active)
                    wr_active <= 1'b1;

                if (wr_ch_idx == CHANNELS-1) begin
                    if (wr_col == WIDTH-1) begin
                        row_valid[wr_slot] <= 1'b1;
                        wr_slot <= (wr_slot == DEPTH-1) ? {SLOT_W{1'b0}} : wr_slot + 1'b1;
                        wr_col <= {COL_W{1'b0}};
                        wr_active <= 1'b0;
                    end else begin
                        wr_col <= wr_col + 1'b1;
                    end
                end
            end

            // ---------------------------------------------------------------
            // CONSUMER: issue next byte when output slot is free or current
            // byte is accepted. Capture payload metadata with the RAM read.
            // ---------------------------------------------------------------
            if (rd_issue) begin
                rd_byte_valid  <= 1'b1;
                rd_out_slot    <= issue_slot;
                rd_out_col     <= issue_col;
                rd_out_ch      <= issue_ch;
                rd_out_row_abs <= issue_row_abs;

                if (issue_ch == CHANNELS-1) begin
                    issue_ch <= {CH_W{1'b0}};
                    if (issue_col == WIDTH-1) begin
                        issue_col <= {COL_W{1'b0}};
                        issue_slot <= (issue_slot == DEPTH-1) ? {SLOT_W{1'b0}} : issue_slot + 1'b1;
                        issue_row_abs <= issue_row_abs + 1'b1;
                    end else begin
                        issue_col <= issue_col + 1'b1;
                    end
                end else begin
                    issue_ch <= issue_ch + 1'b1;
                end
            end else if (rd_fire) begin
                rd_byte_valid <= 1'b0;
            end

            // A slot remains allocated until the last scalar of its row has
            // actually handshaken out, not merely until that scalar is read.
            if (rd_fire && (rd_out_ch == CHANNELS-1) &&
                (rd_out_col == WIDTH-1)) begin
                row_valid[rd_out_slot] <= 1'b0;
            end
        end
    end

    initial begin
        $display("[FILECHECK] ROW_FIFO_BUILD=20261013_SCALAR_BYTE_RAM_V1");
        if (DEPTH < 2) begin
            $display("[ROW-FIFO][ERROR] DEPTH must be >= 2");
            $finish;
        end
        if (WIDTH < 1 || CHANNELS < 1 || DATA_WIDTH < 1) begin
            $display("[ROW-FIFO][ERROR] WIDTH, CHANNELS and DATA_WIDTH must be >= 1");
            $finish;
        end
    end
endmodule

`default_nettype wire