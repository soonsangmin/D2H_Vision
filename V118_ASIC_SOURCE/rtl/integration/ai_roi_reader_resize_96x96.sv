module ai_roi_reader_resize_96x96 #(
    parameter logic [31:0] SNAPSHOT_BASE = 32'h3200_0000
)(
    input  logic clk_i,
    input  logic rstn_i,

    input  logic       start_i,
    input  logic [9:0] roi_xmin_i,
    input  logic [8:0] roi_ymin_i,
    input  logic [9:0] roi_xmax_i,
    input  logic [8:0] roi_ymax_i,

    // Ordered 64-bit DDR read client.
    output logic        rd_req_valid_o,
    input  logic        rd_req_ready_i,
    output logic [31:0] rd_req_addr_o,
    input  logic        rd_rsp_valid_i,
    output logic        rd_rsp_ready_o,
    input  logic [63:0] rd_rsp_data_i,

    // Pixel write handshake; payload remains stable until accepted.
    input  logic        bram_wr_ready_i,
    // BRAM96 write port.
    output logic        bram_wr_en_o,
    output logic [13:0] bram_wr_addr_o,
    output logic [15:0] bram_wr_data_o,

    output logic busy_o,
    output logic done_o
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_LOOKUP,
        S_WAIT_RSP,
        S_PUSH
    } state_t;

    state_t state_r;

    logic [9:0] xmin_r, xmax_r;
    logic [8:0] ymin_r, ymax_r;

    logic [9:0] src_x_r;
    logic [8:0] src_y_r;
    logic [6:0] dst_x_r;
    logic [6:0] dst_y_r;

    // src_size / 96 = integer step + remainder/96.  The small compare/subtract
    // functions avoid synthesizing a variable divider.
    logic [3:0] x_step_q_r, y_step_q_r;
    logic [6:0] x_step_rem_r, y_step_rem_r;
    logic [7:0] x_err_r, y_err_r;

    logic        cache_valid_r;
    logic [31:0] cache_addr_r;
    logic [63:0] cache_data_r;

    logic [1:0]  pending_lane_r;
    logic [31:0] pending_addr_r;

    logic [10:0] width_c;
    logic [9:0]  height_c;

    assign width_c  = {1'b0, roi_xmax_i} - {1'b0, roi_xmin_i} + 11'd1;
    assign height_c = {1'b0, roi_ymax_i} - {1'b0, roi_ymin_i} + 10'd1;

    function automatic [3:0] div96_q_11(input logic [10:0] n);
        begin
            if      (n >= 11'd576) div96_q_11 = 4'd6;
            else if (n >= 11'd480) div96_q_11 = 4'd5;
            else if (n >= 11'd384) div96_q_11 = 4'd4;
            else if (n >= 11'd288) div96_q_11 = 4'd3;
            else if (n >= 11'd192) div96_q_11 = 4'd2;
            else if (n >= 11'd96)  div96_q_11 = 4'd1;
            else                   div96_q_11 = 4'd0;
        end
    endfunction

    function automatic [6:0] mod96_11(input logic [10:0] n);
        begin
            if      (n >= 11'd576) mod96_11 = n - 11'd576;
            else if (n >= 11'd480) mod96_11 = n - 11'd480;
            else if (n >= 11'd384) mod96_11 = n - 11'd384;
            else if (n >= 11'd288) mod96_11 = n - 11'd288;
            else if (n >= 11'd192) mod96_11 = n - 11'd192;
            else if (n >= 11'd96)  mod96_11 = n - 11'd96;
            else                   mod96_11 = n[6:0];
        end
    endfunction

    function automatic [3:0] div96_q_10(input logic [9:0] n);
        begin
            if      (n >= 10'd480) div96_q_10 = 4'd5;
            else if (n >= 10'd384) div96_q_10 = 4'd4;
            else if (n >= 10'd288) div96_q_10 = 4'd3;
            else if (n >= 10'd192) div96_q_10 = 4'd2;
            else if (n >= 10'd96)  div96_q_10 = 4'd1;
            else                   div96_q_10 = 4'd0;
        end
    endfunction

    function automatic [6:0] mod96_10(input logic [9:0] n);
        begin
            if      (n >= 10'd480) mod96_10 = n - 10'd480;
            else if (n >= 10'd384) mod96_10 = n - 10'd384;
            else if (n >= 10'd288) mod96_10 = n - 10'd288;
            else if (n >= 10'd192) mod96_10 = n - 10'd192;
            else if (n >= 10'd96)  mod96_10 = n - 10'd96;
            else                   mod96_10 = n[6:0];
        end
    endfunction

    function automatic [15:0] select_pixel16(
        input logic [63:0] word,
        input logic [1:0] lane
    );
        begin
            case (lane)
                2'd0: select_pixel16 = word[15:0];
                2'd1: select_pixel16 = word[31:16];
                2'd2: select_pixel16 = word[47:32];
                default: select_pixel16 = word[63:48];
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Address of the current nearest-neighbor source pixel.
    // RGB565 byte offset = y*1280 + x*2
    //                    = (y<<10) + (y<<8) + (x<<1).
    // ------------------------------------------------------------------
    logic [31:0] current_byte_addr_c;
    logic [31:0] current_word_addr_c;
    logic [1:0]  current_lane_c;
    logic        current_cache_hit_c;

    always_comb begin
        current_byte_addr_c = SNAPSHOT_BASE
                            + ({23'd0, src_y_r} << 10)
                            + ({23'd0, src_y_r} << 8)
                            + ({22'd0, src_x_r} << 1);
        current_word_addr_c = {current_byte_addr_c[31:3], 3'b000};
        current_lane_c      = current_byte_addr_c[2:1];
        current_cache_hit_c = cache_valid_r &&
                              (cache_addr_r == current_word_addr_c);
    end

    assign busy_o = (state_r != S_IDLE);

    always_comb begin
        rd_req_valid_o = (state_r == S_LOOKUP) && !current_cache_hit_c;
        rd_req_addr_o  = current_word_addr_c;
        rd_rsp_ready_o = (state_r == S_WAIT_RSP);
    end

    // ------------------------------------------------------------------
    // A pixel becomes available either from the local last-word cache or from
    // a just-returned 64-bit DDR response.
    // ------------------------------------------------------------------
    logic        pixel_complete_c;
    logic [15:0] pixel_value_c;

    always_comb begin
        pixel_complete_c = 1'b0;
        pixel_value_c    = 16'h0000;

        if ((state_r == S_LOOKUP) && current_cache_hit_c) begin
            pixel_complete_c = 1'b1;
            pixel_value_c    = select_pixel16(cache_data_r, current_lane_c);
        end else if ((state_r == S_WAIT_RSP) && rd_rsp_valid_i) begin
            pixel_complete_c = 1'b1;
            pixel_value_c    = select_pixel16(rd_rsp_data_i, pending_lane_r);
        end
    end

    // ------------------------------------------------------------------
    // Next nearest-neighbor coordinates after one destination pixel.
    // ------------------------------------------------------------------
    logic [6:0] next_dst_x_c, next_dst_y_c;
    logic [9:0] next_src_x_c;
    logic [8:0] next_src_y_c;
    logic [7:0] next_x_err_c, next_y_err_c;
    logic [8:0] x_sum_c, y_sum_c;
    logic [10:0] src_x_step_c;
    logic [9:0]  src_y_step_c;

    always_comb begin
        next_dst_x_c = dst_x_r;
        next_dst_y_c = dst_y_r;
        next_src_x_c = src_x_r;
        next_src_y_c = src_y_r;
        next_x_err_c = x_err_r;
        next_y_err_c = y_err_r;

        x_sum_c      = {1'b0, x_err_r} + {2'b00, x_step_rem_r};
        y_sum_c      = {1'b0, y_err_r} + {2'b00, y_step_rem_r};
        src_x_step_c = {1'b0, src_x_r} + x_step_q_r;
        src_y_step_c = {1'b0, src_y_r} + y_step_q_r;

        if (dst_x_r == 7'd95) begin
            next_dst_x_c = 7'd0;
            next_src_x_c = xmin_r;
            next_x_err_c = 8'd0;

            if (dst_y_r != 7'd95) begin
                next_dst_y_c = dst_y_r + 1'b1;

                if (y_sum_c >= 9'd96) begin
                    next_y_err_c = y_sum_c - 9'd96;
                    src_y_step_c = {1'b0, src_y_r} + y_step_q_r + 10'd1;
                end else begin
                    next_y_err_c = y_sum_c[7:0];
                end

                if (src_y_step_c > {1'b0, ymax_r})
                    next_src_y_c = ymax_r;
                else
                    next_src_y_c = src_y_step_c[8:0];
            end
        end else begin
            next_dst_x_c = dst_x_r + 1'b1;

            if (x_sum_c >= 9'd96) begin
                next_x_err_c = x_sum_c - 9'd96;
                src_x_step_c = {1'b0, src_x_r} + x_step_q_r + 11'd1;
            end else begin
                next_x_err_c = x_sum_c[7:0];
            end

            if (src_x_step_c > {1'b0, xmax_r})
                next_src_x_c = xmax_r;
            else
                next_src_x_c = src_x_step_c[9:0];
        end
    end

    logic [13:0] current_bram_addr_c;
    assign current_bram_addr_c =
        ({7'd0, dst_y_r} << 6) + ({7'd0, dst_y_r} << 5) + dst_x_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r          <= S_IDLE;
            xmin_r           <= 10'd0;
            xmax_r           <= 10'd0;
            ymin_r           <= 9'd0;
            ymax_r           <= 9'd0;
            src_x_r          <= 10'd0;
            src_y_r          <= 9'd0;
            dst_x_r          <= 7'd0;
            dst_y_r          <= 7'd0;
            x_step_q_r       <= 4'd0;
            y_step_q_r       <= 4'd0;
            x_step_rem_r     <= 7'd0;
            y_step_rem_r     <= 7'd0;
            x_err_r          <= 8'd0;
            y_err_r          <= 8'd0;
            cache_valid_r    <= 1'b0;
            cache_addr_r     <= 32'd0;
            cache_data_r     <= 64'd0;
            pending_lane_r   <= 2'd0;
            pending_addr_r   <= 32'd0;
            bram_wr_en_o     <= 1'b0;
            bram_wr_addr_o   <= 14'd0;
            bram_wr_data_o   <= 16'd0;
            done_o           <= 1'b0;
        end else begin
            if (!((state_r == S_PUSH) && !bram_wr_ready_i))
                bram_wr_en_o <= 1'b0;
            done_o       <= 1'b0;

            case (state_r)
                S_IDLE: begin
                    if (start_i &&
                        (roi_xmin_i <= roi_xmax_i) &&
                        (roi_ymin_i <= roi_ymax_i)) begin
                        xmin_r       <= roi_xmin_i;
                        xmax_r       <= roi_xmax_i;
                        ymin_r       <= roi_ymin_i;
                        ymax_r       <= roi_ymax_i;
                        src_x_r      <= roi_xmin_i;
                        src_y_r      <= roi_ymin_i;
                        dst_x_r      <= 7'd0;
                        dst_y_r      <= 7'd0;
                        x_step_q_r   <= div96_q_11(width_c);
                        x_step_rem_r <= mod96_11(width_c);
                        y_step_q_r   <= div96_q_10(height_c);
                        y_step_rem_r <= mod96_10(height_c);
                        x_err_r      <= 8'd0;
                        y_err_r      <= 8'd0;
                        cache_valid_r <= 1'b0;
                        state_r      <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    if (!current_cache_hit_c && rd_req_valid_o && rd_req_ready_i) begin
                        pending_addr_r <= current_word_addr_c;
                        pending_lane_r <= current_lane_c;
                        state_r        <= S_WAIT_RSP;
                    end
                end

                S_WAIT_RSP: begin
                    if (rd_rsp_valid_i && rd_rsp_ready_o) begin
                        cache_valid_r <= 1'b1;
                        cache_addr_r  <= pending_addr_r;
                        cache_data_r  <= rd_rsp_data_i;
                        state_r       <= S_LOOKUP;
                    end
                end

                S_PUSH: begin
                    if (bram_wr_en_o && bram_wr_ready_i) begin
                        if ((dst_x_r == 7'd95) && (dst_y_r == 7'd95)) begin
                            done_o <= 1'b1;
                            state_r <= S_IDLE;
                        end else begin
                            dst_x_r <= next_dst_x_c;
                            dst_y_r <= next_dst_y_c;
                            src_x_r <= next_src_x_c;
                            src_y_r <= next_src_y_c;
                            x_err_r <= next_x_err_c;
                            y_err_r <= next_y_err_c;
                            state_r <= S_LOOKUP;
                        end
                    end
                end
                default: state_r <= S_IDLE;
            endcase

            if (pixel_complete_c) begin
                bram_wr_en_o   <= 1'b1;
                bram_wr_addr_o <= current_bram_addr_c;
                bram_wr_data_o <= pixel_value_c;
                state_r <= S_PUSH;
            end
        end
    end
endmodule
