module handseg_async_pixel_fifo #(
    parameter integer WIDTH = 24,
    parameter integer ADDR_BITS = 10
)(
    input  logic             wr_clk_i,
    input  logic             wr_rstn_i,
    input  logic             wr_valid_i,
    input  logic [WIDTH-1:0] wr_data_i,
    output logic             wr_ready_o,
    output logic             wr_overflow_o,

    input  logic             rd_clk_i,
    input  logic             rd_rstn_i,
    output logic             rd_valid_o,
    input  logic             rd_ready_i,
    output logic [WIDTH-1:0] rd_data_o
);

    localparam integer DEPTH = (1 << ADDR_BITS);
    localparam integer PTR_W = ADDR_BITS + 1;

    (* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_W-1:0] wr_bin_r, wr_gray_r;
    logic [PTR_W-1:0] rd_bin_r, rd_gray_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic [PTR_W-1:0] rd_gray_wr1_r, rd_gray_wr2_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic [PTR_W-1:0] wr_gray_rd1_r, wr_gray_rd2_r;

    logic [PTR_W-1:0] wr_bin_next_c, wr_gray_next_c;
    logic [PTR_W-1:0] wr_bin_plus1_c, wr_gray_plus1_c;
    logic [PTR_W-1:0] rd_bin_next_c, rd_gray_next_c;
    logic full_c, empty_c;

    function automatic [PTR_W-1:0] bin2gray(input [PTR_W-1:0] b);
        bin2gray = (b >> 1) ^ b;
    endfunction

    assign wr_bin_plus1_c  = wr_bin_r + 1'b1;
    assign wr_gray_plus1_c = bin2gray(wr_bin_plus1_c);

    // Standard async-FIFO full test. This is deliberately based on the
    // unconditional +1 pointer, avoiding a combinational loop through READY.
    assign full_c = (wr_gray_plus1_c == {~rd_gray_wr2_r[PTR_W-1:PTR_W-2], rd_gray_wr2_r[PTR_W-3:0]});
    assign wr_ready_o = !full_c;

    assign wr_bin_next_c  = wr_bin_r + ((wr_valid_i && wr_ready_o) ? 1'b1 : 1'b0);
    assign wr_gray_next_c = bin2gray(wr_bin_next_c);

    assign empty_c = (rd_gray_r == wr_gray_rd2_r);

    logic rd_valid_r;
    logic [WIDTH-1:0] rd_data_r;
    logic rd_prefetch_c;

    assign rd_valid_o = rd_valid_r;
    assign rd_data_o  = rd_data_r;

    // rd_bin_r is the next RAM location to prefetch. Once a word has been
    // copied into rd_data_r, that RAM slot can safely be released to the write
    // clock domain even if the consumer has not yet accepted rd_data_r.
    assign rd_prefetch_c = (!rd_valid_r || rd_ready_i) && !empty_c;
    assign rd_bin_next_c  = rd_bin_r + (rd_prefetch_c ? 1'b1 : 1'b0);
    assign rd_gray_next_c = bin2gray(rd_bin_next_c);

    always_ff @(posedge wr_clk_i) begin
        if (wr_valid_i && wr_ready_o)
            mem[wr_bin_r[ADDR_BITS-1:0]] <= wr_data_i;
    end

    always_ff @(posedge wr_clk_i or negedge wr_rstn_i) begin
        if (!wr_rstn_i) begin
            wr_bin_r <= '0;
            wr_gray_r <= '0;
            rd_gray_wr1_r <= '0;
            rd_gray_wr2_r <= '0;
            wr_overflow_o <= 1'b0;
        end
        else begin
            rd_gray_wr1_r <= rd_gray_r;
            rd_gray_wr2_r <= rd_gray_wr1_r;
            if (wr_valid_i && wr_ready_o) begin
                wr_bin_r <= wr_bin_next_c;
                wr_gray_r <= wr_gray_next_c;
            end
            if (wr_valid_i && !wr_ready_o)
                wr_overflow_o <= 1'b1;
        end
    end

    always_ff @(posedge rd_clk_i or negedge rd_rstn_i) begin
        if (!rd_rstn_i) begin
            rd_bin_r <= '0;
            rd_gray_r <= '0;
            wr_gray_rd1_r <= '0;
            wr_gray_rd2_r <= '0;
            rd_valid_r <= 1'b0;
            rd_data_r <= '0;
        end
        else begin
            wr_gray_rd1_r <= wr_gray_r;
            wr_gray_rd2_r <= wr_gray_rd1_r;

            if (!rd_valid_r || rd_ready_i) begin
                if (!empty_c) begin
                    rd_data_r <= mem[rd_bin_r[ADDR_BITS-1:0]];
                    rd_valid_r <= 1'b1;
                    rd_bin_r <= rd_bin_next_c;
                    rd_gray_r <= rd_gray_next_c;
                end
                else begin
                    rd_valid_r <= 1'b0;
                end
            end
        end
    end

endmodule
