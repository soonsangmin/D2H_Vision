module handseg_reference_top #(
    parameter INPUT_HEX = "golden/stage_hex/02_model_input_u8x8_320x256.hex"
)(
    input logic clk_i,input logic rstn_i,input logic start_i,
    output logic busy_o,output logic done_o,
    output logic presence_keep_o,output logic[7:0]presence_q_o,
    output logic roi_valid_o,output logic[12:0]positive_cells_o,
    output logic[6:0]xmin_o,output logic[5:0]ymin_o,output logic[6:0]xmax_o,output logic[5:0]ymax_o
);
    import handseg_config_pkg::*;

    logic[6:0]pc_r; network_cmd_t cmd; layer_cfg_t layer_cfg; residual_cfg_t residual_cfg; concat_cfg_t concat_cfg;
    network_schedule_rom u_sched(.pc_i(pc_r),.cmd_o(cmd));
    layer_descriptor_rom u_lrom(.layer_id_i(cmd.id),.cfg_o(layer_cfg));
    residual_descriptor_rom u_rrom(.residual_id_i(cmd.id[3:0]),.cfg_o(residual_cfg));
    concat_descriptor_rom u_crom(.concat_id_i(cmd.id[1:0]),.cfg_o(concat_cfg));

    logic active_r, launch_r; logic engine_done;
    assign busy_o=active_r; assign done_o=active_r && (cmd.op==CMD_DONE);

    // Memory buses after mux
    logic m_rd0_v,m_rd0_r;logic[2:0]m_rd0_b;logic[16:0]m_rd0_a;logic m_rd0_rsp_v,m_rd0_rsp_r;logic[63:0]m_rd0_d;
    logic m_rd1_v,m_rd1_r;logic[2:0]m_rd1_b;logic[16:0]m_rd1_a;logic m_rd1_rsp_v,m_rd1_rsp_r;logic[63:0]m_rd1_d;
    logic m_wr_v,m_wr_r;logic[2:0]m_wr_b;logic[16:0]m_wr_a;logic[63:0]m_wr_d;
    reference_feature_memory #(.BANK0_INIT_FILE(INPUT_HEX)) u_mem(.clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_req_valid_i(m_rd0_v),.rd0_req_ready_o(m_rd0_r),.rd0_req_bank_i(m_rd0_b),.rd0_req_addr_i(m_rd0_a),.rd0_rsp_valid_o(m_rd0_rsp_v),.rd0_rsp_ready_i(m_rd0_rsp_r),.rd0_rsp_data_o(m_rd0_d),
        .rd1_req_valid_i(m_rd1_v),.rd1_req_ready_o(m_rd1_r),.rd1_req_bank_i(m_rd1_b),.rd1_req_addr_i(m_rd1_a),.rd1_rsp_valid_o(m_rd1_rsp_v),.rd1_rsp_ready_i(m_rd1_rsp_r),.rd1_rsp_data_o(m_rd1_d),
        .wr_valid_i(m_wr_v),.wr_ready_o(m_wr_r),.wr_bank_i(m_wr_b),.wr_addr_i(m_wr_a),.wr_data_i(m_wr_d));

    // Parameter store
    logic pw_req_v,pw_req_r,pw_rsp_v,pw_rsp_r;logic[16:0]pw_req_a;logic[63:0]pw_d;
    logic pq_req_v,pq_req_r,pq_rsp_v,pq_rsp_r;logic[10:0]pq_req_a;logic[255:0]p_mult;logic[511:0]p_bias;logic[63:0]p_shift,p_zp;logic[7:0]p_relu;
    parameter_store_v141 u_params(.clk_i(clk_i),.rstn_i(rstn_i),.weight_req_valid_i(pw_req_v),.weight_req_ready_o(pw_req_r),.weight_req_addr_i(pw_req_a),.weight_rsp_valid_o(pw_rsp_v),.weight_rsp_ready_i(pw_rsp_r),.weight_rsp_data_o(pw_d),.qparam_req_valid_i(pq_req_v),.qparam_req_ready_o(pq_req_r),.qparam_req_addr_i(pq_req_a),.qparam_rsp_valid_o(pq_rsp_v),.qparam_rsp_ready_i(pq_rsp_r),.multiplier_vec_o(p_mult),.bias_postscale_vec_o(p_bias),.right_shift_vec_o(p_shift),.zero_point_vec_o(p_zp),.relu_en_vec_o(p_relu));

    // Engine-local buses
    logic cv_start,cv_done,cv_busy,cv_rv,cv_rr,cv_rspr,cv_wv,cv_wr,cv_qv,cv_qr,cv_qrsp_r;logic[2:0]cv_rb,cv_wb;logic[16:0]cv_ra,cv_wa,cv_wqa;logic[63:0]cv_wd;logic[10:0]cv_qa;
    conv_layer_engine u_conv(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(cv_start),.cfg_i(layer_cfg),.src_bank_i(cmd.src0_bank),.dst_bank_i(cmd.dst_bank),.busy_o(cv_busy),.done_o(cv_done),
        .mem_rd_req_valid_o(cv_rv),.mem_rd_req_ready_i(m_rd0_r),.mem_rd_req_bank_o(cv_rb),.mem_rd_req_addr_o(cv_ra),.mem_rd_rsp_valid_i(m_rd0_rsp_v),.mem_rd_rsp_ready_o(cv_rspr),.mem_rd_rsp_data_i(m_rd0_d),
        .mem_wr_valid_o(cv_wv),.mem_wr_ready_i(m_wr_r),.mem_wr_bank_o(cv_wb),.mem_wr_addr_o(cv_wa),.mem_wr_data_o(cv_wd),
        .weight_req_valid_o(pw_req_v),.weight_req_ready_i(pw_req_r),.weight_req_addr_o(pw_req_a),.weight_rsp_valid_i(pw_rsp_v),.weight_rsp_ready_o(pw_rsp_r),.weight_rsp_data_i(pw_d),
        .qparam_req_valid_o(pq_req_v),.qparam_req_ready_i(pq_req_r),.qparam_req_addr_o(pq_req_a),.qparam_rsp_valid_i(pq_rsp_v),.qparam_rsp_ready_o(pq_rsp_r),.multiplier_vec_i(p_mult),.bias_vec_i(p_bias),.shift_vec_i(p_shift),.zp_vec_i(p_zp),.relu_vec_i(p_relu));

    logic rs_start,rs_done,rs_r0v,rs_r0rsp_r,rs_r1v,rs_r1rsp_r,rs_wv;logic[2:0]rs_r0b,rs_r1b,rs_wb;logic[16:0]rs_r0a,rs_r1a,rs_wa;logic[63:0]rs_wd;
    residual_word_engine u_reseng(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(rs_start),.cfg_i(residual_cfg),.main_bank_i(cmd.src0_bank),.shortcut_bank_i(cmd.src1_bank),.dst_bank_i(cmd.dst_bank),.word_count_i(cmd.word_count),.busy_o(),.done_o(rs_done),
        .rd0_req_valid_o(rs_r0v),.rd0_req_ready_i(m_rd0_r),.rd0_req_bank_o(rs_r0b),.rd0_req_addr_o(rs_r0a),.rd0_rsp_valid_i(m_rd0_rsp_v),.rd0_rsp_ready_o(rs_r0rsp_r),.rd0_rsp_data_i(m_rd0_d),
        .rd1_req_valid_o(rs_r1v),.rd1_req_ready_i(m_rd1_r),.rd1_req_bank_o(rs_r1b),.rd1_req_addr_o(rs_r1a),.rd1_rsp_valid_i(m_rd1_rsp_v),.rd1_rsp_ready_o(rs_r1rsp_r),.rd1_rsp_data_i(m_rd1_d),
        .wr_valid_o(rs_wv),.wr_ready_i(m_wr_r),.wr_bank_o(rs_wb),.wr_addr_o(rs_wa),.wr_data_o(rs_wd));

    logic cc_start,cc_done,cc_rv,cc_rspr,cc_wv;logic[2:0]cc_rb,cc_wb;logic[16:0]cc_ra,cc_wa;logic[63:0]cc_wd;
    concat_upsample_engine u_concat(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(cc_start),.cfg_i(concat_cfg),.feature_bank_i(cmd.src0_bank),.skip_bank_i(cmd.src1_bank),.dst_bank_i(cmd.dst_bank),.busy_o(),.done_o(cc_done),.rd_req_valid_o(cc_rv),.rd_req_ready_i(m_rd0_r),.rd_req_bank_o(cc_rb),.rd_req_addr_o(cc_ra),.rd_rsp_valid_i(m_rd0_rsp_v),.rd_rsp_ready_o(cc_rspr),.rd_rsp_data_i(m_rd0_d),.wr_valid_o(cc_wv),.wr_ready_i(m_wr_r),.wr_bank_o(cc_wb),.wr_addr_o(cc_wa),.wr_data_o(cc_wd));

    logic gp_start,gp_done,gp_rv,gp_rspr,gp_wv;logic[2:0]gp_rb,gp_wb;logic[16:0]gp_ra,gp_wa;logic[63:0]gp_wd;
    presence_gap_engine u_gap(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(gp_start),.src_bank_i(cmd.src0_bank),.dst_bank_i(cmd.dst_bank),.busy_o(),.done_o(gp_done),.rd_req_valid_o(gp_rv),.rd_req_ready_i(m_rd0_r),.rd_req_bank_o(gp_rb),.rd_req_addr_o(gp_ra),.rd_rsp_valid_i(m_rd0_rsp_v),.rd_rsp_ready_o(gp_rspr),.rd_rsp_data_i(m_rd0_d),.wr_valid_o(gp_wv),.wr_ready_i(m_wr_r),.wr_bank_o(gp_wb),.wr_addr_o(gp_wa),.wr_data_o(gp_wd));

    logic ps_start,ps_done,ps_rv,ps_rspr;logic[2:0]ps_rb;logic[16:0]ps_ra;logic ps_keep;logic[7:0]ps_q;
    presence_check_engine u_pres(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(ps_start),.src_bank_i(cmd.src0_bank),.busy_o(),.done_o(ps_done),.keep_o(ps_keep),.presence_q_o(ps_q),.rd_req_valid_o(ps_rv),.rd_req_ready_i(m_rd0_r),.rd_req_bank_o(ps_rb),.rd_req_addr_o(ps_ra),.rd_rsp_valid_i(m_rd0_rsp_v),.rd_rsp_ready_o(ps_rspr),.rd_rsp_data_i(m_rd0_d));

    logic ro_start,ro_done,ro_rv,ro_rspr;logic[2:0]ro_rb;logic[16:0]ro_ra;
    mask_roi_engine u_roi(.clk_i(clk_i),.rstn_i(rstn_i),.start_i(ro_start),.src_bank_i(cmd.src0_bank),.busy_o(),.done_o(ro_done),.roi_valid_o(roi_valid_o),.positive_cells_o(positive_cells_o),.xmin_o(xmin_o),.ymin_o(ymin_o),.xmax_o(xmax_o),.ymax_o(ymax_o),.rd_req_valid_o(ro_rv),.rd_req_ready_i(m_rd0_r),.rd_req_bank_o(ro_rb),.rd_req_addr_o(ro_ra),.rd_rsp_valid_i(m_rd0_rsp_v),.rd_rsp_ready_o(ro_rspr),.rd_rsp_data_i(m_rd0_d));

    always_comb begin
        cv_start=0;rs_start=0;cc_start=0;gp_start=0;ps_start=0;ro_start=0;engine_done=0;
        m_rd0_v=0;m_rd0_b=0;m_rd0_a=0;m_rd0_rsp_r=0;m_rd1_v=0;m_rd1_b=0;m_rd1_a=0;m_rd1_rsp_r=0;m_wr_v=0;m_wr_b=0;m_wr_a=0;m_wr_d=0;
        case(cmd.op)
            CMD_CONV: begin cv_start=launch_r;m_rd0_v=cv_rv;m_rd0_b=cv_rb;m_rd0_a=cv_ra;m_rd0_rsp_r=cv_rspr;m_wr_v=cv_wv;m_wr_b=cv_wb;m_wr_a=cv_wa;m_wr_d=cv_wd;engine_done=cv_done;end
            CMD_RESIDUAL: begin rs_start=launch_r;m_rd0_v=rs_r0v;m_rd0_b=rs_r0b;m_rd0_a=rs_r0a;m_rd0_rsp_r=rs_r0rsp_r;m_rd1_v=rs_r1v;m_rd1_b=rs_r1b;m_rd1_a=rs_r1a;m_rd1_rsp_r=rs_r1rsp_r;m_wr_v=rs_wv;m_wr_b=rs_wb;m_wr_a=rs_wa;m_wr_d=rs_wd;engine_done=rs_done;end
            CMD_CONCAT: begin cc_start=launch_r;m_rd0_v=cc_rv;m_rd0_b=cc_rb;m_rd0_a=cc_ra;m_rd0_rsp_r=cc_rspr;m_wr_v=cc_wv;m_wr_b=cc_wb;m_wr_a=cc_wa;m_wr_d=cc_wd;engine_done=cc_done;end
            CMD_GAP: begin gp_start=launch_r;m_rd0_v=gp_rv;m_rd0_b=gp_rb;m_rd0_a=gp_ra;m_rd0_rsp_r=gp_rspr;m_wr_v=gp_wv;m_wr_b=gp_wb;m_wr_a=gp_wa;m_wr_d=gp_wd;engine_done=gp_done;end
            CMD_PRESENCE: begin ps_start=launch_r;m_rd0_v=ps_rv;m_rd0_b=ps_rb;m_rd0_a=ps_ra;m_rd0_rsp_r=ps_rspr;engine_done=ps_done;end
            CMD_ROI: begin ro_start=launch_r;m_rd0_v=ro_rv;m_rd0_b=ro_rb;m_rd0_a=ro_ra;m_rd0_rsp_r=ro_rspr;engine_done=ro_done;end
            default: engine_done=1'b0;
        endcase
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin active_r<=0;pc_r<=0;launch_r<=0;presence_keep_o<=0;presence_q_o<=0;end
        else begin
            launch_r<=0;
            if(!active_r) begin if(start_i)begin active_r<=1;pc_r<=0;launch_r<=1;end end
            else if(cmd.op==CMD_DONE) active_r<=0;
            else if(engine_done) begin
                if(cmd.op==CMD_PRESENCE) begin presence_keep_o<=ps_keep;presence_q_o<=ps_q;if(!ps_keep) begin active_r<=0; end else begin pc_r<=pc_r+1'b1;launch_r<=1;end end
                else begin pc_r<=pc_r+1'b1;launch_r<=1;end
            end
        end
    end
endmodule
