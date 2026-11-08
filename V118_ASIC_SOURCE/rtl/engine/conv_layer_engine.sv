module conv_layer_engine (
    input  logic clk_i,
    input  logic rstn_i,
    input  logic start_i,
    input  handseg_config_pkg::layer_cfg_t cfg_i,
    input  logic [2:0] src_bank_i,
    input  logic [2:0] dst_bank_i,
    output logic busy_o,
    output logic done_o,

    output logic        mem_rd_req_valid_o,
    input  logic        mem_rd_req_ready_i,
    output logic [2:0]  mem_rd_req_bank_o,
    output logic [16:0] mem_rd_req_addr_o,
    input  logic        mem_rd_rsp_valid_i,
    output logic        mem_rd_rsp_ready_o,
    input  logic [63:0] mem_rd_rsp_data_i,

    output logic        mem_wr_valid_o,
    input  logic        mem_wr_ready_i,
    output logic [2:0]  mem_wr_bank_o,
    output logic [16:0] mem_wr_addr_o,
    output logic [63:0] mem_wr_data_o,

    output logic        weight_req_valid_o,
    input  logic        weight_req_ready_i,
    output logic [16:0] weight_req_addr_o,
    input  logic        weight_rsp_valid_i,
    output logic        weight_rsp_ready_o,
    input  logic [63:0] weight_rsp_data_i,

    output logic        qparam_req_valid_o,
    input  logic        qparam_req_ready_i,
    output logic [10:0] qparam_req_addr_o,
    input  logic        qparam_rsp_valid_i,
    output logic        qparam_rsp_ready_o,
    input  logic [255:0] multiplier_vec_i,
    input  logic [511:0] bias_vec_i,
    input  logic [63:0] shift_vec_i,
    input  logic [63:0] zp_vec_i,
    input  logic [7:0] relu_vec_i
);
    import handseg_config_pkg::*;

    // V6.0.3 time-multiplexed HandSeg integration note:
    // Two physical 8-PE compute cores process the original output groups
    // in two successive passes per quartet. Network descriptors, weights,
    // biases, quantization, and arithmetic have not been modified.

    // =====================================================================
    // V4.8 PIXEL-MAJOR / LAYER-LOCAL CACHE ENGINE
    // =====================================================================
    // The old schedule was output-group-major.  Every pair of output groups
    // walked the complete source feature map again, which made DDR/cache
    // handshakes dominate wall-clock latency even with 16 MAC PEs.
    //
    // V4.8 changes the loop order:
    //   1) load ALL weights + qparams for the layer once into M10K;
    //   2) for each output pixel, fetch its source activation working set once;
    //   3) reuse that local activation set across every output-group quartet.
    //
    // POINTWISE/FC: cache one complete input vector (<=20 packed words).
    // STANDARD stem: cache the 3x3 spatial neighborhood (9 packed words).
    // DEPTHWISE: cache the complete 3x3 x channel-groups neighborhood in four
    //            interleaved M10K banks.  Loads are group-contiguous, matching the
    //            128-byte burst-line cache in the DDR adapter.
    //
    // Numerical MAC ordering inside every output channel is unchanged.
    //
    // Original V5.0 used four compute_core instances (32 MAC PEs).
    // V6.0.3 processes two adjacent output groups at a time (16 MAC PEs).
    // Power-of-two four-bank interleaving also removes the V4.9 /3 and %3
    // divider/modulo logic. The activation working set is still loaded once
    // per pixel and shared by all four cores.
    // =====================================================================

    localparam integer WEIGHT_BANK_DEPTH = 2400; // max ceil(groups/4)*mac_steps
    localparam integer WEIGHT_AW         = 12;
    localparam integer QPAIR_DEPTH       = 15;   // max ceil(60/4)=15
    localparam integer QPAIR_AW          = 4;
    localparam integer QW                = 904;
    localparam integer DW_BANK_DEPTH     = 135;  // max 15 quartets * 9 taps
    localparam integer DW_AW             = 8;

    typedef enum logic [4:0] {
        S_IDLE,
        S_PREP_ROWWORDS,
        S_WLOAD_REQ,
        S_WLOAD_WAIT,
        S_QLOAD_REQ,
        S_QLOAD_WAIT,
        S_PIXEL_INIT,
        S_PW_LOAD_REQ,
        S_PW_LOAD_WAIT,
        S_STD_LOAD_CHECK,
        S_STD_LOAD_REQ,
        S_STD_LOAD_WAIT,
        S_DW_LOAD_CHECK,
        S_DW_LOAD_REQ,
        S_DW_LOAD_WAIT,
        S_PAIR_PREP,
        S_PAIR_RUN,
        S_WAIT_OUT,
        S_WRITE0,
        S_WRITE1,
        S_WRITE2,
        S_WRITE3,
        S_PAIR_NEXT,
        S_PIXEL_NEXT,
        S_DONE
    } state_t;

    state_t state_r;
    layer_cfg_t cfg_r;
    logic [2:0] src_bank_r, dst_bank_r;

    // Geometry / current output pixel.
    logic [8:0]  out_x_r, out_y_r;
    logic [16:0] row_words_r;
    logic [5:0]  prep_count_r;
    logic [16:0] in_x_base_words_r, in_y_base_words_r;
    logic [16:0] out_pixel_base_r;
    logic [16:0] x_stride_words_c, y_stride_words_c;

    // Layer-local weight preload.
    logic [5:0]  w_group_r;
    logic [9:0]  w_step_r;
    logic [16:0] w_ext_addr_r;
    logic [WEIGHT_AW-1:0] w_bank0_wr_idx_r, w_bank1_wr_idx_r, w_bank2_wr_idx_r, w_bank3_wr_idx_r;
    logic [1:0] w_bank_sel_r;

    // Layer-local qparam preload.
    logic [5:0] q_group_r;
    logic [1:0] q_bank_sel_r;
    logic [QPAIR_AW-1:0] q_slot_r;
    logic [QW-1:0] qpack_c;

    // Pixel-local activation buffer for POINTWISE/FC and STANDARD stem.
    // 64 x 64 = 4 Ki-bit, explicitly synchronous so Quartus maps it to M10K.
    logic        act_small_we_c;
    logic [5:0]  act_small_wr_addr_c, act_small_rd_addr_c;
    logic [63:0] act_small_wr_data_c, act_small_q_r;
    logic [5:0]  pw_load_group_r;
    logic [3:0]  std_load_pos_r;
    logic [1:0]  std_load_ky_r, std_load_kx_r;

    // DEPTHWISE neighborhood loader.
    logic [5:0] dw_load_group_r;
    logic [3:0] dw_load_kpos_r;
    logic [1:0] dw_load_ky_r, dw_load_kx_r;

    // Output-quartet compute state.
    logic [4:0] pair_idx_r;
    logic [5:0] out_group_r;
    logic [WEIGHT_AW-1:0] pair_weight_base_r;
    logic [DW_AW-1:0] pair_dw_base_r;
    logic [9:0] step_r;
    logic [1:0] std_run_chan_r;
    logic [3:0] std_run_kpos_r;

    logic [63:0] pack0_r, pack1_r, pack2_r, pack3_r;
    logic core0_done_r, core1_done_r, core2_done_r, core3_done_r;

    // ---------------------------------------------------------------------
    // Address helpers
    // ---------------------------------------------------------------------
    logic signed [10:0] std_in_x_signed_c, std_in_y_signed_c;
    logic signed [10:0] dw_in_x_signed_c,  dw_in_y_signed_c;
    logic std_padding_c, dw_padding_c;
    logic signed [18:0] std_addr_signed_c, dw_addr_signed_c;
    logic signed [18:0] std_ky_off_c, std_kx_off_c;
    logic signed [18:0] dw_ky_off_c,  dw_kx_off_c;
    logic [16:0] pw_input_addr_c, std_input_addr_c, dw_input_addr_c;
    logic [8:0] dw_local_wr_addr_c;

    // ---------------------------------------------------------------------
    // Local weight/qparam/depthwise caches
    // ---------------------------------------------------------------------
    logic weight_bank0_we_c, weight_bank1_we_c, weight_bank2_we_c, weight_bank3_we_c;
    logic [WEIGHT_AW-1:0] weight_rd_addr_c;
    logic [63:0] weight0_word_r, weight1_word_r, weight2_word_r, weight3_word_r;


    logic dw_bank0_we_c, dw_bank1_we_c, dw_bank2_we_c, dw_bank3_we_c;
    logic [DW_AW-1:0] dw_rd_addr_c;
    logic [63:0] dw_bank0_word_r, dw_bank1_word_r, dw_bank2_word_r, dw_bank3_word_r;
    logic [63:0] dw_write_data_c;

    // ---------------------------------------------------------------------
    // Compute cluster
    // ---------------------------------------------------------------------
    logic pair_active_c, third_active_c, fourth_active_c;
    logic [6:0] out_group_plus1_c, out_group_plus2_c, out_group_plus3_c;
    logic [6:0] last_group_index_c;
    logic [7:0] core0_lane_mask_c, core1_lane_mask_c, core2_lane_mask_c, core3_lane_mask_c;
    logic [63:0] act0_vec_c, act1_vec_c, act2_vec_c, act3_vec_c;

    logic core0_mac_ready, core1_mac_ready, core2_mac_ready, core3_mac_ready, core_group_ready_c;
    logic core0_mac_valid_c, core1_mac_valid_c, core2_mac_valid_c, core3_mac_valid_c;
    logic core0_out_valid, core1_out_valid, core2_out_valid, core3_out_valid;
    logic core0_out_ready, core1_out_ready, core2_out_ready, core3_out_ready;
    logic [7:0] core0_out_data, core1_out_data, core2_out_data, core3_out_data;
    logic [2:0] core0_out_lane, core1_out_lane, core2_out_lane, core3_out_lane;
    logic core0_out_last, core1_out_last, core2_out_last, core3_out_last;
    logic core0_out_fire_c, core1_out_fire_c, core2_out_fire_c, core3_out_fire_c;
    logic core0_finish_c, core1_finish_c, core2_finish_c, core3_finish_c;

    logic [255:0] q0_mult_c, q1_mult_c;
    logic [511:0] q0_bias_c, q1_bias_c;
    logic [63:0] q0_shift_c, q1_shift_c;
    logic [63:0] q0_zp_c, q1_zp_c;
    logic [7:0] q0_relu_c, q1_relu_c;

    function automatic [7:0] select_byte(input [63:0] w, input [2:0] lane);
        select_byte = w[lane*8 +: 8];
    endfunction

    function automatic [63:0] insert_byte(
        input [63:0] w,
        input [2:0] lane,
        input [7:0] v
    );
        reg [63:0] t;
        begin
            t = w;
            t[lane*8 +: 8] = v;
            insert_byte = t;
        end
    endfunction

    // =====================================================================
    // Geometry and source-address generation
    // =====================================================================
    always_comb begin
        x_stride_words_c = (cfg_r.stride == 2) ?
                           ({11'd0,cfg_r.in_groups8} << 1) :
                            {11'd0,cfg_r.in_groups8};
        y_stride_words_c = (cfg_r.stride == 2) ?
                           (row_words_r << 1) : row_words_r;

        pw_input_addr_c = in_y_base_words_r + in_x_base_words_r +
                          {11'd0,pw_load_group_r};

        std_in_x_signed_c = ($signed({1'b0,out_x_r}) <<< 1) +
                            $signed({9'd0,std_load_kx_r}) -
                            $signed({7'd0,cfg_r.padding});
        std_in_y_signed_c = ($signed({1'b0,out_y_r}) <<< 1) +
                            $signed({9'd0,std_load_ky_r}) -
                            $signed({7'd0,cfg_r.padding});
        std_padding_c = (std_in_x_signed_c < 0) ||
                        (std_in_y_signed_c < 0) ||
                        (std_in_x_signed_c >= $signed({2'b00,cfg_r.win})) ||
                        (std_in_y_signed_c >= $signed({2'b00,cfg_r.hin}));

        std_ky_off_c = 19'sd0;
        if (std_load_ky_r < cfg_r.padding)
            std_ky_off_c = -$signed({2'b00,row_words_r});
        else if (std_load_ky_r > cfg_r.padding)
            std_ky_off_c =  $signed({2'b00,row_words_r});

        std_kx_off_c = 19'sd0;
        if (std_load_kx_r < cfg_r.padding)
            std_kx_off_c = -$signed({13'd0,cfg_r.in_groups8});
        else if (std_load_kx_r > cfg_r.padding)
            std_kx_off_c =  $signed({13'd0,cfg_r.in_groups8});

        std_addr_signed_c = $signed({2'b00,in_y_base_words_r}) +
                            std_ky_off_c +
                            $signed({2'b00,in_x_base_words_r}) +
                            std_kx_off_c;
        std_input_addr_c = std_addr_signed_c[16:0];

        dw_in_x_signed_c = ($signed({1'b0,out_x_r}) <<<
                            ((cfg_r.stride == 2) ? 1 : 0)) +
                           $signed({9'd0,dw_load_kx_r}) -
                           $signed({7'd0,cfg_r.padding});
        dw_in_y_signed_c = ($signed({1'b0,out_y_r}) <<<
                            ((cfg_r.stride == 2) ? 1 : 0)) +
                           $signed({9'd0,dw_load_ky_r}) -
                           $signed({7'd0,cfg_r.padding});
        dw_padding_c = (dw_in_x_signed_c < 0) ||
                       (dw_in_y_signed_c < 0) ||
                       (dw_in_x_signed_c >= $signed({2'b00,cfg_r.win})) ||
                       (dw_in_y_signed_c >= $signed({2'b00,cfg_r.hin}));

        dw_ky_off_c = 19'sd0;
        if (dw_load_ky_r < cfg_r.padding)
            dw_ky_off_c = -$signed({2'b00,row_words_r});
        else if (dw_load_ky_r > cfg_r.padding)
            dw_ky_off_c =  $signed({2'b00,row_words_r});

        dw_kx_off_c = 19'sd0;
        if (dw_load_kx_r < cfg_r.padding)
            dw_kx_off_c = -$signed({13'd0,cfg_r.in_groups8});
        else if (dw_load_kx_r > cfg_r.padding)
            dw_kx_off_c =  $signed({13'd0,cfg_r.in_groups8});

        dw_addr_signed_c = $signed({2'b00,in_y_base_words_r}) +
                           dw_ky_off_c +
                           $signed({2'b00,in_x_base_words_r}) +
                           dw_kx_off_c +
                           $signed({13'd0,dw_load_group_r});
        dw_input_addr_c = dw_addr_signed_c[16:0];

        // floor(group/4)*9 + kpos. Four-way banking is power-of-two, so
        // Quartus only needs shifts/wires here (no lpm_divide).
        dw_local_wr_addr_c = ({5'd0,dw_load_group_r[5:2]} << 3) +
                             {5'd0,dw_load_group_r[5:2]} +
                             {5'd0,dw_load_kpos_r};
    end

    // =====================================================================
    // External memory/parameter handshakes
    // =====================================================================
    assign busy_o = (state_r != S_IDLE) && (state_r != S_DONE);
    assign done_o = (state_r == S_DONE);

    always_comb begin
        mem_rd_req_valid_o = 1'b0;
        mem_rd_req_bank_o  = src_bank_r;
        mem_rd_req_addr_o  = 17'd0;
        mem_rd_rsp_ready_o = 1'b0;

        case (state_r)
            S_PW_LOAD_REQ: begin
                mem_rd_req_valid_o = 1'b1;
                mem_rd_req_addr_o  = pw_input_addr_c;
            end
            S_PW_LOAD_WAIT: mem_rd_rsp_ready_o = 1'b1;

            S_STD_LOAD_REQ: begin
                mem_rd_req_valid_o = 1'b1;
                mem_rd_req_addr_o  = std_input_addr_c;
            end
            S_STD_LOAD_WAIT: mem_rd_rsp_ready_o = 1'b1;

            S_DW_LOAD_REQ: begin
                mem_rd_req_valid_o = 1'b1;
                mem_rd_req_addr_o  = dw_input_addr_c;
            end
            S_DW_LOAD_WAIT: mem_rd_rsp_ready_o = 1'b1;
            default: begin end
        endcase
    end

    assign weight_req_valid_o = (state_r == S_WLOAD_REQ);
    assign weight_req_addr_o  = w_ext_addr_r;
    assign weight_rsp_ready_o = (state_r == S_WLOAD_WAIT);

    assign qparam_req_valid_o = (state_r == S_QLOAD_REQ);
    assign qparam_req_addr_o  = cfg_r.qparam_base + {5'd0,q_group_r};
    assign qparam_rsp_ready_o = (state_r == S_QLOAD_WAIT);

    assign mem_wr_valid_o = (state_r == S_WRITE0) ||
                            (state_r == S_WRITE1) ||
                            (state_r == S_WRITE2) ||
                            (state_r == S_WRITE3);
    assign mem_wr_bank_o  = dst_bank_r;
    assign mem_wr_addr_o  = out_pixel_base_r + {11'd0,out_group_r} +
                            ((state_r == S_WRITE3) ? 17'd3 :
                             (state_r == S_WRITE2) ? 17'd2 :
                             (state_r == S_WRITE1) ? 17'd1 : 17'd0);
    assign mem_wr_data_o  = (state_r == S_WRITE3) ? pack3_r :
                            (state_r == S_WRITE2) ? pack2_r :
                            (state_r == S_WRITE1) ? pack1_r : pack0_r;

    // =====================================================================
    // Layer-local weight banks (four adjacent output groups)
    // =====================================================================
    assign weight_bank0_we_c = (state_r == S_WLOAD_WAIT) &&
                               weight_rsp_valid_i && (w_bank_sel_r == 2'd0);
    assign weight_bank1_we_c = (state_r == S_WLOAD_WAIT) &&
                               weight_rsp_valid_i && (w_bank_sel_r == 2'd1);
    assign weight_bank2_we_c = (state_r == S_WLOAD_WAIT) &&
                               weight_rsp_valid_i && (w_bank_sel_r == 2'd2);
    assign weight_bank3_we_c = (state_r == S_WLOAD_WAIT) &&
                               weight_rsp_valid_i && (w_bank_sel_r == 2'd3);

    always_comb begin
        weight_rd_addr_c = pair_weight_base_r + {2'd0,step_r};
        if ((state_r == S_PAIR_RUN) && core_group_ready_c &&
            (step_r != cfg_r.mac_steps-1))
            weight_rd_addr_c = pair_weight_base_r +
                               {2'd0,step_r} + 1'b1;
    end

    handseg_weight_group_ram #(.DEPTH(WEIGHT_BANK_DEPTH), .ADDR_W(WEIGHT_AW))
    u_weight_bank0_ram (
        .clk_i(clk_i),
        .wr_en_i(weight_bank0_we_c),
        .wr_addr_i(w_bank0_wr_idx_r),
        .wr_data_i(weight_rsp_data_i),
        .rd_addr_i(weight_rd_addr_c),
        .rd_data_o(weight0_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(WEIGHT_BANK_DEPTH), .ADDR_W(WEIGHT_AW))
    u_weight_bank1_ram (
        .clk_i(clk_i),
        .wr_en_i(weight_bank1_we_c),
        .wr_addr_i(w_bank1_wr_idx_r),
        .wr_data_i(weight_rsp_data_i),
        .rd_addr_i(weight_rd_addr_c),
        .rd_data_o(weight1_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(WEIGHT_BANK_DEPTH), .ADDR_W(WEIGHT_AW))
    u_weight_bank2_ram (
        .clk_i(clk_i),
        .wr_en_i(weight_bank2_we_c),
        .wr_addr_i(w_bank2_wr_idx_r),
        .wr_data_i(weight_rsp_data_i),
        .rd_addr_i(weight_rd_addr_c),
        .rd_data_o(weight2_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(WEIGHT_BANK_DEPTH), .ADDR_W(WEIGHT_AW))
    u_weight_bank3_ram (
        .clk_i(clk_i),
        .wr_en_i(weight_bank3_we_c),
        .wr_addr_i(w_bank3_wr_idx_r),
        .wr_data_i(weight_rsp_data_i),
        .rd_addr_i(weight_rd_addr_c),
        .rd_data_o(weight3_word_r)
    );

    // =====================================================================
    // V6.0.3: two physical qparam banks (16-PE engine)
    //
    // Original four banks each held 15 x 904-bit words (0/1/2/3).
    // 16-PE time multiplexing reads only two groups per pass.  Combine banks
    // 0+2 into a 30-row even memory and banks 1+3 into a 30-row odd memory.
    // Address [4]=second pass within output quartet; [3:0]=quartet slot.
    // This preserves every qparam bit and synchronous-read latency, while
    // eliminating two 904-bit RAM ports plus two very wide output multiplexers.
    // =====================================================================
    logic q_even_we_c, q_odd_we_c;
    logic [QPAIR_AW:0] q_even_wr_addr_c, q_odd_wr_addr_c;
    logic [QPAIR_AW:0] q_pair_read_addr_c;
    logic [QW-1:0] q_even_r, q_odd_r;

    assign qpack_c = {relu_vec_i, zp_vec_i, shift_vec_i, bias_vec_i,
                      multiplier_vec_i};
    assign q_even_we_c = (state_r == S_QLOAD_WAIT) && qparam_rsp_valid_i &&
                         !q_bank_sel_r[0];
    assign q_odd_we_c  = (state_r == S_QLOAD_WAIT) && qparam_rsp_valid_i &&
                          q_bank_sel_r[0];
    // q_bank_sel_r[1] is bank 2/3, which runs on the second 16-PE pass.
    assign q_even_wr_addr_c = {q_bank_sel_r[1], q_slot_r};
    assign q_odd_wr_addr_c  = {q_bank_sel_r[1], q_slot_r};
    assign q_pair_read_addr_c = {out_group_r[1], pair_idx_r[4:1]};

    handseg_qparam_cache_ram #(
        .DEPTH(1 << (QPAIR_AW+1)), .ADDR_W(QPAIR_AW+1), .WIDTH(QW)
    ) u_q_even_ram (
        .clk_i(clk_i), .wr_en_i(q_even_we_c),
        .wr_addr_i(q_even_wr_addr_c), .wr_data_i(qpack_c),
        .rd_addr_i(q_pair_read_addr_c), .rd_data_o(q_even_r)
    );

    handseg_qparam_cache_ram #(
        .DEPTH(1 << (QPAIR_AW+1)), .ADDR_W(QPAIR_AW+1), .WIDTH(QW)
    ) u_q_odd_ram (
        .clk_i(clk_i), .wr_en_i(q_odd_we_c),
        .wr_addr_i(q_odd_wr_addr_c), .wr_data_i(qpack_c),
        .rd_addr_i(q_pair_read_addr_c), .rd_data_o(q_odd_r)
    );

    assign q0_mult_c  = q_even_r[255:0];
    assign q0_bias_c  = q_even_r[767:256];
    assign q0_shift_c = q_even_r[831:768];
    assign q0_zp_c    = q_even_r[895:832];
    assign q0_relu_c  = q_even_r[903:896];
    assign q1_mult_c  = q_odd_r[255:0];
    assign q1_bias_c  = q_odd_r[767:256];
    assign q1_shift_c = q_odd_r[831:768];
    assign q1_zp_c    = q_odd_r[895:832];
    assign q1_relu_c  = q_odd_r[903:896];

    // =====================================================================
    // Small pixel-local activation M10K (POINTWISE/FC/STANDARD)
    // =====================================================================
    always_comb begin
        act_small_we_c      = 1'b0;
        act_small_wr_addr_c = 6'd0;
        act_small_wr_data_c = 64'd0;

        if ((state_r == S_PW_LOAD_WAIT) && mem_rd_rsp_valid_i) begin
            act_small_we_c      = 1'b1;
            act_small_wr_addr_c = pw_load_group_r;
            act_small_wr_data_c = mem_rd_rsp_data_i;
        end else if ((state_r == S_STD_LOAD_CHECK) && std_padding_c) begin
            act_small_we_c      = 1'b1;
            act_small_wr_addr_c = {2'd0,std_load_pos_r};
            act_small_wr_data_c = {8{cfg_r.input_zero_point}};
        end else if ((state_r == S_STD_LOAD_WAIT) && mem_rd_rsp_valid_i) begin
            act_small_we_c      = 1'b1;
            act_small_wr_addr_c = {2'd0,std_load_pos_r};
            act_small_wr_data_c = mem_rd_rsp_data_i;
        end
    end

    always_comb begin
        act_small_rd_addr_c = 6'd0;
        if ((cfg_r.kind == LAYER_POINTWISE) || (cfg_r.kind == LAYER_FC)) begin
            act_small_rd_addr_c = step_r[8:3];
            if ((state_r == S_PAIR_RUN) && core_group_ready_c &&
                (step_r != cfg_r.mac_steps-1) && (step_r[2:0] == 3'd7))
                act_small_rd_addr_c = step_r[8:3] + 1'b1;
        end else if (cfg_r.kind == LAYER_STANDARD) begin
            act_small_rd_addr_c = {2'd0,std_run_kpos_r};
            if ((state_r == S_PAIR_RUN) && core_group_ready_c &&
                (step_r != cfg_r.mac_steps-1)) begin
                if (std_run_kpos_r == 4'd8)
                    act_small_rd_addr_c = 6'd0;
                else
                    act_small_rd_addr_c = {2'd0,std_run_kpos_r} + 1'b1;
            end
        end
    end

    handseg_weight_group_ram #(.DEPTH(64), .ADDR_W(6), .USE_MLAB(1'b1))
    u_pixel_activation_ram (
        .clk_i(clk_i), .wr_en_i(act_small_we_c),
        .wr_addr_i(act_small_wr_addr_c), .wr_data_i(act_small_wr_data_c),
        .rd_addr_i(act_small_rd_addr_c), .rd_data_o(act_small_q_r)
    );

    // =====================================================================
    // DEPTHWISE pixel-neighborhood M10K banks
    // =====================================================================
    always_comb begin
        dw_write_data_c = mem_rd_rsp_data_i;
        if (state_r == S_DW_LOAD_CHECK)
            dw_write_data_c = {8{cfg_r.input_zero_point}};
    end

    assign dw_bank0_we_c = (((state_r == S_DW_LOAD_CHECK) && dw_padding_c) ||
                            ((state_r == S_DW_LOAD_WAIT) && mem_rd_rsp_valid_i)) &&
                           (dw_load_group_r[1:0] == 2'd0);
    assign dw_bank1_we_c = (((state_r == S_DW_LOAD_CHECK) && dw_padding_c) ||
                            ((state_r == S_DW_LOAD_WAIT) && mem_rd_rsp_valid_i)) &&
                           (dw_load_group_r[1:0] == 2'd1);
    assign dw_bank2_we_c = (((state_r == S_DW_LOAD_CHECK) && dw_padding_c) ||
                            ((state_r == S_DW_LOAD_WAIT) && mem_rd_rsp_valid_i)) &&
                           (dw_load_group_r[1:0] == 2'd2);
    assign dw_bank3_we_c = (((state_r == S_DW_LOAD_CHECK) && dw_padding_c) ||
                            ((state_r == S_DW_LOAD_WAIT) && mem_rd_rsp_valid_i)) &&
                           (dw_load_group_r[1:0] == 2'd3);

    always_comb begin
        dw_rd_addr_c = pair_dw_base_r + step_r[DW_AW-1:0];
        if ((state_r == S_PAIR_RUN) && core_group_ready_c &&
            (step_r != cfg_r.mac_steps-1))
            dw_rd_addr_c = pair_dw_base_r + step_r[DW_AW-1:0] + 1'b1;
    end

    handseg_weight_group_ram #(.DEPTH(DW_BANK_DEPTH), .ADDR_W(DW_AW), .USE_MLAB(1'b1))
    u_dw_bank0_ram (
        .clk_i(clk_i), .wr_en_i(dw_bank0_we_c),
        .wr_addr_i(dw_local_wr_addr_c[DW_AW-1:0]), .wr_data_i(dw_write_data_c),
        .rd_addr_i(dw_rd_addr_c), .rd_data_o(dw_bank0_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(DW_BANK_DEPTH), .ADDR_W(DW_AW), .USE_MLAB(1'b1))
    u_dw_bank1_ram (
        .clk_i(clk_i), .wr_en_i(dw_bank1_we_c),
        .wr_addr_i(dw_local_wr_addr_c[DW_AW-1:0]), .wr_data_i(dw_write_data_c),
        .rd_addr_i(dw_rd_addr_c), .rd_data_o(dw_bank1_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(DW_BANK_DEPTH), .ADDR_W(DW_AW), .USE_MLAB(1'b1))
    u_dw_bank2_ram (
        .clk_i(clk_i), .wr_en_i(dw_bank2_we_c),
        .wr_addr_i(dw_local_wr_addr_c[DW_AW-1:0]), .wr_data_i(dw_write_data_c),
        .rd_addr_i(dw_rd_addr_c), .rd_data_o(dw_bank2_word_r)
    );

    handseg_weight_group_ram #(.DEPTH(DW_BANK_DEPTH), .ADDR_W(DW_AW), .USE_MLAB(1'b1))
    u_dw_bank3_ram (
        .clk_i(clk_i), .wr_en_i(dw_bank3_we_c),
        .wr_addr_i(dw_local_wr_addr_c[DW_AW-1:0]), .wr_data_i(dw_write_data_c),
        .rd_addr_i(dw_rd_addr_c), .rd_data_o(dw_bank3_word_r)
    );

    // =====================================================================
    // Activation selection and 32-PE compute cluster
    // =====================================================================
    assign out_group_plus1_c = {1'b0,out_group_r} + 7'd1;
    assign out_group_plus2_c = {1'b0,out_group_r} + 7'd2;
    assign out_group_plus3_c = {1'b0,out_group_r} + 7'd3;
    assign last_group_index_c = {1'b0,cfg_r.out_groups8} - 7'd1;
    assign pair_active_c   = (out_group_plus1_c < {1'b0,cfg_r.out_groups8});
    assign third_active_c  = (out_group_plus2_c < {1'b0,cfg_r.out_groups8});
    assign fourth_active_c = (out_group_plus3_c < {1'b0,cfg_r.out_groups8});

    always_comb begin
        core0_lane_mask_c = 8'hFF;
        if ({1'b0,out_group_r} == last_group_index_c)
            core0_lane_mask_c = cfg_r.last_group_lane_mask;

        core1_lane_mask_c = 8'h00;
        if (pair_active_c) begin
            if (out_group_plus1_c == last_group_index_c)
                core1_lane_mask_c = cfg_r.last_group_lane_mask;
            else
                core1_lane_mask_c = 8'hFF;
        end

        core2_lane_mask_c = 8'h00;
        if (third_active_c) begin
            if (out_group_plus2_c == last_group_index_c)
                core2_lane_mask_c = cfg_r.last_group_lane_mask;
            else
                core2_lane_mask_c = 8'hFF;
        end

        core3_lane_mask_c = 8'h00;
        if (fourth_active_c) begin
            if (out_group_plus3_c == last_group_index_c)
                core3_lane_mask_c = cfg_r.last_group_lane_mask;
            else
                core3_lane_mask_c = 8'hFF;
        end
    end

    always_comb begin
        act0_vec_c = 64'd0;
        act1_vec_c = 64'd0;
        act2_vec_c = 64'd0;
        act3_vec_c = 64'd0;
        case (cfg_r.kind)
            LAYER_POINTWISE, LAYER_FC: begin
                act0_vec_c = {8{select_byte(act_small_q_r,step_r[2:0])}};
                act1_vec_c = act0_vec_c;
                act2_vec_c = act0_vec_c;
                act3_vec_c = act0_vec_c;
            end
            LAYER_STANDARD: begin
                act0_vec_c = {8{select_byte(act_small_q_r,std_run_chan_r)}};
                act1_vec_c = act0_vec_c;
                act2_vec_c = act0_vec_c;
                act3_vec_c = act0_vec_c;
            end
            default: begin // DEPTHWISE
                act0_vec_c = out_group_r[1] ? dw_bank2_word_r : dw_bank0_word_r;
                act1_vec_c = out_group_r[1] ? dw_bank3_word_r : dw_bank1_word_r;
                act2_vec_c = dw_bank2_word_r;
                act3_vec_c = dw_bank3_word_r;
            end
        endcase
    end

    assign core_group_ready_c = core0_mac_ready &&
                                (!pair_active_c || core1_mac_ready);
    assign core0_mac_valid_c = (state_r == S_PAIR_RUN) && core_group_ready_c;
    assign core1_mac_valid_c = (state_r == S_PAIR_RUN) && pair_active_c && core_group_ready_c;
    assign core2_mac_valid_c = 1'b0;
    assign core3_mac_valid_c = 1'b0;

    assign core0_out_ready = (state_r == S_WAIT_OUT);
    assign core1_out_ready = (state_r == S_WAIT_OUT);
    assign core2_out_ready = (state_r == S_WAIT_OUT);
    assign core3_out_ready = (state_r == S_WAIT_OUT);
    assign core0_out_fire_c = core0_out_valid && core0_out_ready;
    assign core1_out_fire_c = core1_out_valid && core1_out_ready;
    assign core2_out_fire_c = 1'b0;
    assign core3_out_fire_c = 1'b0;
    assign core0_finish_c = core0_done_r || (core0_out_fire_c && core0_out_last);
    assign core1_finish_c = (!pair_active_c) || core1_done_r ||
                            (core1_out_fire_c && core1_out_last);
    assign core2_finish_c = 1'b1;
    assign core3_finish_c = 1'b1;

    compute_core u_core0 (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .mac_valid_i(core0_mac_valid_c), .mac_ready_o(core0_mac_ready),
        .mac_start_i(step_r == 0), .mac_last_i(step_r == cfg_r.mac_steps-1),
        .activation_vec_i(act0_vec_c), .weight_vec_i(out_group_r[1] ? weight2_word_r : weight0_word_r),
        .lane_mask_i(core0_lane_mask_c),
        .multiplier_vec_i(q0_mult_c), .bias_postscale_vec_i(q0_bias_c),
        .right_shift_vec_i(q0_shift_c), .zero_point_vec_i(q0_zp_c),
        .relu_en_vec_i(q0_relu_c),
        .out_valid_o(core0_out_valid), .out_ready_i(core0_out_ready),
        .out_data_o(core0_out_data), .out_lane_o(core0_out_lane), .out_last_o(core0_out_last)
    );

    compute_core u_core1 (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .mac_valid_i(core1_mac_valid_c), .mac_ready_o(core1_mac_ready),
        .mac_start_i(step_r == 0), .mac_last_i(step_r == cfg_r.mac_steps-1),
        .activation_vec_i(act1_vec_c), .weight_vec_i(out_group_r[1] ? weight3_word_r : weight1_word_r),
        .lane_mask_i(core1_lane_mask_c),
        .multiplier_vec_i(q1_mult_c), .bias_postscale_vec_i(q1_bias_c),
        .right_shift_vec_i(q1_shift_c), .zero_point_vec_i(q1_zp_c),
        .relu_en_vec_i(q1_relu_c),
        .out_valid_o(core1_out_valid), .out_ready_i(core1_out_ready),
        .out_data_o(core1_out_data), .out_lane_o(core1_out_lane), .out_last_o(core1_out_last)
    );

    // Only two physical compute_core instances (16 MAC PEs).
    // Banks 2/3 execute on the following pass of each output quartet.

    // =====================================================================
    // Main sequencer
    // =====================================================================
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_IDLE;
            cfg_r <= '0;
            src_bank_r <= 3'd0;
            dst_bank_r <= 3'd0;
            out_x_r <= 9'd0;
            out_y_r <= 9'd0;
            row_words_r <= 17'd0;
            prep_count_r <= 6'd0;
            in_x_base_words_r <= 17'd0;
            in_y_base_words_r <= 17'd0;
            out_pixel_base_r <= 17'd0;
            w_group_r <= 6'd0;
            w_step_r <= 10'd0;
            w_ext_addr_r <= 17'd0;
            w_bank0_wr_idx_r <= '0;
            w_bank1_wr_idx_r <= '0;
            w_bank2_wr_idx_r <= '0;
            w_bank3_wr_idx_r <= '0;
            w_bank_sel_r <= 2'd0;
            q_group_r <= 6'd0;
            q_bank_sel_r <= 2'd0;
            q_slot_r <= '0;
            pw_load_group_r <= 6'd0;
            std_load_pos_r <= 4'd0;
            std_load_ky_r <= 2'd0;
            std_load_kx_r <= 2'd0;
            dw_load_group_r <= 6'd0;
            dw_load_kpos_r <= 4'd0;
            dw_load_ky_r <= 2'd0;
            dw_load_kx_r <= 2'd0;
            pair_idx_r <= 5'd0;
            out_group_r <= 6'd0;
            pair_weight_base_r <= '0;
            pair_dw_base_r <= '0;
            step_r <= 10'd0;
            std_run_chan_r <= 2'd0;
            std_run_kpos_r <= 4'd0;
            pack0_r <= 64'd0;
            pack1_r <= 64'd0;
            pack2_r <= 64'd0;
            pack3_r <= 64'd0;
            core0_done_r <= 1'b0;
            core1_done_r <= 1'b0;
            core2_done_r <= 1'b0;
            core3_done_r <= 1'b0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (start_i) begin
                        cfg_r <= cfg_i;
                        src_bank_r <= src_bank_i;
                        dst_bank_r <= dst_bank_i;
                        out_x_r <= 9'd0;
                        out_y_r <= 9'd0;
                        row_words_r <= 17'd0;
                        prep_count_r <= 6'd0;
                        in_x_base_words_r <= 17'd0;
                        in_y_base_words_r <= 17'd0;
                        out_pixel_base_r <= 17'd0;
                        w_group_r <= 6'd0;
                        w_step_r <= 10'd0;
                        w_ext_addr_r <= cfg_i.weight_base;
                        w_bank0_wr_idx_r <= '0;
                        w_bank1_wr_idx_r <= '0;
                        w_bank2_wr_idx_r <= '0;
                        w_bank3_wr_idx_r <= '0;
                        w_bank_sel_r <= 2'd0;
                        q_group_r <= 6'd0;
                        q_bank_sel_r <= 2'd0;
                        q_slot_r <= '0;
                        state_r <= S_PREP_ROWWORDS;
                    end
                end

                S_PREP_ROWWORDS: begin
                    row_words_r <= row_words_r + {8'd0,cfg_r.win};
                    if (prep_count_r == cfg_r.in_groups8-1) begin
                        prep_count_r <= 6'd0;
                        state_r <= S_WLOAD_REQ;
                    end else
                        prep_count_r <= prep_count_r + 1'b1;
                end

                // Load the complete layer weight set once.  External model
                // weights are already group-major, so separate even/odd write
                // counters naturally create two banks for the four MAC cores.
                S_WLOAD_REQ: begin
                    if (weight_req_ready_i)
                        state_r <= S_WLOAD_WAIT;
                end

                S_WLOAD_WAIT: begin
                    if (weight_rsp_valid_i) begin
                        w_ext_addr_r <= w_ext_addr_r + 1'b1;
                        case (w_bank_sel_r)
                            2'd0: w_bank0_wr_idx_r <= w_bank0_wr_idx_r + 1'b1;
                            2'd1: w_bank1_wr_idx_r <= w_bank1_wr_idx_r + 1'b1;
                            2'd2: w_bank2_wr_idx_r <= w_bank2_wr_idx_r + 1'b1;
                            default: w_bank3_wr_idx_r <= w_bank3_wr_idx_r + 1'b1;
                        endcase

                        if (w_step_r == cfg_r.mac_steps-1) begin
                            w_step_r <= 10'd0;
                            if (w_group_r == cfg_r.out_groups8-1) begin
                                q_group_r <= 6'd0;
                                q_bank_sel_r <= 2'd0;
                                q_slot_r <= '0;
                                state_r <= S_QLOAD_REQ;
                            end else begin
                                w_group_r <= w_group_r + 1'b1;
                                if (w_bank_sel_r == 2'd3)
                                    w_bank_sel_r <= 2'd0;
                                else
                                    w_bank_sel_r <= w_bank_sel_r + 1'b1;
                                state_r <= S_WLOAD_REQ;
                            end
                        end else begin
                            w_step_r <= w_step_r + 1'b1;
                            state_r <= S_WLOAD_REQ;
                        end
                    end
                end

                // Cache every qparam group once for pixel-major reuse.
                S_QLOAD_REQ: begin
                    if (qparam_req_ready_i)
                        state_r <= S_QLOAD_WAIT;
                end

                S_QLOAD_WAIT: begin
                    if (qparam_rsp_valid_i) begin
                        if (q_group_r == cfg_r.out_groups8-1)
                            state_r <= S_PIXEL_INIT;
                        else begin
                            q_group_r <= q_group_r + 1'b1;
                            if (q_bank_sel_r == 2'd3) begin
                                q_bank_sel_r <= 2'd0;
                                q_slot_r <= q_slot_r + 1'b1;
                            end else begin
                                q_bank_sel_r <= q_bank_sel_r + 1'b1;
                            end
                            state_r <= S_QLOAD_REQ;
                        end
                    end
                end

                S_PIXEL_INIT: begin
                    pair_idx_r <= 5'd0;
                    out_group_r <= 6'd0;
                    pair_weight_base_r <= '0;
                    pair_dw_base_r <= '0;
                    pack0_r <= 64'd0;
                    pack1_r <= 64'd0;
                    pack2_r <= 64'd0;
                    pack3_r <= 64'd0;
                    core0_done_r <= 1'b0;
                    core1_done_r <= 1'b0;
                    core2_done_r <= 1'b0;
                    core3_done_r <= 1'b0;
                    step_r <= 10'd0;
                    std_run_chan_r <= 2'd0;
                    std_run_kpos_r <= 4'd0;

                    if ((cfg_r.kind == LAYER_POINTWISE) ||
                        (cfg_r.kind == LAYER_FC)) begin
                        pw_load_group_r <= 6'd0;
                        state_r <= S_PW_LOAD_REQ;
                    end else if (cfg_r.kind == LAYER_STANDARD) begin
                        std_load_pos_r <= 4'd0;
                        std_load_ky_r <= 2'd0;
                        std_load_kx_r <= 2'd0;
                        state_r <= S_STD_LOAD_CHECK;
                    end else begin
                        dw_load_group_r <= 6'd0;
                        dw_load_kpos_r <= 4'd0;
                        dw_load_ky_r <= 2'd0;
                        dw_load_kx_r <= 2'd0;
                        state_r <= S_DW_LOAD_CHECK;
                    end
                end

                // POINTWISE/FC: one packed source vector is read once per
                // pixel and reused across every output group quartet.
                S_PW_LOAD_REQ: begin
                    if (mem_rd_req_ready_i)
                        state_r <= S_PW_LOAD_WAIT;
                end
                S_PW_LOAD_WAIT: begin
                    if (mem_rd_rsp_valid_i) begin
                        if (pw_load_group_r == cfg_r.in_groups8-1) begin
                            step_r <= 10'd0;
                            state_r <= S_PAIR_PREP;
                        end else begin
                            pw_load_group_r <= pw_load_group_r + 1'b1;
                            state_r <= S_PW_LOAD_REQ;
                        end
                    end
                end

                // STANDARD stem: cache the 3x3 neighborhood once.  Each word
                // contains Y/Cb/Cr in lanes 0/1/2, so all three input channels
                // reuse the same nine spatial words.
                S_STD_LOAD_CHECK: begin
                    if (std_padding_c) begin
                        if (std_load_pos_r == 4'd8) begin
                            step_r <= 10'd0;
                            std_run_chan_r <= 2'd0;
                            std_run_kpos_r <= 4'd0;
                            state_r <= S_PAIR_PREP;
                        end else begin
                            std_load_pos_r <= std_load_pos_r + 1'b1;
                            if (std_load_kx_r == 2'd2) begin
                                std_load_kx_r <= 2'd0;
                                std_load_ky_r <= std_load_ky_r + 1'b1;
                            end else
                                std_load_kx_r <= std_load_kx_r + 1'b1;
                        end
                    end else
                        state_r <= S_STD_LOAD_REQ;
                end
                S_STD_LOAD_REQ: begin
                    if (mem_rd_req_ready_i)
                        state_r <= S_STD_LOAD_WAIT;
                end
                S_STD_LOAD_WAIT: begin
                    if (mem_rd_rsp_valid_i) begin
                        if (std_load_pos_r == 4'd8) begin
                            step_r <= 10'd0;
                            std_run_chan_r <= 2'd0;
                            std_run_kpos_r <= 4'd0;
                            state_r <= S_PAIR_PREP;
                        end else begin
                            std_load_pos_r <= std_load_pos_r + 1'b1;
                            if (std_load_kx_r == 2'd2) begin
                                std_load_kx_r <= 2'd0;
                                std_load_ky_r <= std_load_ky_r + 1'b1;
                            end else
                                std_load_kx_r <= std_load_kx_r + 1'b1;
                            state_r <= S_STD_LOAD_CHECK;
                        end
                    end
                end

                // DEPTHWISE: load the entire 3x3 x group neighborhood with
                // group as the inner loop.  Adjacent group words are contiguous
                // in DDR and therefore heavily reuse each burst-4 cache line.
                S_DW_LOAD_CHECK: begin
                    if (dw_padding_c) begin
                        if (dw_load_group_r == cfg_r.out_groups8-1) begin
                            dw_load_group_r <= 6'd0;
                            if (dw_load_kpos_r == 4'd8) begin
                                step_r <= 10'd0;
                                state_r <= S_PAIR_PREP;
                            end else begin
                                dw_load_kpos_r <= dw_load_kpos_r + 1'b1;
                                if (dw_load_kx_r == 2'd2) begin
                                    dw_load_kx_r <= 2'd0;
                                    dw_load_ky_r <= dw_load_ky_r + 1'b1;
                                end else
                                    dw_load_kx_r <= dw_load_kx_r + 1'b1;
                            end
                        end else
                            dw_load_group_r <= dw_load_group_r + 1'b1;
                    end else
                        state_r <= S_DW_LOAD_REQ;
                end
                S_DW_LOAD_REQ: begin
                    if (mem_rd_req_ready_i)
                        state_r <= S_DW_LOAD_WAIT;
                end
                S_DW_LOAD_WAIT: begin
                    if (mem_rd_rsp_valid_i) begin
                        if (dw_load_group_r == cfg_r.out_groups8-1) begin
                            dw_load_group_r <= 6'd0;
                            if (dw_load_kpos_r == 4'd8) begin
                                step_r <= 10'd0;
                                state_r <= S_PAIR_PREP;
                            end else begin
                                dw_load_kpos_r <= dw_load_kpos_r + 1'b1;
                                if (dw_load_kx_r == 2'd2) begin
                                    dw_load_kx_r <= 2'd0;
                                    dw_load_ky_r <= dw_load_ky_r + 1'b1;
                                end else
                                    dw_load_kx_r <= dw_load_kx_r + 1'b1;
                                state_r <= S_DW_LOAD_CHECK;
                            end
                        end else begin
                            dw_load_group_r <= dw_load_group_r + 1'b1;
                            state_r <= S_DW_LOAD_CHECK;
                        end
                    end
                end

                // One setup cycle primes synchronous weight/qparam/DW RAMs.
                S_PAIR_PREP: begin
                    step_r <= 10'd0;
                    std_run_chan_r <= 2'd0;
                    std_run_kpos_r <= 4'd0;
                    pack0_r <= 64'd0;
                    pack1_r <= 64'd0;
                    pack2_r <= 64'd0;
                    pack3_r <= 64'd0;
                    core0_done_r <= 1'b0;
                    core1_done_r <= 1'b0;
                    core2_done_r <= 1'b0;
                    core3_done_r <= 1'b0;
                    state_r <= S_PAIR_RUN;
                end

                // Hot loop: all operands are local.  One accepted MAC step per
                // clock is possible with no feature/weight/qparam DDR wait.
                S_PAIR_RUN: begin
                    if (core_group_ready_c) begin
                        if (step_r == cfg_r.mac_steps-1)
                            state_r <= S_WAIT_OUT;
                        else begin
                            step_r <= step_r + 1'b1;
                            if (cfg_r.kind == LAYER_STANDARD) begin
                                if (std_run_kpos_r == 4'd8) begin
                                    std_run_kpos_r <= 4'd0;
                                    std_run_chan_r <= std_run_chan_r + 1'b1;
                                end else
                                    std_run_kpos_r <= std_run_kpos_r + 1'b1;
                            end
                        end
                    end
                end

                S_WAIT_OUT: begin
                    if (core0_out_fire_c) begin
                        pack0_r <= insert_byte(pack0_r,core0_out_lane,core0_out_data);
                        if (core0_out_last)
                            core0_done_r <= 1'b1;
                    end
                    if (core1_out_fire_c) begin
                        pack1_r <= insert_byte(pack1_r,core1_out_lane,core1_out_data);
                        if (core1_out_last)
                            core1_done_r <= 1'b1;
                    end
                    if (core0_finish_c && core1_finish_c)
                        state_r <= S_WRITE0;
                end

                S_WRITE0: begin
                    if (mem_wr_ready_i)
                        state_r <= pair_active_c ? S_WRITE1 : S_PAIR_NEXT;
                end
                S_WRITE1: begin
                    if (mem_wr_ready_i)
                        state_r <= S_PAIR_NEXT;
                end
                S_WRITE2: begin
                    if (mem_wr_ready_i)
                        state_r <= fourth_active_c ? S_WRITE3 : S_PAIR_NEXT;
                end
                S_WRITE3: begin
                    if (mem_wr_ready_i)
                        state_r <= S_PAIR_NEXT;
                end

                S_PAIR_NEXT: begin
                    if (({1'b0,out_group_r} + 7'd2) >= {1'b0,cfg_r.out_groups8})
                        state_r <= S_PIXEL_NEXT;
                    else begin
                        pair_idx_r <= pair_idx_r + 1'b1;
                        out_group_r <= out_group_r + 6'd2;
                        // Quartet caches retain four interleaved banks. Advance
                        // the shared read address only after both 16-PE passes.
                        if (out_group_r[1]) begin
                            pair_weight_base_r <= pair_weight_base_r +
                                                  {2'd0,cfg_r.mac_steps};
                            pair_dw_base_r <= pair_dw_base_r + 8'd9;
                        end
                        step_r <= 10'd0;
                        state_r <= S_PAIR_PREP;
                    end
                end

                S_PIXEL_NEXT: begin
                    out_pixel_base_r <= out_pixel_base_r + {11'd0,cfg_r.out_groups8};
                    if (out_x_r == cfg_r.wout-1) begin
                        out_x_r <= 9'd0;
                        in_x_base_words_r <= 17'd0;
                        if (out_y_r == cfg_r.hout-1) begin
                            out_y_r <= 9'd0;
                            in_y_base_words_r <= 17'd0;
                            state_r <= S_DONE;
                        end else begin
                            out_y_r <= out_y_r + 1'b1;
                            in_y_base_words_r <= in_y_base_words_r + y_stride_words_c;
                            state_r <= S_PIXEL_INIT;
                        end
                    end else begin
                        out_x_r <= out_x_r + 1'b1;
                        in_x_base_words_r <= in_x_base_words_r + x_stride_words_c;
                        state_r <= S_PIXEL_INIT;
                    end
                end

                S_DONE: state_r <= S_IDLE;
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
