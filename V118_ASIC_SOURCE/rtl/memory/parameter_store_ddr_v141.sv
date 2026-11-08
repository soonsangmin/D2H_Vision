module parameter_store_ddr_v141 #(
    parameter logic [31:0] WEIGHT_BASE = 32'h3480_0000,
    parameter logic [31:0] QPARAM_BASE = 32'h3490_0000,
    parameter logic [31:0] MAGIC_ADDR  = 32'h349F_F000,
    parameter logic [31:0] MAGIC_VALUE = 32'h4853_4731,
    parameter integer POLL_BITS = 20
)(
    input  logic clk_i,
    input  logic rstn_i,

    input  logic        weight_req_valid_i,
    output logic        weight_req_ready_o,
    input  logic [16:0] weight_req_addr_i,
    output logic        weight_rsp_valid_o,
    input  logic        weight_rsp_ready_i,
    output logic [63:0] weight_rsp_data_o,

    input  logic        qparam_req_valid_i,
    output logic        qparam_req_ready_o,
    input  logic [10:0] qparam_req_addr_i,
    output logic        qparam_rsp_valid_o,
    input  logic        qparam_rsp_ready_i,
    output logic [255:0] multiplier_vec_o,
    output logic [511:0] bias_postscale_vec_o,
    output logic [63:0]  right_shift_vec_o,
    output logic [63:0]  zero_point_vec_o,
    output logic [7:0]   relu_en_vec_o,

    output logic         params_ready_o,

    output logic         ddr_rd_req_valid_o,
    input  logic         ddr_rd_req_ready_i,
    output logic [31:0]  ddr_rd_req_addr_o,
    input  logic         ddr_rd_rsp_valid_i,
    output logic         ddr_rd_rsp_ready_o,
    input  logic [63:0]  ddr_rd_rsp_data_i
);

    // V6.0.4: the downstream conv_layer_engine already preloads the entire
    // layer's weight set into four M10K banks. The extra DDR-side 512-line
    // cache can be bypassed without altering weights or transaction ordering.
    // Set 1 to restore old cache; default 0 saves FPGA RAM/valid FFs.
    localparam bit ENABLE_WEIGHT_READ_CACHE = 1'b0;

    // V4 synchronous direct-mapped 4 KiB weight cache.
    // Data+tag are read through a registered address so Quartus can infer M10K
    // instead of expanding 32 kbit of cache data into registers/ALMs.
    localparam integer CACHE_LINES = 512;

    (* ramstyle = "M10K" *) logic [71:0] weight_cache_mem [0:CACHE_LINES-1]; // {tag[7:0],data[63:0]}
    logic [CACHE_LINES-1:0] cache_valid_r;
    logic [8:0] cache_rd_idx_r;
    logic [71:0] cache_line_q;
    logic cache_we_c;
    logic [8:0] cache_wr_idx_c;
    logic [71:0] cache_wr_line_c;

    typedef enum logic [4:0] {
        S_MAGIC_REQ, S_MAGIC_WAIT, S_MAGIC_DELAY,
        S_IDLE,
        S_W_CACHE_WAIT, S_W_LOOKUP, S_W_DDR_REQ, S_W_DDR_WAIT, S_W_HOLD,
        S_Q_REQ, S_Q_WAIT, S_Q_HOLD
    } state_t;

    state_t state_r;
    logic [POLL_BITS-1:0] poll_count_r;
    logic [16:0] w_addr_r;
    logic [10:0] q_addr_r;
    logic [3:0] qword_r;
    logic [7:0] cache_tag_req_r;

    logic [63:0]  weight_rsp_data_r;
    logic [255:0] q_mult_r;
    logic [511:0] q_bias_r;
    logic [63:0]  q_shift_r;
    logic [63:0]  q_zp_r;
    logic [7:0]   q_relu_r;

    assign params_ready_o = (state_r >= S_IDLE);
    assign weight_rsp_valid_o = (state_r == S_W_HOLD);
    assign qparam_rsp_valid_o = (state_r == S_Q_HOLD);
    assign weight_rsp_data_o = weight_rsp_data_r;
    assign multiplier_vec_o = q_mult_r;
    assign bias_postscale_vec_o = q_bias_r;
    assign right_shift_vec_o = q_shift_r;
    assign zero_point_vec_o = q_zp_r;
    assign relu_en_vec_o = q_relu_r;

    assign qparam_req_ready_o = (state_r == S_IDLE);
    assign weight_req_ready_o = (state_r == S_IDLE) && !qparam_req_valid_i;

    function automatic [31:0] weight_ddr_addr(input logic [16:0] a);
        weight_ddr_addr = WEIGHT_BASE + {12'd0, a, 3'b000};
    endfunction

    function automatic [31:0] qparam_ddr_addr(input logic [10:0] g,input logic [3:0] w);
        logic [31:0] goff;
        begin
            // 15 x 64-bit words = 120 bytes/group. Shift/add only.
            goff = ({21'd0,g} << 7) - ({21'd0,g} << 3);
            qparam_ddr_addr = QPARAM_BASE + goff + {25'd0,w,3'b000};
        end
    endfunction

    always_comb begin
        ddr_rd_req_valid_o = 1'b0;
        ddr_rd_req_addr_o  = 32'd0;
        ddr_rd_rsp_ready_o = 1'b0;

        case (state_r)
            S_MAGIC_REQ: begin
                ddr_rd_req_valid_o = 1'b1;
                ddr_rd_req_addr_o = MAGIC_ADDR;
            end
            S_MAGIC_WAIT: ddr_rd_rsp_ready_o = 1'b1;
            S_W_DDR_REQ: begin
                ddr_rd_req_valid_o = 1'b1;
                ddr_rd_req_addr_o = weight_ddr_addr(w_addr_r);
            end
            S_W_DDR_WAIT: ddr_rd_rsp_ready_o = 1'b1;
            S_Q_REQ: begin
                ddr_rd_req_valid_o = 1'b1;
                ddr_rd_req_addr_o = qparam_ddr_addr(q_addr_r,qword_r);
            end
            S_Q_WAIT: ddr_rd_rsp_ready_o = 1'b1;
            default: begin end
        endcase
    end

    assign cache_we_c = ENABLE_WEIGHT_READ_CACHE &&
                        (state_r == S_W_DDR_WAIT) && ddr_rd_rsp_valid_i;
    assign cache_wr_idx_c = w_addr_r[8:0];
    assign cache_wr_line_c = {w_addr_r[16:9],ddr_rd_rsp_data_i};

    // Single synchronous RAM process: registered read + optional write.
    always_ff @(posedge clk_i) begin
        cache_line_q <= weight_cache_mem[cache_rd_idx_r];
        if (cache_we_c)
            weight_cache_mem[cache_wr_idx_c] <= cache_wr_line_c;
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_MAGIC_REQ;
            poll_count_r <= '0;
            w_addr_r <= 17'd0;
            q_addr_r <= 11'd0;
            qword_r <= 4'd0;
            cache_tag_req_r <= 8'd0;
            cache_rd_idx_r <= 9'd0;
            cache_valid_r <= '0;
            weight_rsp_data_r <= 64'd0;
            q_mult_r <= 256'd0;
            q_bias_r <= 512'd0;
            q_shift_r <= 64'd0;
            q_zp_r <= 64'd0;
            q_relu_r <= 8'd0;
        end else begin
            if (cache_we_c)
                cache_valid_r[cache_wr_idx_c] <= 1'b1;

            case (state_r)
                S_MAGIC_REQ: if (ddr_rd_req_ready_i) state_r <= S_MAGIC_WAIT;

                S_MAGIC_WAIT: if (ddr_rd_rsp_valid_i) begin
                    if (ddr_rd_rsp_data_i[31:0] == MAGIC_VALUE)
                        state_r <= S_IDLE;
                    else begin
                        poll_count_r <= '0;
                        state_r <= S_MAGIC_DELAY;
                    end
                end

                S_MAGIC_DELAY: begin
                    if (&poll_count_r) begin
                        poll_count_r <= '0;
                        state_r <= S_MAGIC_REQ;
                    end else
                        poll_count_r <= poll_count_r + 1'b1;
                end

                S_IDLE: begin
                    if (qparam_req_valid_i) begin
                        q_addr_r <= qparam_req_addr_i;
                        qword_r <= 4'd0;
                        q_mult_r <= 256'd0;
                        q_bias_r <= 512'd0;
                        q_shift_r <= 64'd0;
                        q_zp_r <= 64'd0;
                        q_relu_r <= 8'd0;
                        state_r <= S_Q_REQ;
                    end else if (weight_req_valid_i) begin
                        w_addr_r <= weight_req_addr_i;
                        cache_tag_req_r <= weight_req_addr_i[16:9];
                        cache_rd_idx_r <= weight_req_addr_i[8:0];
                        state_r <= ENABLE_WEIGHT_READ_CACHE ? S_W_CACHE_WAIT
                                                             : S_W_DDR_REQ;
                    end
                end

                // One dead cycle is intentional for synchronous M10K read.
                S_W_CACHE_WAIT: state_r <= S_W_LOOKUP;

                S_W_LOOKUP: begin
                    if (cache_valid_r[w_addr_r[8:0]] && (cache_line_q[71:64] == cache_tag_req_r)) begin
                        weight_rsp_data_r <= cache_line_q[63:0];
                        state_r <= S_W_HOLD;
                    end else begin
                        state_r <= S_W_DDR_REQ;
                    end
                end

                S_W_DDR_REQ: if (ddr_rd_req_ready_i) state_r <= S_W_DDR_WAIT;

                S_W_DDR_WAIT: if (ddr_rd_rsp_valid_i) begin
                    weight_rsp_data_r <= ddr_rd_rsp_data_i;
                    state_r <= S_W_HOLD;
                end

                S_W_HOLD: if (weight_rsp_ready_i) state_r <= S_IDLE;

                S_Q_REQ: if (ddr_rd_req_ready_i) state_r <= S_Q_WAIT;

                S_Q_WAIT: if (ddr_rd_rsp_valid_i) begin
                    case (qword_r)
                        4'd0:  q_mult_r[63:0]     <= ddr_rd_rsp_data_i;
                        4'd1:  q_mult_r[127:64]   <= ddr_rd_rsp_data_i;
                        4'd2:  q_mult_r[191:128]  <= ddr_rd_rsp_data_i;
                        4'd3:  q_mult_r[255:192]  <= ddr_rd_rsp_data_i;
                        4'd4:  q_bias_r[63:0]     <= ddr_rd_rsp_data_i;
                        4'd5:  q_bias_r[127:64]   <= ddr_rd_rsp_data_i;
                        4'd6:  q_bias_r[191:128]  <= ddr_rd_rsp_data_i;
                        4'd7:  q_bias_r[255:192]  <= ddr_rd_rsp_data_i;
                        4'd8:  q_bias_r[319:256]  <= ddr_rd_rsp_data_i;
                        4'd9:  q_bias_r[383:320]  <= ddr_rd_rsp_data_i;
                        4'd10: q_bias_r[447:384]  <= ddr_rd_rsp_data_i;
                        4'd11: q_bias_r[511:448]  <= ddr_rd_rsp_data_i;
                        4'd12: q_shift_r           <= ddr_rd_rsp_data_i;
                        4'd13: q_zp_r              <= ddr_rd_rsp_data_i;
                        4'd14: q_relu_r             <= ddr_rd_rsp_data_i[7:0];
                        default: begin end
                    endcase
                    if (qword_r == 4'd14)
                        state_r <= S_Q_HOLD;
                    else begin
                        qword_r <= qword_r + 1'b1;
                        state_r <= S_Q_REQ;
                    end
                end

                S_Q_HOLD: if (qparam_rsp_ready_i) state_r <= S_IDLE;
                default: state_r <= S_MAGIC_REQ;
            endcase
        end
    end
endmodule
