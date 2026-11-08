`timescale 1ns/1ps
// Uses the REAL upstream OpenRAM Verilog macro model (2KiB, 1RW+1R).
// 20ns TB clock gives the upstream macro model's negedge+#3ns timing margin.
module tb_v109_feature_macro;
    reg clk_i = 0;
    always #10 clk_i = ~clk_i;
    reg rstn_i = 0;
    reg rd0_req_valid_i=0, rd1_req_valid_i=0, wr_valid_i=0;
    reg rd0_rsp_ready_i=1, rd1_rsp_ready_i=1;
    reg [2:0] rd0_req_bank_i=0, rd1_req_bank_i=0, wr_bank_i=0;
    reg [16:0] rd0_req_addr_i=0, rd1_req_addr_i=0, wr_addr_i=0;
    reg [63:0] wr_data_i=0;
    wire rd0_req_ready_o, rd1_req_ready_o, wr_ready_o;
    wire rd0_rsp_valid_o,rd1_rsp_valid_o;
    wire [63:0] rd0_rsp_data_o,rd1_rsp_data_o;
    integer b;
    reg [63:0] exp0,exp1;

    reference_feature_memory #(
        .DEPTH_WORDS(1024), .BANK0_INIT_FILE("")
    ) dut (
        .clk_i(clk_i), .rstn_i(rstn_i),
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

    task automatic write64(input [2:0] bank, input [16:0] addr,
                            input [63:0] data);
    begin
        @(negedge clk_i); #1;
        wr_valid_i=1; wr_bank_i=bank; wr_addr_i=addr; wr_data_i=data;
        #1;
        if (!wr_ready_o) $fatal(1,"unexpected blocked write");
        @(posedge clk_i); #1;
        @(negedge clk_i); #5; // model writes at negedge
        wr_valid_i=0;
    end
    endtask

    task automatic read2(input [2:0] b0, input [16:0] a0, input [63:0] d0,
                         input [2:0] b1, input [16:0] a1, input [63:0] d1);
    begin
        @(negedge clk_i); #1;
        rd0_req_valid_i=1;rd0_req_bank_i=b0;rd0_req_addr_i=a0;
        rd1_req_valid_i=1;rd1_req_bank_i=b1;rd1_req_addr_i=a1;
        if (!rd0_req_ready_o || !rd1_req_ready_o)
            $fatal(1,"read ports not ready");
        @(posedge clk_i); #1;
        rd0_req_valid_i=0;rd1_req_valid_i=0;
        @(negedge clk_i); #5;
        if (!rd0_rsp_valid_o || !rd1_rsp_valid_o)
            $fatal(1,"read responses not valid");
        if (rd0_rsp_data_o !== d0 || rd1_rsp_data_o !== d1)
            $fatal(1,"read2 mismatch b0=%0d a0=%0d got=%h exp=%h b1=%0d a1=%0d got=%h exp=%h",
                b0,a0,rd0_rsp_data_o,d0,b1,a1,rd1_rsp_data_o,d1);
    end
    endtask

    initial begin
        repeat (3) @(negedge clk_i);
        #1 rstn_i=1;
        // Both halves of each 64-bit word, boundary 511/512, and 8 banks.
        for (b=0;b<8;b=b+1) begin
            write64(b[2:0],17'd0,   64'h10203040_AABB0000 + b);
            write64(b[2:0],17'd511, 64'hF00DBABE_00001000 + b);
            write64(b[2:0],17'd512, 64'h12345678_CAFE2000 + b);
            write64(b[2:0],17'd1023,64'hFEDCBA98_00003000 + b);
        end
        for (b=0;b<8;b=b+1) begin
            read2(b[2:0],17'd0,   64'h10203040_AABB0000 + b,
                  b[2:0],17'd1023,64'hFEDCBA98_00003000 + b);
            read2(b[2:0],17'd511,64'hF00DBABE_00001000 + b,
                  b[2:0],17'd512,64'h12345678_CAFE2000 + b);
        end
        // Dual reads crossing different banks, same cycle.
        read2(3'd7,17'd512,64'h12345678_CAFE2007,
              3'd0,17'd511,64'hF00DBABE_00001000);

        // Same-address read/write MUST block write, preserving old data.
        @(negedge clk_i); #1;
        wr_valid_i=1;wr_bank_i=3'd0;wr_addr_i=17'd511;
        wr_data_i=64'hDEAD_BEEF_BAD0_C0DE;
        rd0_req_valid_i=1;rd0_req_bank_i=3'd0;rd0_req_addr_i=17'd511;
        rd1_req_valid_i=0;
        #1;
        if (wr_ready_o !== 1'b0)
            $fatal(1,"same-word collision did not backpressure write");
        @(posedge clk_i); #1;
        rd0_req_valid_i=0;
        @(negedge clk_i); #5;
        if (!rd0_rsp_valid_o || rd0_rsp_data_o !== 64'hF00DBABE_00001000)
            $fatal(1,"collision read must return pre-write data");
        #1;
        if (wr_ready_o !== 1'b1)
            $fatal(1,"write did not unblock after colliding read acceptance");
        @(posedge clk_i); #1;
        wr_valid_i=0;
        @(negedge clk_i); #5;
        read2(3'd0,17'd511,64'hDEAD_BEEF_BAD0_C0DE,
              3'd0,17'd511,64'hDEAD_BEEF_BAD0_C0DE);

        // Response remains stable when backpressure stalls the consumer.
        rd0_rsp_ready_i=0;rd1_rsp_ready_i=0;
        repeat(4) begin
            @(negedge clk_i); #5;
            if (!rd0_rsp_valid_o || !rd1_rsp_valid_o ||
                rd0_rsp_data_o !== 64'hDEAD_BEEF_BAD0_C0DE ||
                rd1_rsp_data_o !== 64'hDEAD_BEEF_BAD0_C0DE)
                $fatal(1,"backpressure did not retain data");
        end
        rd0_rsp_ready_i=1;rd1_rsp_ready_i=1;
        // V109: RW port is occupied by read0 in the same tile, even if
        // the write address is a different word. Read wins this cycle.
        @(negedge clk_i); #1;
        rd0_req_valid_i=1; rd0_req_bank_i=3'd1; rd0_req_addr_i=17'd511;
        wr_valid_i=1; wr_bank_i=3'd1; wr_addr_i=17'd510;
        wr_data_i=64'h5555_AAAA_4444_BBBB;
        #1;
        if (wr_ready_o !== 1'b0) $fatal(1,"V109 same-tile RW-port arbitration FAILED");
        @(posedge clk_i); #1;
        rd0_req_valid_i=0;
        @(negedge clk_i); #5;
        if (!rd0_rsp_valid_o || rd0_rsp_data_o !== 64'hF00DBABE_00001001)
            $fatal(1,"V109 read0 must win RW-port scheduling");
        #1;
        if (wr_ready_o !== 1'b1) $fatal(1,"V109 same-tile write did not unblock");
        @(posedge clk_i); #1;
        wr_valid_i=0;
        @(negedge clk_i); #5;
        read2(3'd1,17'd510,64'h5555_AAAA_4444_BBBB,
              3'd1,17'd511,64'hF00DBABE_00001001);

        // Different tiles in the same bank can read0 and write concurrently.
        @(negedge clk_i); #1;
        rd0_req_valid_i=1;rd0_req_bank_i=3'd2;rd0_req_addr_i=17'd511;
        wr_valid_i=1;wr_bank_i=3'd2;wr_addr_i=17'd513;
        wr_data_i=64'hABCD_9876_4321_0123;
        #1;
        if (wr_ready_o !== 1'b1) $fatal(1,"V109 different-tile write should be accepted");
        @(posedge clk_i); #1;
        rd0_req_valid_i=0;wr_valid_i=0;
        @(negedge clk_i); #5;
        if (!rd0_rsp_valid_o || rd0_rsp_data_o !== 64'hF00DBABE_00001002)
            $fatal(1,"V109 read0 corrupted by parallel different-tile write");
        read2(3'd2,17'd513,64'hABCD_9876_4321_0123,
              3'd2,17'd511,64'hF00DBABE_00001002);

        // read1 can coexist with a write to another word in the same tile.
        @(negedge clk_i); #1;
        rd1_req_valid_i=1;rd1_req_bank_i=3'd3;rd1_req_addr_i=17'd511;
        wr_valid_i=1;wr_bank_i=3'd3;wr_addr_i=17'd510;
        wr_data_i=64'h3C3C_C3C3_5A5A_A5A5;
        #1;
        if (wr_ready_o !== 1'b1) $fatal(1,"V109 port1 read / port0 write should be accepted");
        @(posedge clk_i); #1;
        rd1_req_valid_i=0;wr_valid_i=0;
        @(negedge clk_i); #5;
        if (!rd1_rsp_valid_o || rd1_rsp_data_o !== 64'hF00DBABE_00001003)
            $fatal(1,"V109 read1 corrupted by different-word write");
        read2(3'd3,17'd510,64'h3C3C_C3C3_5A5A_A5A5,
              3'd3,17'd511,64'hF00DBABE_00001003);

        $display("PASS tb_v109_feature_macro: 8 banks, 2 x 512-word tiles, both read ports, 1RW/1R single copy, collision stall, backpressure");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"simulation timed out");
    end
endmodule
