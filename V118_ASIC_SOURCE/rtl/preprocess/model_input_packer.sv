module model_input_packer(
    input logic clk_i,input logic rstn_i,input logic start_i,input logic valid_i,input logic[23:0]ycbcr_i,
    output logic valid_o,output logic[16:0]addr_o,output logic[63:0]data_o,output logic done_o
);
logic[16:0]addr_r;always_ff@(posedge clk_i or negedge rstn_i)begin if(!rstn_i)begin addr_r<=0;valid_o<=0;addr_o<=0;data_o<=0;done_o<=0;end else begin valid_o<=0;done_o<=0;if(start_i)addr_r<=0;if(valid_i)begin valid_o<=1;addr_o<=addr_r;data_o<={40'd0,ycbcr_i[7:0],ycbcr_i[15:8],ycbcr_i[23:16]};if(addr_r==81919)begin done_o<=1;addr_r<=0;end else addr_r<=addr_r+1'b1;end end end
endmodule
