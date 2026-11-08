module presence_check_engine (
    input logic clk_i,input logic rstn_i,input logic start_i,input logic[2:0]src_bank_i,
    output logic busy_o,output logic done_o,output logic keep_o,output logic[7:0]presence_q_o,
    output logic rd_req_valid_o,input logic rd_req_ready_i,output logic[2:0]rd_req_bank_o,output logic[16:0]rd_req_addr_o,
    input logic rd_rsp_valid_i,output logic rd_rsp_ready_o,input logic[63:0]rd_rsp_data_i
);
    typedef enum logic[2:0]{S_IDLE,S_REQ,S_WAIT,S_DONE}state_t;state_t state_r;logic[2:0]bank_r;
    assign busy_o=(state_r!=S_IDLE)&&(state_r!=S_DONE);assign done_o=(state_r==S_DONE);assign rd_req_valid_o=(state_r==S_REQ);assign rd_req_bank_o=bank_r;assign rd_req_addr_o=0;assign rd_rsp_ready_o=(state_r==S_WAIT);
    always_ff @(posedge clk_i or negedge rstn_i)begin if(!rstn_i)begin state_r<=S_IDLE;bank_r<=0;keep_o<=0;presence_q_o<=0;end else case(state_r) S_IDLE:if(start_i)begin bank_r<=src_bank_i;state_r<=S_REQ;end S_REQ:if(rd_req_ready_i)state_r<=S_WAIT; S_WAIT:if(rd_rsp_valid_i)begin presence_q_o<=rd_rsp_data_i[7:0];keep_o<=(rd_rsp_data_i[7:0]>=8'd28);state_r<=S_DONE;end S_DONE:state_r<=S_IDLE;default:state_r<=S_IDLE;endcase end
endmodule
