`timescale 1ns/1ps
module tb_v106_feature_banks;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rstn_i=0;
    reg rd0_req_valid_i=0,rd1_req_valid_i=0,wr_valid_i=0;
    reg rd0_rsp_ready_i=1,rd1_rsp_ready_i=1;
    reg [2:0] rd0_req_bank_i=0,rd1_req_bank_i=0,wr_bank_i=0;
    reg [16:0] rd0_req_addr_i=0,rd1_req_addr_i=0,wr_addr_i=0;
    reg [63:0] wr_data_i=0;
    wire rd0_req_ready_o,rd1_req_ready_o,wr_ready_o,rd0_rsp_valid_o,rd1_rsp_valid_o;
    wire [63:0] rd0_rsp_data_o,rd1_rsp_data_o;
    integer b;
    integer depths[0:7];
    reg [63:0] expected;

    reference_feature_memory #(.BANK0_INIT_FILE("")) dut (
      .clk_i(clk_i),.rstn_i(rstn_i),
      .rd0_req_valid_i(rd0_req_valid_i),.rd0_req_ready_o(rd0_req_ready_o),
      .rd0_req_bank_i(rd0_req_bank_i),.rd0_req_addr_i(rd0_req_addr_i),
      .rd0_rsp_valid_o(rd0_rsp_valid_o),.rd0_rsp_ready_i(rd0_rsp_ready_i),
      .rd0_rsp_data_o(rd0_rsp_data_o),
      .rd1_req_valid_i(rd1_req_valid_i),.rd1_req_ready_o(rd1_req_ready_o),
      .rd1_req_bank_i(rd1_req_bank_i),.rd1_req_addr_i(rd1_req_addr_i),
      .rd1_rsp_valid_o(rd1_rsp_valid_o),.rd1_rsp_ready_i(rd1_rsp_ready_i),
      .rd1_rsp_data_o(rd1_rsp_data_o),
      .wr_valid_i(wr_valid_i),.wr_ready_o(wr_ready_o),
      .wr_bank_i(wr_bank_i),.wr_addr_i(wr_addr_i),.wr_data_i(wr_data_i)
    );
    initial begin
        depths[0]=122880;depths[1]=61440;depths[2]=46080;depths[3]=5120;
        depths[4]=1280;depths[5]=384;depths[6]=46080;depths[7]=5120;
        repeat(3) @(negedge clk_i);
        rstn_i=1;
        // Write first and last valid address of each bank
        for (b=0;b<8;b=b+1) begin
            @(negedge clk_i);
            wr_bank_i=b;wr_addr_i=0;wr_data_i=64'h1020304050607080+b;
            wr_valid_i=1;
            @(negedge clk_i);
            wr_addr_i=depths[b]-1;wr_data_i=64'hDEADBEEF00000000+b;
            @(negedge clk_i);
            wr_valid_i=0;
        end
        for (b=0;b<8;b=b+1) begin
            @(negedge clk_i);
            rd0_req_valid_i=1;rd1_req_valid_i=1;
            rd0_req_bank_i=b;rd1_req_bank_i=b;
            rd0_req_addr_i=0;rd1_req_addr_i=depths[b]-1;
            @(negedge clk_i);
            rd0_req_valid_i=0;rd1_req_valid_i=0;
            if (!rd0_rsp_valid_o || !rd1_rsp_valid_o)
                $fatal(1,"missing read valid at bank %0d",b);
            if (rd0_rsp_data_o !== (64'h1020304050607080+b))
                $fatal(1,"read0 mismatch bank %0d got %h",b,rd0_rsp_data_o);
            if (rd1_rsp_data_o !== (64'hDEADBEEF00000000+b))
                $fatal(1,"read1 mismatch bank %0d got %h",b,rd1_rsp_data_o);
            // Check stall holds read-valid and registered data
            rd0_rsp_ready_i=0;rd1_rsp_ready_i=0;
            @(negedge clk_i);
            if (!rd0_rsp_valid_o || !rd1_rsp_valid_o ||
                rd0_rsp_data_o !== (64'h1020304050607080+b))
                $fatal(1,"response hold failed bank %0d",b);
            rd0_rsp_ready_i=1;rd1_rsp_ready_i=1;
            @(negedge clk_i);
        end
        $display("PASS tb_v106_feature_banks: 8 banks, first/last addr, 2R1W and read stall");
        $finish;
    end
endmodule
