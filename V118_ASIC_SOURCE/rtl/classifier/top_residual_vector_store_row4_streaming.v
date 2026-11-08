`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Quartus RAM-inference revision of the streaming residual vector store.
//
// Key changes versus the original:
//   * Flatten DEPTH x WIDTH memory into one 1-D array.
//   * One complete packed-vector write per committed pixel.
//   * Synchronous RAM read with one prefetched current vector.
//   * RAM contents are not reset; row_valid/row_tag gate visibility.
//   * rd_data / empty / rd_en interface is preserved. `empty` stays asserted
//     until the first word has been synchronously fetched, and after consuming
//     the final pixel of a row the next row is prefetched when already ready.
//
// IMPORTANT: this changes the row-available timing by a fetch cycle compared
// with the asynchronous-read implementation. Re-run the RTL regression after
// replacing the original module.
// ============================================================================

module top_residual_vector_store_row4_streaming #(
    parameter integer WIDTH      = 96,
    parameter integer HEIGHT     = 96,
    parameter integer IN_CH      = 24,
    parameter integer DEPTH      = 3,
    parameter integer DATA_WIDTH = 8
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          wr_valid,
    input  wire [7:0]                    wr_pixel,
    input  wire [7:0]                    wr_ch_idx,
    output wire                          wr_ready,

    output wire [IN_CH*DATA_WIDTH-1:0]   rd_data,
    output wire                          empty,
    input  wire                          rd_en
);

    localparam integer PIXEL_BITS = IN_CH * DATA_WIDTH;
    localparam integer COL_W      = (WIDTH <= 2) ? 1 : $clog2(WIDTH);
    localparam integer SLOT_W     = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam integer MEM_DEPTH  = DEPTH * WIDTH;
    localparam integer ADDR_W     = (MEM_DEPTH <= 2) ? 1 : $clog2(MEM_DEPTH);
    // Width-limited constant prevents 32-bit integer arithmetic in RAM addresses.
    localparam [ADDR_W-1:0] WIDTH_ADDR = WIDTH[ADDR_W-1:0];

    // Flattened RAM address: slot * WIDTH + column.
    (* ramstyle = "M10K" *)
    reg [PIXEL_BITS-1:0] mem [0:MEM_DEPTH-1];

    // A slot is readable only after a full row has been committed.
    reg [DEPTH-1:0] row_valid;
    reg [7:0]       row_tag [0:DEPTH-1];

    // Writer state.
    reg [7:0]        wr_row;
    reg [SLOT_W-1:0] wr_slot;
    reg [COL_W-1:0]  wr_col;
    reg              wr_active;
    reg [PIXEL_BITS-1:0] wr_vec;

    // Reader state. rd_data_reg is the prefetched vector at (rd_slot,rd_col).
    reg [7:0]        rd_row;
    reg [SLOT_W-1:0] rd_slot;
    reg [COL_W-1:0]  rd_col;
    reg [PIXEL_BITS-1:0] rd_data_reg;
    reg              rd_data_valid;

    wire wr_fire = wr_valid && wr_ready;
    wire rd_fire = rd_en && !empty;

    wire [ADDR_W-1:0] wr_mem_addr = (wr_slot * WIDTH_ADDR) + wr_col;
    wire [SLOT_W-1:0] rd_next_slot = (rd_slot == DEPTH-1)
                                   ? {SLOT_W{1'b0}} : rd_slot + 1'b1;

    wire current_row_ready = row_valid[rd_slot] &&
                             (row_tag[rd_slot] == rd_row);
    wire next_row_ready = (rd_row < HEIGHT-1) &&
                          row_valid[rd_next_slot] &&
                          (row_tag[rd_next_slot] == (rd_row + 1'b1));

    // Assemble sequential HWC channels with a fixed shift, not a variable
    // indexed part-select. The stream order is ch=0,1,...,IN_CH-1. After the
    // final channel, channel 0 occupies the least-significant byte/field and
    // channel IN_CH-1 occupies the most-significant field, matching the legacy
    // wr_vec[wr_ch_idx*DATA_WIDTH +: DATA_WIDTH] representation.
    function [PIXEL_BITS-1:0] shift_insert_channel;
        input [PIXEL_BITS-1:0] current_vec;
        input [DATA_WIDTH-1:0] pixel_value;
        begin
            shift_insert_channel = current_vec >> DATA_WIDTH;
            shift_insert_channel[PIXEL_BITS-1 -: DATA_WIDTH] = pixel_value;
        end
    endfunction

    // On the final channel, include the current pixel and shift the previously
    // accumulated channels into their final positions for the synchronous RAM
    // write. When a vector starts, stale bits are discarded.
    reg [PIXEL_BITS-1:0] wr_mem_data;
    always @(*) begin
        wr_mem_data = wr_vec;
        if (wr_ch_idx == IN_CH-1) begin
            if (!wr_active)
                wr_mem_data = {wr_pixel[DATA_WIDTH-1:0], {(PIXEL_BITS-DATA_WIDTH){1'b0}}};
            else
                wr_mem_data = shift_insert_channel(wr_vec, wr_pixel[DATA_WIDTH-1:0]);
        end
    end

    wire wr_mem_we = rst_n && wr_fire && (wr_ch_idx < IN_CH) &&
                     (wr_ch_idx == IN_CH-1);

    // Read-ahead address control. The RAM read itself is synchronous.
    reg                  rd_mem_re;
    reg [ADDR_W-1:0]     rd_mem_addr;
    always @(*) begin
        rd_mem_re   = 1'b0;
        rd_mem_addr = (rd_slot * WIDTH_ADDR) + rd_col;

        if (!rd_data_valid) begin
            // First vector in a row, or a newly committed next row.
            if (current_row_ready) begin
                rd_mem_re   = 1'b1;
                rd_mem_addr = (rd_slot * WIDTH_ADDR) + rd_col;
            end
        end else if (rd_fire) begin
            if (rd_col != WIDTH-1) begin
                // Pre-fetch the next pixel in the current row.
                rd_mem_re   = 1'b1;
                rd_mem_addr = (rd_slot * WIDTH_ADDR) + (rd_col + 1'b1);
            end else if (next_row_ready) begin
                // Last pixel consumed: pre-fetch column zero of the next row.
                rd_mem_re   = 1'b1;
                rd_mem_addr = (rd_next_slot * WIDTH_ADDR);
            end
        end
    end

    // Dedicated synchronous memory access process: no asynchronous reset and
    // no reset loop over RAM contents, allowing Quartus to infer an M10K.
    always @(posedge clk) begin
        if (wr_mem_we)
            mem[wr_mem_addr] <= wr_mem_data;
        if (rst_n && rd_mem_re)
            rd_data_reg <= mem[rd_mem_addr];
    end

    // Preserve the external "current unread vector" convention. empty remains
    // asserted until the requested word has arrived from synchronous RAM.
    assign empty = !(current_row_ready && rd_data_valid);
    assign rd_data = !empty ? rd_data_reg : {PIXEL_BITS{1'b0}};
    assign wr_ready = rst_n && (wr_active || !row_valid[wr_slot]);

    initial begin
        $display("[FILECHECK] RESIDUAL_VECTOR_ROW4_BUILD=20261019_V12_M10K_MEMFIX");
        if (DEPTH < 2) begin
            $display("[RES-ROW4][ERROR] DEPTH must be >= 2");
            $finish;
        end
        if (WIDTH < 1 || HEIGHT < 1 || IN_CH < 1 || IN_CH > 256 || DATA_WIDTH < 1) begin
            $display("[RES-ROW4][ERROR] Invalid WIDTH/HEIGHT/IN_CH/DATA_WIDTH parameter");
            $finish;
        end
    end

    // Control state only. Do not reset the RAM itself.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_valid     <= {DEPTH{1'b0}};

            wr_row        <= 8'd0;
            wr_slot       <= {SLOT_W{1'b0}};
            wr_col        <= {COL_W{1'b0}};
            wr_active     <= 1'b0;
            wr_vec        <= {PIXEL_BITS{1'b0}};

            rd_row        <= 8'd0;
            rd_slot       <= {SLOT_W{1'b0}};
            rd_col        <= {COL_W{1'b0}};
            rd_data_valid <= 1'b0;
        end else begin
            // ---------------------------------------------------------------
            // Writer: HWC scalar stream, commit one vector on final channel.
            // ---------------------------------------------------------------
            if (wr_fire && (wr_ch_idx < IN_CH)) begin
                if (!wr_active) begin
                    wr_active <= 1'b1;
                    wr_col    <= {COL_W{1'b0}};
                    // First HWC channel seeds the high field; later channels
                    // shift it down until channel 0 lands in the low field.
                    wr_vec <= {wr_pixel[DATA_WIDTH-1:0], {(PIXEL_BITS-DATA_WIDTH){1'b0}}};
                end else begin
                    wr_vec <= shift_insert_channel(wr_vec, wr_pixel[DATA_WIDTH-1:0]);
                end

                if (wr_ch_idx == IN_CH-1) begin
                    if (wr_col == WIDTH-1) begin
                        row_valid[wr_slot] <= 1'b1;
                        row_tag[wr_slot]   <= wr_row;

                        if (wr_row < HEIGHT-1) begin
                            wr_row  <= wr_row + 1'b1;
                            wr_slot <= (wr_slot == DEPTH-1)
                                     ? {SLOT_W{1'b0}} : wr_slot + 1'b1;
                        end

                        wr_col    <= {COL_W{1'b0}};
                        wr_active <= 1'b0;
                    end else begin
                        wr_col <= wr_col + 1'b1;
                    end
                end
            end

            // ---------------------------------------------------------------
            // Reader: rd_en consumes the currently prefetched whole vector.
            // ---------------------------------------------------------------
            if (!rd_data_valid) begin
                if (current_row_ready)
                    rd_data_valid <= 1'b1;
            end else if (rd_fire) begin
                if (rd_col == WIDTH-1) begin
                    row_valid[rd_slot] <= 1'b0;
                    rd_col <= {COL_W{1'b0}};

                    if (rd_row < HEIGHT-1) begin
                        rd_row  <= rd_row + 1'b1;
                        rd_slot <= rd_next_slot;
                        rd_data_valid <= next_row_ready;
                    end else begin
                        // Final image row consumed.
                        rd_data_valid <= 1'b0;
                    end
                end else begin
                    rd_col <= rd_col + 1'b1;
                    // rd_data_valid remains asserted: the next word is fetched
                    // on this same edge by the synchronous RAM process.
                end
            end
        end
    end

endmodule

`default_nettype wire