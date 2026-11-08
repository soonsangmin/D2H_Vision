module handseg_live_top #(
    parameter integer USE_EXTERNAL_DDR = 0
)(
    input  logic        clk_i,
    input  logic        rstn_i,

    // One complete 320x256 YCbCr frame is streamed in this clock domain.
    input  logic        frame_start_i,
    input  logic        pixel_valid_i,
    output logic        pixel_ready_o,
    input  logic [23:0] pixel_ycbcr_i,

    // Ordered 64-bit DDR transaction interface. In the Quartus top this is
    // connected to the existing HPS F2H SDRAM port through a small arbiter.
    output logic        ddr_rd_req_valid_o,
    input  logic        ddr_rd_req_ready_i,
    output logic [31:0] ddr_rd_req_addr_o,
    input  logic        ddr_rd_rsp_valid_i,
    output logic        ddr_rd_rsp_ready_o,
    input  logic [63:0] ddr_rd_rsp_data_i,

    output logic        ddr_wr_req_valid_o,
    input  logic        ddr_wr_req_ready_i,
    output logic [31:0] ddr_wr_req_addr_o,
    output logic [63:0] ddr_wr_req_data_o,

    output logic        params_ready_o,
    output logic        busy_o,
    output logic        inference_done_o,
    output logic        roi_update_o,

    output logic        presence_keep_o,
    output logic [7:0]  presence_q_o,

    // Raw mask-grid ROI, 80x64 coordinates.
    output logic        roi_valid_o,
    output logic [12:0] positive_cells_o,
    output logic [6:0]  xmin_o,
    output logic [5:0]  ymin_o,
    output logic [6:0]  xmax_o,
    output logic [5:0]  ymax_o,

    output logic [6:0]  current_pc_o
);

    import handseg_config_pkg::*;

    localparam integer INPUT_WORDS = 320 * 256;

    // ========================================================================
    // NETWORK DESCRIPTORS
    // ========================================================================

    logic [6:0] pc_r;
    network_cmd_t  cmd;
    layer_cfg_t    layer_cfg;
    residual_cfg_t residual_cfg;
    concat_cfg_t   concat_cfg;

    network_schedule_rom u_sched (
        .pc_i  (pc_r),
        .cmd_o (cmd)
    );

    layer_descriptor_rom u_lrom (
        .layer_id_i (cmd.id),
        .cfg_o      (layer_cfg)
    );

    residual_descriptor_rom u_rrom (
        .residual_id_i (cmd.id[3:0]),
        .cfg_o         (residual_cfg)
    );

    concat_descriptor_rom u_crom (
        .concat_id_i (cmd.id[1:0]),
        .cfg_o       (concat_cfg)
    );

    assign current_pc_o = pc_r;

    // ========================================================================
    // INPUT FRAME LOADER
    //
    // Packing is identical to model_input_packer.sv:
    //   lane0 = Y
    //   lane1 = Cb
    //   lane2 = Cr
    //   lanes3..7 = 0
    // ========================================================================

    logic        load_active_r;
    logic [16:0] load_addr_r;

    logic active_r;
    logic launch_r;
    logic engine_done;

    assign busy_o = load_active_r | active_r;

    // ========================================================================
    // MEMORY BUSES AFTER MUX
    // ========================================================================

    logic        m_rd0_v;
    logic        m_rd0_r;
    logic [2:0]  m_rd0_b;
    logic [16:0] m_rd0_a;
    logic        m_rd0_rsp_v;
    logic        m_rd0_rsp_r;
    logic [63:0] m_rd0_d;

    logic        m_rd1_v;
    logic        m_rd1_r;
    logic [2:0]  m_rd1_b;
    logic [16:0] m_rd1_a;
    logic        m_rd1_rsp_v;
    logic        m_rd1_rsp_r;
    logic [63:0] m_rd1_d;

    logic        m_wr_v;
    logic        m_wr_r;
    logic [2:0]  m_wr_b;
    logic [16:0] m_wr_a;
    logic [63:0] m_wr_d;

    assign pixel_ready_o = load_active_r && !active_r && m_wr_r;

    // ========================================================================
    // PARAMETER STORE
    // ========================================================================

    logic        pw_req_v;
    logic        pw_req_r;
    logic [16:0] pw_req_a;
    logic        pw_rsp_v;
    logic        pw_rsp_r;
    logic [63:0] pw_d;

    logic         pq_req_v;
    logic         pq_req_r;
    logic [10:0]  pq_req_a;
    logic         pq_rsp_v;
    logic         pq_rsp_r;
    logic [255:0] p_mult;
    logic [511:0] p_bias;
    logic [63:0]  p_shift;
    logic [63:0]  p_zp;
    logic [7:0]   p_relu;

    // ========================================================================
    // MEMORY / PARAMETER BACKEND
    //
    // Simulation keeps the already validated full-buffer memories. Quartus
    // sets USE_EXTERNAL_DDR=1, which removes those huge arrays completely and
    // stores feature maps + model parameters in HPS DDR. A 4-KiB weight tile
    // cache inside parameter_store_ddr_v141 preserves the important reuse.
    // ========================================================================

    generate
        if (USE_EXTERNAL_DDR != 0) begin : g_external_ddr
            handseg_ddr_memory_subsystem u_ddr_mem (
                .clk_i(clk_i), .rstn_i(rstn_i),

                .rd0_req_valid_i(m_rd0_v), .rd0_req_ready_o(m_rd0_r),
                .rd0_req_bank_i(m_rd0_b), .rd0_req_addr_i(m_rd0_a),
                .rd0_rsp_valid_o(m_rd0_rsp_v), .rd0_rsp_ready_i(m_rd0_rsp_r), .rd0_rsp_data_o(m_rd0_d),

                .rd1_req_valid_i(m_rd1_v), .rd1_req_ready_o(m_rd1_r),
                .rd1_req_bank_i(m_rd1_b), .rd1_req_addr_i(m_rd1_a),
                .rd1_rsp_valid_o(m_rd1_rsp_v), .rd1_rsp_ready_i(m_rd1_rsp_r), .rd1_rsp_data_o(m_rd1_d),

                .wr_valid_i(m_wr_v), .wr_ready_o(m_wr_r), .wr_bank_i(m_wr_b), .wr_addr_i(m_wr_a), .wr_data_i(m_wr_d),

                .weight_req_valid_i(pw_req_v), .weight_req_ready_o(pw_req_r), .weight_req_addr_i(pw_req_a),
                .weight_rsp_valid_o(pw_rsp_v), .weight_rsp_ready_i(pw_rsp_r), .weight_rsp_data_o(pw_d),

                .qparam_req_valid_i(pq_req_v), .qparam_req_ready_o(pq_req_r), .qparam_req_addr_i(pq_req_a),
                .qparam_rsp_valid_o(pq_rsp_v), .qparam_rsp_ready_i(pq_rsp_r),
                .multiplier_vec_o(p_mult), .bias_postscale_vec_o(p_bias), .right_shift_vec_o(p_shift),
                .zero_point_vec_o(p_zp), .relu_en_vec_o(p_relu), .params_ready_o(params_ready_o),

                .ddr_rd_req_valid_o(ddr_rd_req_valid_o), .ddr_rd_req_ready_i(ddr_rd_req_ready_i),
                .ddr_rd_req_addr_o(ddr_rd_req_addr_o), .ddr_rd_rsp_valid_i(ddr_rd_rsp_valid_i),
                .ddr_rd_rsp_ready_o(ddr_rd_rsp_ready_o), .ddr_rd_rsp_data_i(ddr_rd_rsp_data_i),

                .ddr_wr_req_valid_o(ddr_wr_req_valid_o), .ddr_wr_req_ready_i(ddr_wr_req_ready_i),
                .ddr_wr_req_addr_o(ddr_wr_req_addr_o), .ddr_wr_req_data_o(ddr_wr_req_data_o)
            );
        end
        else begin : g_reference_mem
            reference_feature_memory #(.BANK0_INIT_FILE("")) u_mem (
                .clk_i(clk_i), .rstn_i(rstn_i),
                .rd0_req_valid_i(m_rd0_v), .rd0_req_ready_o(m_rd0_r), .rd0_req_bank_i(m_rd0_b), .rd0_req_addr_i(m_rd0_a),
                .rd0_rsp_valid_o(m_rd0_rsp_v), .rd0_rsp_ready_i(m_rd0_rsp_r), .rd0_rsp_data_o(m_rd0_d),
                .rd1_req_valid_i(m_rd1_v), .rd1_req_ready_o(m_rd1_r), .rd1_req_bank_i(m_rd1_b), .rd1_req_addr_i(m_rd1_a),
                .rd1_rsp_valid_o(m_rd1_rsp_v), .rd1_rsp_ready_i(m_rd1_rsp_r), .rd1_rsp_data_o(m_rd1_d),
                .wr_valid_i(m_wr_v), .wr_ready_o(m_wr_r), .wr_bank_i(m_wr_b), .wr_addr_i(m_wr_a), .wr_data_i(m_wr_d)
            );

            parameter_store_v141 u_params (
                .clk_i(clk_i), .rstn_i(rstn_i),
                .weight_req_valid_i(pw_req_v), .weight_req_ready_o(pw_req_r), .weight_req_addr_i(pw_req_a),
                .weight_rsp_valid_o(pw_rsp_v), .weight_rsp_ready_i(pw_rsp_r), .weight_rsp_data_o(pw_d),
                .qparam_req_valid_i(pq_req_v), .qparam_req_ready_o(pq_req_r), .qparam_req_addr_i(pq_req_a),
                .qparam_rsp_valid_o(pq_rsp_v), .qparam_rsp_ready_i(pq_rsp_r),
                .multiplier_vec_o(p_mult), .bias_postscale_vec_o(p_bias), .right_shift_vec_o(p_shift),
                .zero_point_vec_o(p_zp), .relu_en_vec_o(p_relu)
            );

            assign params_ready_o       = 1'b1;
            assign ddr_rd_req_valid_o   = 1'b0;
            assign ddr_rd_req_addr_o    = 32'd0;
            assign ddr_rd_rsp_ready_o   = 1'b0;
            assign ddr_wr_req_valid_o   = 1'b0;
            assign ddr_wr_req_addr_o    = 32'd0;
            assign ddr_wr_req_data_o    = 64'd0;
        end
    endgenerate

    // ========================================================================
    // CONV ENGINE
    // ========================================================================

    logic        cv_start;
    logic        cv_done;
    logic        cv_busy;
    logic        cv_rv;
    logic        cv_rspr;
    logic [2:0]  cv_rb;
    logic [16:0] cv_ra;
    logic        cv_wv;
    logic [2:0]  cv_wb;
    logic [16:0] cv_wa;
    logic [63:0] cv_wd;

    conv_layer_engine u_conv (
        .clk_i                  (clk_i),
        .rstn_i                 (rstn_i),
        .start_i                (cv_start),
        .cfg_i                  (layer_cfg),
        .src_bank_i             (cmd.src0_bank),
        .dst_bank_i             (cmd.dst_bank),
        .busy_o                 (cv_busy),
        .done_o                 (cv_done),

        .mem_rd_req_valid_o     (cv_rv),
        .mem_rd_req_ready_i     (m_rd0_r),
        .mem_rd_req_bank_o      (cv_rb),
        .mem_rd_req_addr_o      (cv_ra),
        .mem_rd_rsp_valid_i     (m_rd0_rsp_v),
        .mem_rd_rsp_ready_o     (cv_rspr),
        .mem_rd_rsp_data_i      (m_rd0_d),

        .mem_wr_valid_o         (cv_wv),
        .mem_wr_ready_i         (m_wr_r),
        .mem_wr_bank_o          (cv_wb),
        .mem_wr_addr_o          (cv_wa),
        .mem_wr_data_o          (cv_wd),

        .weight_req_valid_o     (pw_req_v),
        .weight_req_ready_i     (pw_req_r),
        .weight_req_addr_o      (pw_req_a),
        .weight_rsp_valid_i     (pw_rsp_v),
        .weight_rsp_ready_o     (pw_rsp_r),
        .weight_rsp_data_i      (pw_d),

        .qparam_req_valid_o     (pq_req_v),
        .qparam_req_ready_i     (pq_req_r),
        .qparam_req_addr_o      (pq_req_a),
        .qparam_rsp_valid_i     (pq_rsp_v),
        .qparam_rsp_ready_o     (pq_rsp_r),
        .multiplier_vec_i       (p_mult),
        .bias_vec_i             (p_bias),
        .shift_vec_i            (p_shift),
        .zp_vec_i               (p_zp),
        .relu_vec_i             (p_relu)
    );

    // ========================================================================
    // RESIDUAL ENGINE
    // ========================================================================

    logic        rs_start;
    logic        rs_done;
    logic        rs_r0v;
    logic        rs_r0rsp_r;
    logic [2:0]  rs_r0b;
    logic [16:0] rs_r0a;
    logic        rs_r1v;
    logic        rs_r1rsp_r;
    logic [2:0]  rs_r1b;
    logic [16:0] rs_r1a;
    logic        rs_wv;
    logic [2:0]  rs_wb;
    logic [16:0] rs_wa;
    logic [63:0] rs_wd;

    residual_word_engine u_reseng (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),
        .start_i            (rs_start),
        .cfg_i              (residual_cfg),
        .main_bank_i        (cmd.src0_bank),
        .shortcut_bank_i    (cmd.src1_bank),
        .dst_bank_i         (cmd.dst_bank),
        .word_count_i       (cmd.word_count),
        .busy_o             (),
        .done_o             (rs_done),

        .rd0_req_valid_o    (rs_r0v),
        .rd0_req_ready_i    (m_rd0_r),
        .rd0_req_bank_o     (rs_r0b),
        .rd0_req_addr_o     (rs_r0a),
        .rd0_rsp_valid_i    (m_rd0_rsp_v),
        .rd0_rsp_ready_o    (rs_r0rsp_r),
        .rd0_rsp_data_i     (m_rd0_d),

        .rd1_req_valid_o    (rs_r1v),
        .rd1_req_ready_i    (m_rd1_r),
        .rd1_req_bank_o     (rs_r1b),
        .rd1_req_addr_o     (rs_r1a),
        .rd1_rsp_valid_i    (m_rd1_rsp_v),
        .rd1_rsp_ready_o    (rs_r1rsp_r),
        .rd1_rsp_data_i     (m_rd1_d),

        .wr_valid_o         (rs_wv),
        .wr_ready_i         (m_wr_r),
        .wr_bank_o          (rs_wb),
        .wr_addr_o          (rs_wa),
        .wr_data_o          (rs_wd)
    );

    // ========================================================================
    // CONCAT / UPSAMPLE ENGINE
    // ========================================================================

    logic        cc_start;
    logic        cc_done;
    logic        cc_rv;
    logic        cc_rspr;
    logic [2:0]  cc_rb;
    logic [16:0] cc_ra;
    logic        cc_wv;
    logic [2:0]  cc_wb;
    logic [16:0] cc_wa;
    logic [63:0] cc_wd;

    concat_upsample_engine u_concat (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),
        .start_i            (cc_start),
        .cfg_i              (concat_cfg),
        .feature_bank_i     (cmd.src0_bank),
        .skip_bank_i        (cmd.src1_bank),
        .dst_bank_i         (cmd.dst_bank),
        .busy_o             (),
        .done_o             (cc_done),
        .rd_req_valid_o     (cc_rv),
        .rd_req_ready_i     (m_rd0_r),
        .rd_req_bank_o      (cc_rb),
        .rd_req_addr_o      (cc_ra),
        .rd_rsp_valid_i     (m_rd0_rsp_v),
        .rd_rsp_ready_o     (cc_rspr),
        .rd_rsp_data_i      (m_rd0_d),
        .wr_valid_o         (cc_wv),
        .wr_ready_i         (m_wr_r),
        .wr_bank_o          (cc_wb),
        .wr_addr_o          (cc_wa),
        .wr_data_o          (cc_wd)
    );

    // ========================================================================
    // PRESENCE GAP
    // ========================================================================

    logic        gp_start;
    logic        gp_done;
    logic        gp_rv;
    logic        gp_rspr;
    logic [2:0]  gp_rb;
    logic [16:0] gp_ra;
    logic        gp_wv;
    logic [2:0]  gp_wb;
    logic [16:0] gp_wa;
    logic [63:0] gp_wd;

    presence_gap_engine u_gap (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),
        .start_i            (gp_start),
        .src_bank_i         (cmd.src0_bank),
        .dst_bank_i         (cmd.dst_bank),
        .busy_o             (),
        .done_o             (gp_done),
        .rd_req_valid_o     (gp_rv),
        .rd_req_ready_i     (m_rd0_r),
        .rd_req_bank_o      (gp_rb),
        .rd_req_addr_o      (gp_ra),
        .rd_rsp_valid_i     (m_rd0_rsp_v),
        .rd_rsp_ready_o     (gp_rspr),
        .rd_rsp_data_i      (m_rd0_d),
        .wr_valid_o         (gp_wv),
        .wr_ready_i         (m_wr_r),
        .wr_bank_o          (gp_wb),
        .wr_addr_o          (gp_wa),
        .wr_data_o          (gp_wd)
    );

    // ========================================================================
    // PRESENCE CHECK
    // ========================================================================

    logic        ps_start;
    logic        ps_done;
    logic        ps_rv;
    logic        ps_rspr;
    logic [2:0]  ps_rb;
    logic [16:0] ps_ra;
    logic        ps_keep;
    logic [7:0]  ps_q;

    presence_check_engine u_pres (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),
        .start_i            (ps_start),
        .src_bank_i         (cmd.src0_bank),
        .busy_o             (),
        .done_o             (ps_done),
        .keep_o             (ps_keep),
        .presence_q_o       (ps_q),
        .rd_req_valid_o     (ps_rv),
        .rd_req_ready_i     (m_rd0_r),
        .rd_req_bank_o      (ps_rb),
        .rd_req_addr_o      (ps_ra),
        .rd_rsp_valid_i     (m_rd0_rsp_v),
        .rd_rsp_ready_o     (ps_rspr),
        .rd_rsp_data_i      (m_rd0_d)
    );

    // ========================================================================
    // MASK -> RAW ROI
    // ========================================================================

    logic        ro_start;
    logic        ro_done;
    logic        ro_rv;
    logic        ro_rspr;
    logic [2:0]  ro_rb;
    logic [16:0] ro_ra;

    logic        ro_roi_valid;
    logic [12:0] ro_positive_cells;
    logic [6:0]  ro_xmin;
    logic [5:0]  ro_ymin;
    logic [6:0]  ro_xmax;
    logic [5:0]  ro_ymax;

    mask_roi_engine u_roi (
        .clk_i              (clk_i),
        .rstn_i             (rstn_i),
        .start_i            (ro_start),
        .src_bank_i         (cmd.src0_bank),
        .busy_o             (),
        .done_o             (ro_done),
        .roi_valid_o        (ro_roi_valid),
        .positive_cells_o   (ro_positive_cells),
        .xmin_o             (ro_xmin),
        .ymin_o             (ro_ymin),
        .xmax_o             (ro_xmax),
        .ymax_o             (ro_ymax),
        .rd_req_valid_o     (ro_rv),
        .rd_req_ready_i     (m_rd0_r),
        .rd_req_bank_o      (ro_rb),
        .rd_req_addr_o      (ro_ra),
        .rd_rsp_valid_i     (m_rd0_rsp_v),
        .rd_rsp_ready_o     (ro_rspr),
        .rd_rsp_data_i      (m_rd0_d)
    );

    // ========================================================================
    // ENGINE + MEMORY MUX
    // ========================================================================

    always_comb begin
        cv_start = 1'b0;
        rs_start = 1'b0;
        cc_start = 1'b0;
        gp_start = 1'b0;
        ps_start = 1'b0;
        ro_start = 1'b0;
        engine_done = 1'b0;

        m_rd0_v     = 1'b0;
        m_rd0_b     = BANK_A;
        m_rd0_a     = 17'd0;
        m_rd0_rsp_r = 1'b0;

        m_rd1_v     = 1'b0;
        m_rd1_b     = BANK_A;
        m_rd1_a     = 17'd0;
        m_rd1_rsp_r = 1'b0;

        m_wr_v = 1'b0;
        m_wr_b = BANK_A;
        m_wr_a = 17'd0;
        m_wr_d = 64'd0;

        // Input frame loader owns the write port while the network is idle.
        if (load_active_r && !active_r) begin
            m_wr_v = pixel_valid_i && pixel_ready_o;
            m_wr_b = BANK_A;
            m_wr_a = load_addr_r;
            m_wr_d = {
                40'd0,
                pixel_ycbcr_i[7:0],
                pixel_ycbcr_i[15:8],
                pixel_ycbcr_i[23:16]
            };
        end
        else begin
            case (cmd.op)
                CMD_CONV: begin
                    cv_start     = launch_r;
                    m_rd0_v     = cv_rv;
                    m_rd0_b     = cv_rb;
                    m_rd0_a     = cv_ra;
                    m_rd0_rsp_r = cv_rspr;
                    m_wr_v      = cv_wv;
                    m_wr_b      = cv_wb;
                    m_wr_a      = cv_wa;
                    m_wr_d      = cv_wd;
                    engine_done = cv_done;
                end

                CMD_RESIDUAL: begin
                    rs_start     = launch_r;
                    m_rd0_v     = rs_r0v;
                    m_rd0_b     = rs_r0b;
                    m_rd0_a     = rs_r0a;
                    m_rd0_rsp_r = rs_r0rsp_r;
                    m_rd1_v     = rs_r1v;
                    m_rd1_b     = rs_r1b;
                    m_rd1_a     = rs_r1a;
                    m_rd1_rsp_r = rs_r1rsp_r;
                    m_wr_v      = rs_wv;
                    m_wr_b      = rs_wb;
                    m_wr_a      = rs_wa;
                    m_wr_d      = rs_wd;
                    engine_done = rs_done;
                end

                CMD_CONCAT: begin
                    cc_start     = launch_r;
                    m_rd0_v     = cc_rv;
                    m_rd0_b     = cc_rb;
                    m_rd0_a     = cc_ra;
                    m_rd0_rsp_r = cc_rspr;
                    m_wr_v      = cc_wv;
                    m_wr_b      = cc_wb;
                    m_wr_a      = cc_wa;
                    m_wr_d      = cc_wd;
                    engine_done = cc_done;
                end

                CMD_GAP: begin
                    gp_start     = launch_r;
                    m_rd0_v     = gp_rv;
                    m_rd0_b     = gp_rb;
                    m_rd0_a     = gp_ra;
                    m_rd0_rsp_r = gp_rspr;
                    m_wr_v      = gp_wv;
                    m_wr_b      = gp_wb;
                    m_wr_a      = gp_wa;
                    m_wr_d      = gp_wd;
                    engine_done = gp_done;
                end

                CMD_PRESENCE: begin
                    ps_start     = launch_r;
                    m_rd0_v     = ps_rv;
                    m_rd0_b     = ps_rb;
                    m_rd0_a     = ps_ra;
                    m_rd0_rsp_r = ps_rspr;
                    engine_done = ps_done;
                end

                CMD_ROI: begin
                    ro_start     = launch_r;
                    m_rd0_v     = ro_rv;
                    m_rd0_b     = ro_rb;
                    m_rd0_a     = ro_ra;
                    m_rd0_rsp_r = ro_rspr;
                    engine_done = ro_done;
                end

                default: begin
                    engine_done = 1'b0;
                end
            endcase
        end
    end

    // ========================================================================
    // FRAME LOAD + NETWORK CONTROL
    // ========================================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            load_active_r     <= 1'b0;
            load_addr_r       <= 17'd0;
            active_r          <= 1'b0;
            pc_r              <= 7'd0;
            launch_r          <= 1'b0;

            inference_done_o  <= 1'b0;
            roi_update_o      <= 1'b0;

            presence_keep_o   <= 1'b0;
            presence_q_o      <= 8'd0;

            roi_valid_o       <= 1'b0;
            positive_cells_o  <= 13'd0;
            xmin_o            <= 7'd0;
            ymin_o            <= 6'd0;
            xmax_o            <= 7'd0;
            ymax_o            <= 6'd0;
        end
        else begin
            launch_r         <= 1'b0;
            inference_done_o <= 1'b0;
            roi_update_o     <= 1'b0;

            // Accept a new model-input frame only while completely idle.
            if (frame_start_i && params_ready_o && !load_active_r && !active_r) begin
                load_active_r <= 1'b1;
                load_addr_r   <= 17'd0;
            end

            // Load 81920 packed words into BANK_A.
            if (load_active_r && pixel_valid_i && pixel_ready_o) begin
                if (load_addr_r == INPUT_WORDS-1) begin
                    load_active_r <= 1'b0;
                    load_addr_r   <= 17'd0;

                    // Start the complete network on the next cycle.
                    active_r <= 1'b1;
                    pc_r     <= 7'd0;
                    launch_r <= 1'b1;
                end
                else begin
                    load_addr_r <= load_addr_r + 1'b1;
                end
            end

            if (active_r) begin
                // Normal successful end after mask ROI.
                if (cmd.op == CMD_DONE) begin
                    active_r         <= 1'b0;
                    inference_done_o <= 1'b1;
                    roi_update_o     <= 1'b1;

                    roi_valid_o      <= ro_roi_valid;
                    positive_cells_o <= ro_positive_cells;
                    xmin_o           <= ro_xmin;
                    ymin_o           <= ro_ymin;
                    xmax_o           <= ro_xmax;
                    ymax_o           <= ro_ymax;
                end

                else if (engine_done) begin
                    if (cmd.op == CMD_PRESENCE) begin
                        presence_keep_o <= ps_keep;
                        presence_q_o    <= ps_q;

                        // Early reject: publish an invalid ROI and release camera.
                        if (!ps_keep) begin
                            active_r         <= 1'b0;
                            inference_done_o <= 1'b1;
                            roi_update_o     <= 1'b1;

                            roi_valid_o      <= 1'b0;
                            positive_cells_o <= 13'd0;
                            xmin_o           <= 7'd0;
                            ymin_o           <= 6'd0;
                            xmax_o           <= 7'd0;
                            ymax_o           <= 6'd0;
                        end
                        else begin
                            pc_r     <= pc_r + 1'b1;
                            launch_r <= 1'b1;
                        end
                    end
                    else begin
                        pc_r     <= pc_r + 1'b1;
                        launch_r <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
