module mask_roi_engine (
    input logic clk_i,input logic rstn_i,input logic start_i,input logic[2:0]src_bank_i,
    output logic busy_o,output logic done_o,output logic roi_valid_o,output logic[12:0]positive_cells_o,
    output logic[6:0]xmin_o,output logic[5:0]ymin_o,output logic[6:0]xmax_o,output logic[5:0]ymax_o,
    output logic rd_req_valid_o,input logic rd_req_ready_i,output logic[2:0]rd_req_bank_o,output logic[16:0]rd_req_addr_o,
    input logic rd_rsp_valid_i,output logic rd_rsp_ready_o,input logic[63:0]rd_rsp_data_i
);
    // V4: explicit x/y counters replace idx%80 and idx/80 divider logic.
    localparam integer W=80,H=64,N=5120;
    typedef enum logic[2:0]{S_IDLE,S_REQ,S_WAIT,S_DONE}state_t;
    state_t state_r;
    logic[2:0]bank_r;
    logic[12:0]idx_r,count_r;
    logic[6:0]x_r;
    logic[5:0]y_r;
    logic hit_c;

    assign hit_c=(rd_rsp_data_i[7:0]>=8'd110);
    assign busy_o=(state_r!=S_IDLE)&&(state_r!=S_DONE);
    assign done_o=(state_r==S_DONE);
    assign rd_req_valid_o=(state_r==S_REQ);
    assign rd_req_bank_o=bank_r;
    assign rd_req_addr_o={4'd0,idx_r};
    assign rd_rsp_ready_o=(state_r==S_WAIT);

    always_ff @(posedge clk_i or negedge rstn_i)begin
        if(!rstn_i)begin
            state_r<=S_IDLE;bank_r<=0;idx_r<=0;count_r<=0;x_r<=0;y_r<=0;
            xmin_o<=0;ymin_o<=0;xmax_o<=0;ymax_o<=0;roi_valid_o<=0;positive_cells_o<=0;
        end else case(state_r)
            S_IDLE:if(start_i)begin
                bank_r<=src_bank_i;idx_r<=0;count_r<=0;x_r<=0;y_r<=0;
                xmin_o<=7'd79;ymin_o<=6'd63;xmax_o<=0;ymax_o<=0;roi_valid_o<=0;
                state_r<=S_REQ;
            end
            S_REQ:if(rd_req_ready_i)state_r<=S_WAIT;
            S_WAIT:if(rd_rsp_valid_i)begin
                if(hit_c)begin
                    count_r<=count_r+1'b1;
                    if(x_r<xmin_o)xmin_o<=x_r;
                    if(x_r>xmax_o)xmax_o<=x_r;
                    if(y_r<ymin_o)ymin_o<=y_r;
                    if(y_r>ymax_o)ymax_o<=y_r;
                end
                if(idx_r==N-1)begin
                    positive_cells_o<=count_r+(hit_c?1:0);
                    roi_valid_o<=((count_r+(hit_c?1:0))>=8);
                    state_r<=S_DONE;
                end else begin
                    idx_r<=idx_r+1'b1;
                    if(x_r==W-1)begin
                        x_r<=0;
                        y_r<=y_r+1'b1;
                    end else begin
                        x_r<=x_r+1'b1;
                    end
                    state_r<=S_REQ;
                end
            end
            S_DONE:state_r<=S_IDLE;
            default:state_r<=S_IDLE;
        endcase
    end
endmodule
