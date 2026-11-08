module residual_word_engine (
    input logic clk_i, input logic rstn_i, input logic start_i,
    input handseg_config_pkg::residual_cfg_t cfg_i,
    input logic [2:0] main_bank_i, input logic [2:0] shortcut_bank_i, input logic [2:0] dst_bank_i,
    input logic [16:0] word_count_i,
    output logic busy_o, output logic done_o,
    output logic rd0_req_valid_o, input logic rd0_req_ready_i, output logic [2:0] rd0_req_bank_o, output logic [16:0] rd0_req_addr_o,
    input logic rd0_rsp_valid_i, output logic rd0_rsp_ready_o, input logic [63:0] rd0_rsp_data_i,
    output logic rd1_req_valid_o, input logic rd1_req_ready_i, output logic [2:0] rd1_req_bank_o, output logic [16:0] rd1_req_addr_o,
    input logic rd1_rsp_valid_i, output logic rd1_rsp_ready_o, input logic [63:0] rd1_rsp_data_i,
    output logic wr_valid_o, input logic wr_ready_i, output logic [2:0] wr_bank_o, output logic [16:0] wr_addr_o, output logic [63:0] wr_data_o
);
    import handseg_config_pkg::*;

    // V4: one physical 9x33 multiplier is reused for all 8 lanes and for both
    // branches of Stage2D. This is intentionally slower (16 multiply cycles
    // per packed word) but removes the 16 parallel multipliers in the old
    // residual_single_rne_8 datapath.

    typedef enum logic [3:0] {
        S_IDLE, S_REQ, S_WAIT,
        S_MAIN_MUL, S_SHORT_MUL, S_ROUND_STORE,
        S_WRITE, S_DONE
    } state_t;

    state_t state_r;
    residual_cfg_t cfg_r;
    logic [2:0] main_bank_r, skip_bank_r, dst_bank_r;
    logic [16:0] count_r, index_r;
    logic [63:0] main_word_r, skip_word_r, result_word_r;
    logic main_have_r, skip_have_r;
    logic [2:0] lane_r;

    logic signed [8:0]  mul_a_c;
    logic signed [32:0] mul_b_c;
    logic signed [41:0] mul_product_c;
    logic signed [41:0] main_product_r;
    logic signed [41:0] shortcut_product_r;
    logic signed [63:0] numerator_c;
    logic signed [63:0] scaled_c;
    logic signed [64:0] with_zp_c;
    logic [7:0] lane_q_c;

    function automatic signed [63:0] rne_shift64(
        input signed [63:0] value,
        input [7:0] shift
    );
        logic neg;
        logic [63:0] mag, quot, rem, mask, halfv, rounded;
        begin
            if (shift == 0) begin
                rne_shift64 = value;
            end else if (shift >= 64) begin
                rne_shift64 = 64'sd0;
            end else begin
                neg = value[63];
                mag = neg ? (~$unsigned(value) + 64'd1) : $unsigned(value);
                quot = mag >> shift;
                mask = {64{1'b1}} >> (64-shift);
                rem = mag & mask;
                halfv = 64'd1 << (shift-1);
                rounded = quot + ((rem > halfv) || ((rem == halfv) && quot[0]));
                rne_shift64 = neg ? -$signed(rounded) : $signed(rounded);
            end
        end
    endfunction

    always_comb begin
        mul_a_c = 9'sd0;
        mul_b_c = 33'sd0;

        if (state_r == S_MAIN_MUL) begin
            mul_a_c = $signed({1'b0,main_word_r[lane_r*8 +: 8]}) -
                      $signed({1'b0,cfg_r.main_zero_point});
            mul_b_c = $signed({1'b0,cfg_r.main_multiplier});
        end else if (state_r == S_SHORT_MUL) begin
            mul_a_c = $signed({1'b0,skip_word_r[lane_r*8 +: 8]}) -
                      $signed({1'b0,cfg_r.shortcut_zero_point});
            mul_b_c = $signed({1'b0,cfg_r.shortcut_multiplier});
        end

        // Exactly one multiplier in this module.
        mul_product_c = mul_a_c * mul_b_c;

        numerator_c = $signed({{22{main_product_r[41]}},main_product_r}) +
                      $signed({{22{shortcut_product_r[41]}},shortcut_product_r});
        scaled_c = rne_shift64(numerator_c, cfg_r.shared_right_shift);
        with_zp_c = scaled_c + $signed({1'b0,cfg_r.output_zero_point});

        if (with_zp_c < 0)
            lane_q_c = 8'd0;
        else if (with_zp_c > 255)
            lane_q_c = 8'd255;
        else
            lane_q_c = with_zp_c[7:0];
    end

    assign busy_o = (state_r != S_IDLE) && (state_r != S_DONE);
    assign done_o = (state_r == S_DONE);

    assign rd0_req_valid_o = (state_r == S_REQ);
    assign rd0_req_bank_o = main_bank_r;
    assign rd0_req_addr_o = index_r;
    assign rd0_rsp_ready_o = (state_r == S_WAIT) && !main_have_r;

    assign rd1_req_valid_o = (state_r == S_REQ);
    assign rd1_req_bank_o = skip_bank_r;
    assign rd1_req_addr_o = index_r;
    assign rd1_rsp_ready_o = (state_r == S_WAIT) && !skip_have_r;

    assign wr_valid_o = (state_r == S_WRITE);
    assign wr_bank_o = dst_bank_r;
    assign wr_addr_o = index_r;
    assign wr_data_o = result_word_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_IDLE;
            cfg_r <= '0;
            main_bank_r <= 3'd0;
            skip_bank_r <= 3'd0;
            dst_bank_r <= 3'd0;
            count_r <= 17'd0;
            index_r <= 17'd0;
            main_word_r <= 64'd0;
            skip_word_r <= 64'd0;
            result_word_r <= 64'd0;
            main_have_r <= 1'b0;
            skip_have_r <= 1'b0;
            lane_r <= 3'd0;
            main_product_r <= 42'sd0;
            shortcut_product_r <= 42'sd0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (start_i) begin
                        cfg_r <= cfg_i;
                        main_bank_r <= main_bank_i;
                        skip_bank_r <= shortcut_bank_i;
                        dst_bank_r <= dst_bank_i;
                        count_r <= word_count_i;
                        index_r <= 17'd0;
                        state_r <= S_REQ;
                    end
                end

                S_REQ: begin
                    if (rd0_req_ready_i && rd1_req_ready_i) begin
                        main_have_r <= 1'b0;
                        skip_have_r <= 1'b0;
                        state_r <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (rd0_rsp_valid_i) begin
                        main_word_r <= rd0_rsp_data_i;
                        main_have_r <= 1'b1;
                    end
                    if (rd1_rsp_valid_i) begin
                        skip_word_r <= rd1_rsp_data_i;
                        skip_have_r <= 1'b1;
                    end
                    if ((main_have_r || rd0_rsp_valid_i) &&
                        (skip_have_r || rd1_rsp_valid_i)) begin
                        lane_r <= 3'd0;
                        result_word_r <= 64'd0;
                        state_r <= S_MAIN_MUL;
                    end
                end

                S_MAIN_MUL: begin
                    main_product_r <= mul_product_c;
                    state_r <= S_SHORT_MUL;
                end

                S_SHORT_MUL: begin
                    shortcut_product_r <= mul_product_c;
                    state_r <= S_ROUND_STORE;
                end

                S_ROUND_STORE: begin
                    result_word_r[lane_r*8 +: 8] <= lane_q_c;
                    if (lane_r == 3'd7) begin
                        state_r <= S_WRITE;
                    end else begin
                        lane_r <= lane_r + 1'b1;
                        state_r <= S_MAIN_MUL;
                    end
                end

                S_WRITE: begin
                    if (wr_ready_i) begin
                        if (index_r == count_r-1) begin
                            state_r <= S_DONE;
                        end else begin
                            index_r <= index_r + 1'b1;
                            state_r <= S_REQ;
                        end
                    end
                end

                S_DONE: state_r <= S_IDLE;
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
