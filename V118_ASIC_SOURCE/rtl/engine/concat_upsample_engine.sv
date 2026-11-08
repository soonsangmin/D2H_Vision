module concat_upsample_engine (
    input logic clk_i, input logic rstn_i, input logic start_i,
    input handseg_config_pkg::concat_cfg_t cfg_i,
    input logic [2:0] feature_bank_i, input logic [2:0] skip_bank_i, input logic [2:0] dst_bank_i,
    output logic busy_o, output logic done_o,
    output logic rd_req_valid_o, input logic rd_req_ready_i, output logic [2:0] rd_req_bank_o, output logic [16:0] rd_req_addr_o,
    input logic rd_rsp_valid_i, output logic rd_rsp_ready_o, input logic [63:0] rd_rsp_data_i,
    output logic wr_valid_o, input logic wr_ready_i, output logic [2:0] wr_bank_o, output logic [16:0] wr_addr_o, output logic [63:0] wr_data_o
);
    import handseg_config_pkg::*;

    // V4: old design instantiated two 8-lane requantizers (16 multipliers).
    // This engine requantizes one byte per clock with one shared 9x33
    // multiplier. Decoder concatenation is bandwidth/latency tolerant, so the
    // resource saving is much more valuable than 8-lane throughput here.

    typedef enum logic [3:0] {S_IDLE,S_REQ,S_WAIT,S_PREP,S_MUL,S_ROUND,S_QUANT,S_WRITE,S_DONE} state_t;
    state_t state_r;
    concat_cfg_t cfg_r;
    logic [2:0] feature_bank_r, skip_bank_r, dst_bank_r;
    logic [8:0] x_r, y_r;
    logic [3:0] group_r;
    logic [2:0] lane_r;
    logic [63:0] src_word_r, out_word_r;

    logic use_feature_c;
    logic [7:0] src_zp_c, dst_zp_c;
    logic [31:0] mult_c;
    logic [7:0] shift_c;
    logic signed [8:0] centered_c, centered_r;
    logic signed [32:0] mult_ext_c, mult_r;
    logic signed [41:0] product_r;
    logic [7:0] shift_r, dst_zp_r;
    logic signed [63:0] product_ext_c, scaled_r;
    logic signed [64:0] with_zp_c;
    logic [7:0] lane_q_c;

    // Address accumulators replace repeated generic multiplications in the
    // output path. Source feature address still uses shift/add because the
    // spatial width is a power-of-two-ish runtime descriptor, but no / or %.
    logic [16:0] dst_addr_r;

    function automatic signed [63:0] rne_shift64(
        input signed [63:0] value,
        input [7:0] shift
    );
        logic neg;
        logic [63:0] mag, quot, rem, mask, halfv, rounded;
        begin
            if (shift == 0) rne_shift64 = value;
            else if (shift >= 64) rne_shift64 = 64'sd0;
            else begin
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

    // Small shift/add multiply for address generation: a(<=320*256) * b(<=16).
    // No '*' operator, so Quartus will not allocate a DSP for this bookkeeping.
    function automatic [16:0] mul17x6_shiftadd(input [16:0] a, input [5:0] b);
        reg [22:0] t;
        integer k;
        begin
            t = 23'd0;
            for (k=0; k<6; k=k+1)
                if (b[k]) t = t + ({6'd0,a} << k);
            mul17x6_shiftadd = t[16:0];
        end
    endfunction


    function automatic [16:0] mul9x9_shiftadd(input [8:0] a, input [8:0] b);
        reg [17:0] t;
        integer j;
        begin
            t = 18'd0;
            for (j=0; j<9; j=j+1)
                if (b[j]) t = t + ({9'd0,a} << j);
            mul9x9_shiftadd = t[16:0];
        end
    endfunction

    logic [16:0] feature_pixel_index_c;
    logic [16:0] skip_pixel_index_c;
    logic [16:0] feature_addr_c;
    logic [16:0] skip_addr_c;

    always_comb begin
        use_feature_c = (group_r < cfg_r.feature_groups);
        src_zp_c = use_feature_c ? cfg_r.feature_zero_point : cfg_r.skip_zero_point;
        mult_c   = use_feature_c ? cfg_r.feature_multiplier : cfg_r.skip_multiplier;
        shift_c  = use_feature_c ? cfg_r.feature_shift : cfg_r.skip_shift;
        dst_zp_c = cfg_r.concat_zero_point;

        centered_c = $signed({1'b0,src_word_r[lane_r*8 +: 8]}) - $signed({1'b0,src_zp_c});
        mult_ext_c = $signed({1'b0,mult_c});
        product_ext_c = $signed({{22{product_r[41]}},product_r});
        with_zp_c = scaled_r + $signed({1'b0,dst_zp_r});
        if (with_zp_c < 0) lane_q_c = 8'd0;
        else if (with_zp_c > 255) lane_q_c = 8'd255;
        else lane_q_c = with_zp_c[7:0];

        // y/x are already explicit counters. Upsampling by 2 is a shift.
        feature_pixel_index_c = mul9x9_shiftadd((y_r >> 1), (cfg_r.out_width >> 1)) + (x_r >> 1);
        skip_pixel_index_c    = mul9x9_shiftadd(y_r, cfg_r.out_width) + x_r;
        feature_addr_c = mul17x6_shiftadd(feature_pixel_index_c, cfg_r.feature_groups) + group_r;
        skip_addr_c    = mul17x6_shiftadd(skip_pixel_index_c, cfg_r.skip_groups);
    end

    assign busy_o = (state_r != S_IDLE) && (state_r != S_DONE);
    assign done_o = (state_r == S_DONE);
    assign rd_req_valid_o = (state_r == S_REQ);
    assign rd_req_bank_o = use_feature_c ? feature_bank_r : skip_bank_r;
    assign rd_req_addr_o = use_feature_c ? feature_addr_c : skip_addr_c;
    assign rd_rsp_ready_o = (state_r == S_WAIT);
    assign wr_valid_o = (state_r == S_WRITE);
    assign wr_bank_o = dst_bank_r;
    assign wr_addr_o = dst_addr_r;
    assign wr_data_o = out_word_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_IDLE;
            cfg_r <= '0;
            feature_bank_r <= 3'd0;
            skip_bank_r <= 3'd0;
            dst_bank_r <= 3'd0;
            x_r <= 9'd0;
            y_r <= 9'd0;
            group_r <= 4'd0;
            lane_r <= 3'd0;
            src_word_r <= 64'd0;
            out_word_r <= 64'd0;
            dst_addr_r <= 17'd0;
            centered_r <= 9'sd0;
            mult_r <= 33'sd0;
            shift_r <= 8'd0;
            dst_zp_r <= 8'd0;
            product_r <= 42'sd0;
            scaled_r <= 64'sd0;
        end else begin
            case (state_r)
                S_IDLE: if (start_i) begin
                    cfg_r <= cfg_i;
                    feature_bank_r <= feature_bank_i;
                    skip_bank_r <= skip_bank_i;
                    dst_bank_r <= dst_bank_i;
                    x_r <= 9'd0;
                    y_r <= 9'd0;
                    group_r <= 4'd0;
                    lane_r <= 3'd0;
                    dst_addr_r <= 17'd0;
                    state_r <= S_REQ;
                end

                S_REQ: if (rd_req_ready_i) state_r <= S_WAIT;

                S_WAIT: if (rd_rsp_valid_i) begin
                    src_word_r <= rd_rsp_data_i;
                    out_word_r <= 64'd0;
                    lane_r <= 3'd0;
                    state_r <= S_PREP;
                end

                S_PREP: begin
                    centered_r <= centered_c;
                    mult_r <= mult_ext_c;
                    shift_r <= shift_c;
                    dst_zp_r <= dst_zp_c;
                    state_r <= S_MUL;
                end

                S_MUL: begin
                    product_r <= centered_r * mult_r;
                    state_r <= S_ROUND;
                end

                S_ROUND: begin
                    scaled_r <= rne_shift64(product_ext_c, shift_r);
                    state_r <= S_QUANT;
                end

                S_QUANT: begin
                    out_word_r[lane_r*8 +: 8] <= lane_q_c;
                    if (lane_r == 3'd7)
                        state_r <= S_WRITE;
                    else begin
                        lane_r <= lane_r + 1'b1;
                        state_r <= S_PREP;
                    end
                end

                S_WRITE: if (wr_ready_i) begin
                    dst_addr_r <= dst_addr_r + 1'b1;
                    if (group_r == (cfg_r.feature_groups + cfg_r.skip_groups - 1)) begin
                        group_r <= 4'd0;
                        if (x_r == cfg_r.out_width-1) begin
                            x_r <= 9'd0;
                            if (y_r == cfg_r.out_height-1)
                                state_r <= S_DONE;
                            else begin
                                y_r <= y_r + 1'b1;
                                state_r <= S_REQ;
                            end
                        end else begin
                            x_r <= x_r + 1'b1;
                            state_r <= S_REQ;
                        end
                    end else begin
                        group_r <= group_r + 1'b1;
                        state_r <= S_REQ;
                    end
                end

                S_DONE: state_r <= S_IDLE;
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
