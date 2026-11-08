module handseg_ddr_memory_subsystem (
    input  logic clk_i,
    input  logic rstn_i,

    // Feature-map interface used by all existing compute engines.
    input  logic        rd0_req_valid_i,
    output logic        rd0_req_ready_o,
    input  logic [2:0]  rd0_req_bank_i,
    input  logic [16:0] rd0_req_addr_i,
    output logic        rd0_rsp_valid_o,
    input  logic        rd0_rsp_ready_i,
    output logic [63:0] rd0_rsp_data_o,

    input  logic        rd1_req_valid_i,
    output logic        rd1_req_ready_o,
    input  logic [2:0]  rd1_req_bank_i,
    input  logic [16:0] rd1_req_addr_i,
    output logic        rd1_rsp_valid_o,
    input  logic        rd1_rsp_ready_i,
    output logic [63:0] rd1_rsp_data_o,

    input  logic        wr_valid_i,
    output logic        wr_ready_o,
    input  logic [2:0]  wr_bank_i,
    input  logic [16:0] wr_addr_i,
    input  logic [63:0] wr_data_i,

    // Parameter interface is identical to parameter_store_v141.
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

    // Single ordered AI DDR master request interface.
    output logic        ddr_rd_req_valid_o,
    input  logic        ddr_rd_req_ready_i,
    output logic [31:0] ddr_rd_req_addr_o,
    input  logic        ddr_rd_rsp_valid_i,
    output logic        ddr_rd_rsp_ready_o,
    input  logic [63:0] ddr_rd_rsp_data_i,

    output logic        ddr_wr_req_valid_o,
    input  logic        ddr_wr_req_ready_i,
    output logic [31:0] ddr_wr_req_addr_o,
    output logic [63:0] ddr_wr_req_data_o
);

    logic feat_rd_req_v, feat_rd_req_r;
    logic [31:0] feat_rd_req_a;
    logic feat_rd_rsp_v, feat_rd_rsp_r;
    logic [63:0] feat_rd_rsp_d;

    logic par_rd_req_v, par_rd_req_r;
    logic [31:0] par_rd_req_a;
    logic par_rd_rsp_v, par_rd_rsp_r;
    logic [63:0] par_rd_rsp_d;

    handseg_ddr_feature_memory u_feat (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .rd0_req_valid_i(rd0_req_valid_i), .rd0_req_ready_o(rd0_req_ready_o),
        .rd0_req_bank_i(rd0_req_bank_i), .rd0_req_addr_i(rd0_req_addr_i),
        .rd0_rsp_valid_o(rd0_rsp_valid_o), .rd0_rsp_ready_i(rd0_rsp_ready_i), .rd0_rsp_data_o(rd0_rsp_data_o),
        .rd1_req_valid_i(rd1_req_valid_i), .rd1_req_ready_o(rd1_req_ready_o),
        .rd1_req_bank_i(rd1_req_bank_i), .rd1_req_addr_i(rd1_req_addr_i),
        .rd1_rsp_valid_o(rd1_rsp_valid_o), .rd1_rsp_ready_i(rd1_rsp_ready_i), .rd1_rsp_data_o(rd1_rsp_data_o),
        .wr_valid_i(wr_valid_i), .wr_ready_o(wr_ready_o), .wr_bank_i(wr_bank_i), .wr_addr_i(wr_addr_i), .wr_data_i(wr_data_i),
        .ddr_rd_req_valid_o(feat_rd_req_v), .ddr_rd_req_ready_i(feat_rd_req_r), .ddr_rd_req_addr_o(feat_rd_req_a),
        .ddr_rd_rsp_valid_i(feat_rd_rsp_v), .ddr_rd_rsp_ready_o(feat_rd_rsp_r), .ddr_rd_rsp_data_i(feat_rd_rsp_d),
        .ddr_wr_req_valid_o(ddr_wr_req_valid_o), .ddr_wr_req_ready_i(ddr_wr_req_ready_i),
        .ddr_wr_req_addr_o(ddr_wr_req_addr_o), .ddr_wr_req_data_o(ddr_wr_req_data_o)
    );

    parameter_store_ddr_v141 u_param (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .weight_req_valid_i(weight_req_valid_i), .weight_req_ready_o(weight_req_ready_o), .weight_req_addr_i(weight_req_addr_i),
        .weight_rsp_valid_o(weight_rsp_valid_o), .weight_rsp_ready_i(weight_rsp_ready_i), .weight_rsp_data_o(weight_rsp_data_o),
        .qparam_req_valid_i(qparam_req_valid_i), .qparam_req_ready_o(qparam_req_ready_o), .qparam_req_addr_i(qparam_req_addr_i),
        .qparam_rsp_valid_o(qparam_rsp_valid_o), .qparam_rsp_ready_i(qparam_rsp_ready_i),
        .multiplier_vec_o(multiplier_vec_o), .bias_postscale_vec_o(bias_postscale_vec_o),
        .right_shift_vec_o(right_shift_vec_o), .zero_point_vec_o(zero_point_vec_o), .relu_en_vec_o(relu_en_vec_o),
        .params_ready_o(params_ready_o),
        .ddr_rd_req_valid_o(par_rd_req_v), .ddr_rd_req_ready_i(par_rd_req_r), .ddr_rd_req_addr_o(par_rd_req_a),
        .ddr_rd_rsp_valid_i(par_rd_rsp_v), .ddr_rd_rsp_ready_o(par_rd_rsp_r), .ddr_rd_rsp_data_i(par_rd_rsp_d)
    );

    handseg_simple_read_arbiter u_rd_arb (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .c0_req_valid_i(feat_rd_req_v), .c0_req_ready_o(feat_rd_req_r), .c0_req_addr_i(feat_rd_req_a),
        .c0_rsp_valid_o(feat_rd_rsp_v), .c0_rsp_ready_i(feat_rd_rsp_r), .c0_rsp_data_o(feat_rd_rsp_d),
        .c1_req_valid_i(par_rd_req_v), .c1_req_ready_o(par_rd_req_r), .c1_req_addr_i(par_rd_req_a),
        .c1_rsp_valid_o(par_rd_rsp_v), .c1_rsp_ready_i(par_rd_rsp_r), .c1_rsp_data_o(par_rd_rsp_d),
        .m_req_valid_o(ddr_rd_req_valid_o), .m_req_ready_i(ddr_rd_req_ready_i), .m_req_addr_o(ddr_rd_req_addr_o),
        .m_rsp_valid_i(ddr_rd_rsp_valid_i), .m_rsp_ready_o(ddr_rd_rsp_ready_o), .m_rsp_data_i(ddr_rd_rsp_data_i)
    );

endmodule
