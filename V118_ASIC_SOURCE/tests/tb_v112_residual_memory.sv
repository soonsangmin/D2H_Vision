`timescale 1ns/1ps
// V112: REAL HandSeg residual_word_engine + REAL reference_feature_memory API.
// Two separate compilations of this SAME testbench:
//   golden: inferred V106 RAM; hard: V109 1RW1R SKY130 OpenRAM macro model.
// NO mock engine, no mock SRAM, no bypass of the ready/valid protocol.
module tb_v112_residual_memory;
    localparam PHASE_LOAD=0, PHASE_ENGINE=1, PHASE_READBACK=2;
    reg clk=0;
    always #10 clk=~clk;
    reg rstn=0, start=0;
    integer phase=PHASE_LOAD;
    integer words=4;
    integer i;
    integer completed=0;
    integer cycle_count=0;
    integer throttled_writes=0;
    reg [63:0] expected;

    handseg_config_pkg::residual_cfg_t cfg;
    wire engine_busy, engine_done;
    wire e_r0_v,e_r0_ready,e_r0_rsp_ready,e_r1_v,e_r1_ready,e_r1_rsp_ready;
    wire [2:0] e_r0_bank,e_r1_bank,e_wr_bank;
    wire [16:0] e_r0_addr,e_r1_addr,e_wr_addr;
    wire e_wr_v,e_wr_ready;
    wire [63:0] e_wr_data;

    reg tb_wr_v=0;
    reg [2:0] tb_wr_bank=0;
    reg [16:0] tb_wr_addr=0;
    reg [63:0] tb_wr_data=0;
    reg tb_rd_v=0;
    reg [2:0] tb_rd_bank=2;
    reg [16:0] tb_rd_addr=0;

    wire m_r0_ready,m_r1_ready,m_wr_ready,m_r0_rsp_v,m_r1_rsp_v;
    wire [63:0] m_r0_rsp_data,m_r1_rsp_data;
    wire m_r0_v = phase==PHASE_ENGINE ? e_r0_v : (phase==PHASE_READBACK ? tb_rd_v : 1'b0);
    wire [2:0] m_r0_bank = phase==PHASE_ENGINE ? e_r0_bank : tb_rd_bank;
    wire [16:0] m_r0_addr = phase==PHASE_ENGINE ? e_r0_addr : tb_rd_addr;
    wire m_r0_rsp_ready = phase==PHASE_ENGINE ? e_r0_rsp_ready : 1'b1;
    wire m_r1_v = phase==PHASE_ENGINE ? e_r1_v : 1'b0;
    wire [2:0] m_r1_bank=e_r1_bank;
    wire [16:0] m_r1_addr=e_r1_addr;
    wire m_r1_rsp_ready = phase==PHASE_ENGINE ? e_r1_rsp_ready : 1'b1;

    // Exercise actual residual engine's write-backpressure handling by
    // gating BOTH the engine's ready input and physical memory write valid.
    // The same deterministic throttle applies to golden and hard models.
    wire write_slot = (cycle_count % 5 != 0);
    wire m_wr_v = phase==PHASE_LOAD ? tb_wr_v :
                  (phase==PHASE_ENGINE ? (e_wr_v && write_slot) : 1'b0);
    wire [2:0] m_wr_bank=phase==PHASE_LOAD ? tb_wr_bank : e_wr_bank;
    wire [16:0] m_wr_addr=phase==PHASE_LOAD ? tb_wr_addr : e_wr_addr;
    wire [63:0] m_wr_data=phase==PHASE_LOAD ? tb_wr_data : e_wr_data;
    assign e_r0_ready=m_r0_ready;
    assign e_r1_ready=m_r1_ready;
    assign e_wr_ready=m_wr_ready && write_slot && phase==PHASE_ENGINE;

    residual_word_engine u_engine (
        .clk_i(clk),.rstn_i(rstn),.start_i(start),.cfg_i(cfg),
        .main_bank_i(3'd0),.shortcut_bank_i(3'd1),.dst_bank_i(3'd2),
        .word_count_i(words[16:0]),.busy_o(engine_busy),.done_o(engine_done),
        .rd0_req_valid_o(e_r0_v),.rd0_req_ready_i(e_r0_ready),
        .rd0_req_bank_o(e_r0_bank),.rd0_req_addr_o(e_r0_addr),
        .rd0_rsp_valid_i(m_r0_rsp_v),.rd0_rsp_ready_o(e_r0_rsp_ready),.rd0_rsp_data_i(m_r0_rsp_data),
        .rd1_req_valid_o(e_r1_v),.rd1_req_ready_i(e_r1_ready),
        .rd1_req_bank_o(e_r1_bank),.rd1_req_addr_o(e_r1_addr),
        .rd1_rsp_valid_i(m_r1_rsp_v),.rd1_rsp_ready_o(e_r1_rsp_ready),.rd1_rsp_data_i(m_r1_rsp_data),
        .wr_valid_o(e_wr_v),.wr_ready_i(e_wr_ready),
        .wr_bank_o(e_wr_bank),.wr_addr_o(e_wr_addr),.wr_data_o(e_wr_data)
    );

    // Identical physical/logical depth on both configurations. The 1024-word
    // configuration deliberately exercises both tiles on each 64-bit bank.
    reference_feature_memory #(.DEPTH_WORDS(1024),.BANK0_INIT_FILE("")) u_memory (
        .clk_i(clk),.rstn_i(rstn),
        .rd0_req_valid_i(m_r0_v),.rd0_req_ready_o(m_r0_ready),.rd0_req_bank_i(m_r0_bank),.rd0_req_addr_i(m_r0_addr),
        .rd0_rsp_valid_o(m_r0_rsp_v),.rd0_rsp_ready_i(m_r0_rsp_ready),.rd0_rsp_data_o(m_r0_rsp_data),
        .rd1_req_valid_i(m_r1_v),.rd1_req_ready_o(m_r1_ready),.rd1_req_bank_i(m_r1_bank),.rd1_req_addr_i(m_r1_addr),
        .rd1_rsp_valid_o(m_r1_rsp_v),.rd1_rsp_ready_i(m_r1_rsp_ready),.rd1_rsp_data_o(m_r1_rsp_data),
        .wr_valid_i(m_wr_v),.wr_ready_o(m_wr_ready),.wr_bank_i(m_wr_bank),.wr_addr_i(m_wr_addr),.wr_data_i(m_wr_data)
    );

    function automatic [63:0] make_main(input integer idx);
        reg [63:0] tmp;
        integer lane;
        begin
            tmp=0;
            for (lane=0;lane<8;lane=lane+1)
                tmp[lane*8 +:8] = (idx+lane*13+1) % 256;
            make_main=tmp;
        end
    endfunction
    function automatic [63:0] make_shortcut(input integer idx);
        reg [63:0] tmp;
        integer lane;
        begin
            tmp=0;
            for (lane=0;lane<8;lane=lane+1)
                tmp[lane*8 +:8] = (idx*3+lane*7+2) % 256;
            make_shortcut=tmp;
        end
    endfunction
    // Independent arithmetic oracle: cfg has unit multipliers, zero offsets,
    // zero shift. Thus each output lane = saturate(main + shortcut, 0..255).
    function automatic [63:0] expected_word(input integer idx);
        reg [63:0] tmp, a, b;
        integer lane,sum;
        begin
            a=make_main(idx); b=make_shortcut(idx); tmp=0;
            for (lane=0;lane<8;lane=lane+1) begin
                sum=a[lane*8+:8]+b[lane*8+:8];
                tmp[lane*8+:8] = sum > 255 ? 8'd255 : sum;
            end
            expected_word=tmp;
        end
    endfunction

    // Count and check every accepted residual-engine write transaction.
    always @(posedge clk) if (rstn) begin
        cycle_count <= cycle_count + 1;
        if (phase==PHASE_ENGINE && e_wr_v && !e_wr_ready)
            throttled_writes <= throttled_writes + 1;
        if (phase==PHASE_ENGINE && e_wr_v && e_wr_ready) begin
            if (completed>=words) $fatal(1,"V112 extra engine write");
            if (e_wr_addr !== completed[16:0] || e_wr_bank !== 3'd2)
                $fatal(1,"V112 engine write address mismatch: got bank=%0d addr=%0d expected addr=%0d",e_wr_bank,e_wr_addr,completed);
            if (e_wr_data !== expected_word(completed))
                $fatal(1,"V112 arithmetic mismatch at word %0d got %h expected %h",completed,e_wr_data,expected_word(completed));
            $display("TRACE word=%0d data=%016h", completed,e_wr_data);
            completed <= completed+1;
        end
    end

    task automatic preload(input [2:0] bank,input integer idx,input [63:0] data);
        begin
            @(negedge clk); #1;
            tb_wr_v=1; tb_wr_bank=bank; tb_wr_addr=idx; tb_wr_data=data;
            #1;
            if (m_wr_ready !== 1'b1) $fatal(1,"V112 preload blocked at bank %0d idx %0d",bank,idx);
            @(posedge clk); #1;
            tb_wr_v=0;
            // OpenRAM behavioral model commits on falling edge.
            @(negedge clk); #5;
        end
    endtask
    task automatic readback(input integer idx);
        begin
            @(negedge clk); #1;
            tb_rd_bank=3'd2; tb_rd_addr=idx; tb_rd_v=1;
            #1;
            if (m_r0_ready !== 1'b1) $fatal(1,"V112 readback port not ready");
            @(posedge clk); #1;
            tb_rd_v=0;
            @(negedge clk); #5;
            if (m_r0_rsp_v !== 1'b1 || m_r0_rsp_data !== expected_word(idx))
                $fatal(1,"V112 SRAM readback mismatch at %0d got=%016h expected=%016h valid=%b",idx,m_r0_rsp_data,expected_word(idx),m_r0_rsp_v);
        end
    endtask

    initial begin
        if (!$value$plusargs("WORDS=%d", words)) words=4;
        if (words<1 || words>513) $fatal(1,"V112 WORDS must be within 1..513");
        cfg='0;
        cfg.main_multiplier=32'd1;
        cfg.shortcut_multiplier=32'd1;
        cfg.main_zero_point=8'd0;
        cfg.shortcut_zero_point=8'd0;
        cfg.output_zero_point=8'd0;
        cfg.shared_right_shift=8'd0;
        repeat(3) @(negedge clk);
        #1; rstn=1;

        // Prepare both input banks through the exact same feature RAM API.
        for (i=0;i<words;i=i+1) begin
            preload(3'd0,i,make_main(i));
            preload(3'd1,i,make_shortcut(i));
        end
        @(negedge clk); #1;
        phase=PHASE_ENGINE;
        start=1;
        @(posedge clk); #1; start=0;
        wait(engine_done===1'b1);
        @(negedge clk); #1;
        if (completed!==words)
            $fatal(1,"V112 engine done but only %0d/%0d writes committed",completed,words);
        if (words==513 && throttled_writes==0)
            $fatal(1,"V112 stress test did not exercise write backpressure");
        phase=PHASE_READBACK;
        readback(0);
        if(words>1) readback(1);
        if(words>2) readback(words-1);
        if(words>512) begin
            readback(511);
            readback(512);
        end
        $display("PASS tb_v112_residual_memory WORDS=%0d WRITES=%0d THROTTLED=%0d READBACK=OK",words,completed,throttled_writes);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"V112 timeout: words=%0d completed=%0d phase=%0d",words,completed,phase);
    end
endmodule
