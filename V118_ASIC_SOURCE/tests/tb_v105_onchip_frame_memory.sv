`timescale 1ns/1ps
module tb_v105_onchip_frame_memory;
    reg clk=0, rstn=0;
    always #5 clk=~clk;
    reg active=0, cam_valid=0;
    reg [15:0] cam_pixel=0;
    wire snap_ready, error;
    reg rd_valid=0, rd_rsp_ready=0, wr_valid=0;
    reg [31:0] rd_addr=0,wr_addr=0;
    reg [63:0] wr_data=0;
    wire rd_ready,rsp_valid,wr_ready;
    wire [63:0] rd_data;
    asic_onchip_frame_memory #(.SNAPSHOT_PIXELS(8),.RGB96_WORDS(2)) dut (
        .clk_i(clk),.rstn_i(rstn),
        .cam_capture_active_i(active),.cam_pixel_valid_i(cam_valid),
        .cam_pixel_rgb565_i(cam_pixel),.snapshot_ready_o(snap_ready),
        .access_error_o(error),
        .rd_req_valid_i(rd_valid),.rd_req_ready_o(rd_ready),
        .rd_req_addr_i(rd_addr),.rd_rsp_valid_o(rsp_valid),
        .rd_rsp_ready_i(rd_rsp_ready),.rd_rsp_data_o(rd_data),
        .wr_req_valid_i(wr_valid),.wr_req_ready_o(wr_ready),
        .wr_req_addr_i(wr_addr),.wr_req_data_i(wr_data)
    );
    task automatic read_check(input [31:0] addr, input [63:0] expected);
    begin
        @(negedge clk);
        rd_valid=1; rd_addr=addr; rd_rsp_ready=0;
        if (!rd_ready) $fatal(1,"Unexpected read stall");
        @(negedge clk);
        rd_valid=0;
        if (!rsp_valid || rd_data !== expected)
            $fatal(1,"Read mismatch %h got=%h expected=%h",addr,rd_data,expected);
        repeat(2) begin
            @(negedge clk);
            if (!rsp_valid || rd_data !== expected)
                $fatal(1,"Response not held correctly");
        end
        rd_rsp_ready=1;
        @(negedge clk);
        rd_rsp_ready=0;
        if (rsp_valid) $fatal(1,"Response did not deassert");
    end
    endtask
    task automatic write_word(input [31:0] addr, input [63:0] data);
    begin
        @(negedge clk);
        wr_valid=1; wr_addr=addr; wr_data=data;
        if (!wr_ready) $fatal(1,"Unexpected write stall");
        @(negedge clk); wr_valid=0;
    end
    endtask
    integer i;
    initial begin
        repeat(3) @(negedge clk); rstn=1;
        @(negedge clk); active=1;
        for (i=0;i<8;i=i+1) begin
            cam_valid=1;
            cam_pixel=16'h1001+i;
            @(negedge clk);
        end
        cam_valid=0;
        active=0;
        #1;
        if (!snap_ready || error) $fatal(1,"Snapshot not complete");
        read_check(32'h3200_0000, 64'h1004_1003_1002_1001);
        read_check(32'h3200_0008, 64'h1008_1007_1006_1005);
        write_word(32'h3600_0000,64'h0123_4567_89ab_cdef);
        write_word(32'h3600_0008,64'hfedc_ba98_7654_3210);
        read_check(32'h3600_0000,64'h0123_4567_89ab_cdef);
        read_check(32'h3600_0008,64'hfedc_ba98_7654_3210);
        if (error) $fatal(1,"Unexpected address error");
        $display("PASS tb_v105_onchip_frame_memory: 8 snapshot RGB565 pixels + 2 ROI words");
        $finish;
    end
    initial begin #4000; $fatal(1,"TEST TIMEOUT"); end
endmodule
