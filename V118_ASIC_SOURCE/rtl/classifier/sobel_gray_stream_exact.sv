`timescale 1ns/1ps


// Bit-exact streaming Sobel for the user's Python preprocessing.
// Python reference (zero padding by one pixel on every edge):
//   Gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22
//   Gy =  p00 + 2*p01 + p02 - p20 - 2*p21 - p22
//   edge = min(abs(Gx) + abs(Gy), 255)
//
// Emits all H_RES*V_RES values, including borders. Border taps outside the
// frame are synthesized as zero by adding one virtual right-padding token after
// each row and a virtual bottom-padding row after the final source row.
// The RTL requires row-major input addresses 0..H_RES*V_RES-1.
//
// Pipeline:
//   sync line RAM + window/tap register -> side sums -> abs gradients -> clamp
// Each pipeline stage uses ready/valid elastic flow control. The output payload
// remains stable while out_valid_o && !out_ready_i. Only two line memories are
// stored; a full Sobel frame is never buffered.
module sobel_gray_stream_exact #(
    parameter integer H_RES = 96,
    parameter integer V_RES = 96,
    parameter integer ADDR_W = 17
)(
    input  logic              clk_i,
    input  logic              rst_i,
    input  logic              frame_start_i,

    input  logic              in_valid_i,
    output logic              in_ready_o,
    input  logic [ADDR_W-1:0] in_addr_i,
    input  logic [7:0]        gray_i,

    output logic              out_valid_o,
    input  logic              out_ready_i,
    output logic [ADDR_W-1:0] out_addr_o,
    output logic [7:0]        edge_o,
    output logic [8:0]        center_x_o,
    output logic [7:0]        center_y_o
);
    localparam integer FRAME_PIXELS = H_RES * V_RES;
    localparam integer COORD_W = (H_RES > V_RES ? $clog2(H_RES+1) : $clog2(V_RES+1));

    localparam logic [1:0]
        M_INPUT      = 2'd0,
        M_PAD_RIGHT  = 2'd1,
        M_PAD_BOTTOM = 2'd2,
        M_DONE       = 2'd3;

    logic [1:0] mode_q;
    logic [COORD_W-1:0] input_row_q, input_col_q;
    logic [COORD_W-1:0] last_input_row_q;
    logic [ADDR_W-1:0]  last_input_addr_q;
    logic               pad_after_frame_q;
    logic [COORD_W-1:0] bottom_col_q;

    // Stage-A token aligns metadata with synchronous reads of both line RAMs.
    logic               pipe_valid_q;
    logic [7:0]         pixel_pipe_q;
    logic [ADDR_W-1:0]  addr_pipe_q;
    logic [COORD_W-1:0] col_pipe_q, row_pipe_q;
    logic               right_pad_pipe_q;

    // V7: isolate synchronous RAM read and write ports into separate clocked
    // processes. This is intended to let Quartus infer Cyclone V MLABs instead
    // of implementing these 2 x H_RES x 8 bits as ordinary flip-flops.
    // The one-input-late write protocol is preserved to avoid same-address
    // read/write collisions for the required row-major stream.
    (* ramstyle = "MLAB" *) logic [7:0] line_a [0:H_RES-1];
    (* ramstyle = "MLAB" *) logic [7:0] line_b [0:H_RES-1];
    logic [7:0] ram_a_q, ram_b_q;

    logic               wr_pending_q;
    logic               wr_to_line_a_q;
    logic [COORD_W-1:0] wr_col_q;
    logic [7:0]         wr_data_q;


    // Three rows of horizontal history; d2 is column c-2, d1 is c-1, current c.
    logic [7:0] top_d2_q, top_d1_q;
    logic [7:0] mid_d2_q, mid_d1_q;
    logic [7:0] bot_d2_q, bot_d1_q;

    // Elastic ready chain. Stage B may consume a window when Stage 1 can accept;
    // Stage A may advance when its current token is consumed or its register empty.
    wire out_slot_available = (~out_valid_o) | out_ready_i;
    logic s2_valid_q, s1_valid_q;
    wire s2_ready = (~s2_valid_q) | out_slot_available;
    wire s1_ready = (~s1_valid_q) | s2_ready;
    wire stage_a_slot_available = (~pipe_valid_q) | s1_ready;

    wire input_fire = in_valid_i && in_ready_o;
    wire pad_right_fire = (mode_q == M_PAD_RIGHT) && stage_a_slot_available;
    wire pad_bottom_fire = (mode_q == M_PAD_BOTTOM) && stage_a_slot_available;
    wire stage_a_token_fire = input_fire || pad_right_fire || pad_bottom_fire;

    // Input pixel: read at input_col_q. Bottom-padding token: read at
    // bottom_col_q. Virtual right/bottom padding tokens do not read RAM.
    wire line_read_fire = !rst_i && !frame_start_i && stage_a_slot_available &&
        (input_fire || (pad_bottom_fire && (bottom_col_q < H_RES)));
    wire [COORD_W-1:0] line_read_addr = input_fire ? input_col_q : bottom_col_q;
    wire stage_b_fire = pipe_valid_q && s1_ready;
    wire stage_b_has_output = stage_b_fire && (row_pipe_q >= 1) && (col_pipe_q >= 1);
    wire s1_to_s2_fire = s1_valid_q && s2_ready;

    assign in_ready_o = (mode_q == M_INPUT) && stage_a_slot_available;

    // Row r reads row r-2 from the same parity bank and row r-1 from the other.
    // The top padding row (for output row 0) and all right-padding samples are 0.
    wire [7:0] top_current =
        (right_pad_pipe_q || (row_pipe_q == {{(COORD_W-1){1'b0}},1'b1}))
            ? 8'd0
            : (row_pipe_q[0] ? ram_b_q : ram_a_q);
    wire [7:0] mid_current =
        right_pad_pipe_q ? 8'd0 : (row_pipe_q[0] ? ram_a_q : ram_b_q);
    wire [7:0] bot_current = right_pad_pipe_q ? 8'd0 : pixel_pipe_q;

    // Stage 1 combinational side sums, then registered.
    // V7 width proof: each weighted side sum is at most 255 + 2*255 + 255 = 1020,
    // so unsigned 10-bit values are exact (no saturation or rounding here).
    wire [9:0] gx_left_comb =
        {2'b00, top_d2_q} + ({2'b00, mid_d2_q} << 1) + {2'b00, bot_d2_q};
    wire [9:0] gx_right_comb =
        {2'b00, top_current} + ({2'b00, mid_current} << 1) + {2'b00, bot_current};
    wire [9:0] gy_top_comb =
        {2'b00, top_d2_q} + ({2'b00, top_d1_q} << 1) + {2'b00, top_current};
    wire [9:0] gy_bottom_comb =
        {2'b00, bot_d2_q} + ({2'b00, bot_d1_q} << 1) + {2'b00, bot_current};

    logic [9:0] s1_gx_left_q, s1_gx_right_q;
    logic [9:0] s1_gy_top_q, s1_gy_bottom_q;
    logic [ADDR_W-1:0] s1_addr_q;
    logic [8:0] s1_x_q;
    logic [7:0] s1_y_q;

    // Stage 2 subtracts side sums and takes absolute values.
    // Difference range is -1020..+1020: signed 11-bit is sufficient.
    wire signed [10:0] s1_gx_signed =
        $signed({1'b0, s1_gx_right_q}) - $signed({1'b0, s1_gx_left_q});
    // This is -Python Gy; abs(-Gy) == abs(Gy), so the magnitude is identical.
    wire signed [10:0] s1_gy_signed =
        $signed({1'b0, s1_gy_bottom_q}) - $signed({1'b0, s1_gy_top_q});
    // |gradient| <= 1020, so unsigned 10-bit magnitudes are exact.
    wire [9:0] s1_gx_abs = s1_gx_signed[10] ? (~s1_gx_signed[9:0] + 10'd1) : s1_gx_signed[9:0];
    wire [9:0] s1_gy_abs = s1_gy_signed[10] ? (~s1_gy_signed[9:0] + 10'd1) : s1_gy_signed[9:0];

    logic [9:0] s2_gx_abs_q, s2_gy_abs_q;
    logic [ADDR_W-1:0] s2_addr_q;
    logic [8:0] s2_x_q;
    logic [7:0] s2_y_q;

    // Stage 3 sum and unsigned saturation to U8.
    // Maximum L1 magnitude is 1020 + 1020 = 2040, fitting 11 unsigned bits.
    wire [10:0] s2_magnitude_sum = {1'b0, s2_gx_abs_q} + {1'b0, s2_gy_abs_q};
    wire [7:0] s2_edge_sat = (s2_magnitude_sum > 11'd255) ? 8'hff : s2_magnitude_sum[7:0];

    // One-cycle write metadata pipeline. Synthetic padding is never written.
    always_ff @(posedge clk_i) begin
        if (rst_i || frame_start_i) begin
            wr_pending_q   <= 1'b0;
            wr_to_line_a_q <= 1'b0;
            wr_col_q       <= '0;
            wr_data_q      <= 8'd0;
        end else begin
            wr_pending_q <= input_fire;
            if (input_fire) begin
                wr_to_line_a_q <= ~input_row_q[0];
                wr_col_q       <= input_col_q;
                wr_data_q      <= gray_i;
            end
        end
    end

    // Dedicated synchronous RAM write port. The arrays are written only here.
    always_ff @(posedge clk_i) begin
        if (!rst_i && !frame_start_i && wr_pending_q) begin
            if (wr_to_line_a_q)
                line_a[wr_col_q] <= wr_data_q;
            else
                line_b[wr_col_q] <= wr_data_q;
        end
    end

    // Dedicated registered synchronous read port. The read-data registers are
    // not reset: invalid pipeline tokens are flushed by reset/frame_start, and
    // their contents are not consumed until a valid token has been accepted.
    // Keeping reset logic off the RAM output helps preserve memory inference.
    always_ff @(posedge clk_i) begin
        if (line_read_fire) begin
            ram_a_q <= line_a[line_read_addr];
            ram_b_q <= line_b[line_read_addr];
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || frame_start_i) begin
            mode_q            <= M_INPUT;
            input_row_q       <= '0;
            input_col_q       <= '0;
            last_input_row_q  <= '0;
            last_input_addr_q <= '0;
            pad_after_frame_q <= 1'b0;
            bottom_col_q      <= '0;

            pipe_valid_q      <= 1'b0;
            pixel_pipe_q      <= 8'd0;
            addr_pipe_q       <= '0;
            col_pipe_q        <= '0;
            row_pipe_q        <= '0;
            right_pad_pipe_q  <= 1'b0;

            top_d2_q <= 8'd0; top_d1_q <= 8'd0;
            mid_d2_q <= 8'd0; mid_d1_q <= 8'd0;
            bot_d2_q <= 8'd0; bot_d1_q <= 8'd0;

            s1_valid_q    <= 1'b0;
            s1_gx_left_q  <= 10'd0;
            s1_gx_right_q <= 10'd0;
            s1_gy_top_q   <= 10'd0;
            s1_gy_bottom_q<= 10'd0;
            s1_addr_q     <= '0;
            s1_x_q        <= '0;
            s1_y_q        <= '0;

            s2_valid_q    <= 1'b0;
            s2_gx_abs_q   <= 10'd0;
            s2_gy_abs_q   <= 10'd0;
            s2_addr_q     <= '0;
            s2_x_q        <= '0;
            s2_y_q        <= '0;

            out_valid_o <= 1'b0;
            out_addr_o  <= '0;
            edge_o      <= 8'd0;
            center_x_o  <= '0;
            center_y_o  <= '0;
        end else begin
            // Stage 3: output register. Replaces a consumed output on the same
            // edge, so a ready downstream can accept one Sobel value per cycle.
            if (out_slot_available) begin
                out_valid_o <= s2_valid_q;
                if (s2_valid_q) begin
                    out_addr_o <= s2_addr_q;
                    edge_o     <= s2_edge_sat;
                    center_x_o <= s2_x_q;
                    center_y_o <= s2_y_q;
                end
            end

            // Stage 2: abs gradients plus aligned output metadata.
            if (s2_ready) begin
                s2_valid_q <= s1_valid_q;
                if (s1_valid_q) begin
                    s2_gx_abs_q <= s1_gx_abs;
                    s2_gy_abs_q <= s1_gy_abs;
                    s2_addr_q   <= s1_addr_q;
                    s2_x_q      <= s1_x_q;
                    s2_y_q      <= s1_y_q;
                end
            end

            // Stage 1: weighted side sums for the pending window token.
            if (s1_ready) begin
                s1_valid_q <= stage_b_has_output;
                if (stage_b_has_output) begin
                    s1_gx_left_q  <= gx_left_comb;
                    s1_gx_right_q <= gx_right_comb;
                    s1_gy_top_q   <= gy_top_comb;
                    s1_gy_bottom_q<= gy_bottom_comb;
                    s1_addr_q     <= addr_pipe_q - (H_RES + 1);
                    s1_x_q        <= col_pipe_q - 1'b1;
                    s1_y_q        <= row_pipe_q - 1'b1;
                end
            end

            // Stage A: line-RAM read and row/column metadata registration.
            if (stage_a_slot_available) begin
                pipe_valid_q <= stage_a_token_fire;
                if (stage_a_token_fire) begin
                    if (input_fire) begin
                        pixel_pipe_q     <= gray_i;
                        addr_pipe_q      <= in_addr_i;
                        col_pipe_q       <= input_col_q;
                        row_pipe_q       <= input_row_q;
                        right_pad_pipe_q <= 1'b0;

                        if (input_col_q == H_RES-1) begin
                            last_input_row_q  <= input_row_q;
                            last_input_addr_q <= in_addr_i;
                            pad_after_frame_q <= (input_row_q == V_RES-1);
                            input_col_q <= '0;
                            if (input_row_q != V_RES-1)
                                input_row_q <= input_row_q + 1'b1;
                            mode_q <= M_PAD_RIGHT;
                        end else begin
                            input_col_q <= input_col_q + 1'b1;
                        end
                    end else if (pad_right_fire) begin
                        // Virtual right-edge zero at column H_RES. The output
                        // address maps this token to column H_RES-1 of row r-1.
                        pixel_pipe_q     <= 8'd0;
                        addr_pipe_q      <= last_input_addr_q + 1'b1;
                        col_pipe_q       <= H_RES;
                        row_pipe_q       <= last_input_row_q;
                        right_pad_pipe_q <= 1'b1;

                        if (pad_after_frame_q) begin
                            bottom_col_q <= '0;
                            mode_q <= M_PAD_BOTTOM;
                        end else begin
                            mode_q <= M_INPUT;
                        end
                    end else if (pad_bottom_fire) begin
                        // Virtual bottom row r=V_RES. Top/middle come from the
                        // last two real rows; pixel_pipe is the zero bottom row.
                        pixel_pipe_q     <= 8'd0;
                        addr_pipe_q      <= FRAME_PIXELS + bottom_col_q;
                        col_pipe_q       <= bottom_col_q;
                        row_pipe_q       <= V_RES;
                        right_pad_pipe_q <= (bottom_col_q == H_RES);

                        if (bottom_col_q == H_RES) begin
                            mode_q <= M_DONE;
                        end else begin
                            bottom_col_q <= bottom_col_q + 1'b1;
                        end
                    end
                end
            end

            // Shift horizontal taps only when the current window token is
            // consumed into Stage 1. Gaps/backpressure do not disturb the window.
            if (stage_b_fire) begin
                if (col_pipe_q == 0) begin
                    top_d2_q <= 8'd0; top_d1_q <= top_current;
                    mid_d2_q <= 8'd0; mid_d1_q <= mid_current;
                    bot_d2_q <= 8'd0; bot_d1_q <= bot_current;
                end else begin
                    top_d2_q <= top_d1_q; top_d1_q <= top_current;
                    mid_d2_q <= mid_d1_q; mid_d1_q <= mid_current;
                    bot_d2_q <= bot_d1_q; bot_d1_q <= bot_current;
                end
            end
        end
    end
endmodule

`default_nettype wire