`timescale 1ns/1ps
module tb_fifo_sram_equivalence;
    parameter integer WIDTH=4, CHANNELS=3, DEPTH=3;
    localparam integer ROW_BYTES=WIDTH*CHANNELS;
    localparam integer TOTAL_ROWS=8;
    localparam integer TOTAL_BYTES=TOTAL_ROWS*ROW_BYTES;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,wr_valid=0,rd_ready=0;
    reg [7:0] wr_pixel=0,wr_ch_idx=0;
    wire wr_ready,rd_valid,empty,full;
    wire [7:0] rd_pixel,rd_ch_idx,rd_row_idx,completed_rows;
    wire ref_wr_ready,ref_rd_valid,ref_empty,ref_full;
    wire [7:0] ref_rd_pixel,ref_rd_ch_idx,ref_rd_row_idx,ref_completed_rows;
    integer sent=0,received=0,cycle=0;
    reg [31:0] pseudo=32'h91ab32d7;

    stream_interstage_row_fifo_hwc_stage2 #(.WIDTH(WIDTH),.HEIGHT(96),.CHANNELS(CHANNELS),.DEPTH(DEPTH),.DATA_WIDTH(8)) dut
    (.clk(clk),.rst_n(rst_n),.wr_valid(wr_valid),.wr_pixel(wr_pixel),.wr_ch_idx(wr_ch_idx),.wr_ready(wr_ready),
     .completed_rows(completed_rows),.rd_valid(rd_valid),.rd_pixel(rd_pixel),.rd_ch_idx(rd_ch_idx),.rd_row_idx(rd_row_idx),
     .rd_ready(rd_ready),.empty(empty),.full(full));
    reference_stream_interstage_row_fifo_v102 #(.WIDTH(WIDTH),.HEIGHT(96),.CHANNELS(CHANNELS),.DEPTH(DEPTH),.DATA_WIDTH(8)) ref_fifo
    (.clk(clk),.rst_n(rst_n),.wr_valid(wr_valid),.wr_pixel(wr_pixel),.wr_ch_idx(wr_ch_idx),.wr_ready(ref_wr_ready),
     .completed_rows(ref_completed_rows),.rd_valid(ref_rd_valid),.rd_pixel(ref_rd_pixel),.rd_ch_idx(ref_rd_ch_idx),.rd_row_idx(ref_rd_row_idx),
     .rd_ready(rd_ready),.empty(ref_empty),.full(ref_full));

    task compare_outputs;
    begin
       if({wr_ready,rd_valid,rd_ch_idx,rd_row_idx,empty,full,completed_rows} !==
          {ref_wr_ready,ref_rd_valid,ref_rd_ch_idx,ref_rd_row_idx,ref_empty,ref_full,ref_completed_rows})
          $fatal(1,"FIFO metadata divergence at cycle=%0d, sent=%0d, received=%0d",cycle,sent,received);
       if(rd_valid && (rd_pixel !== ref_rd_pixel))
          $fatal(1,"FIFO payload divergence at cycle=%0d: %h vs %h",cycle,rd_pixel,ref_rd_pixel);
    end
    endtask

    initial begin
       repeat(4) @(negedge clk); rst_n=1;
       for(cycle=0;cycle<200000;cycle=cycle+1) begin
          // Hold a pending pixel until both implementations accept it.
          @(negedge clk);
          pseudo = {pseudo[30:0],pseudo[31]^pseudo[21]^pseudo[1]^pseudo[0]};
          wr_valid=(sent<TOTAL_BYTES) && (pseudo[3] || (cycle%7==0));
          wr_pixel = (sent*17+((sent>>4)*11)+31) & 8'hff;
          wr_ch_idx=sent%CHANNELS;
          rd_ready=pseudo[5] || (cycle%13==0);
          #1; compare_outputs();
          @(posedge clk);
          if (wr_valid&&wr_ready) sent=sent+1;
          if (rd_valid&&rd_ready) received=received+1;
          #1; compare_outputs();
          if(received==TOTAL_BYTES) begin
             if(sent!=TOTAL_BYTES) $fatal(1,"FIFO incomplete input");
             $display("PASS tb_fifo_sram_equivalence: WIDTH=%0d CH=%0d DEPTH=%0d bytes=%0d cycles=%0d", WIDTH,CHANNELS,DEPTH,TOTAL_BYTES,cycle);
             $finish;
          end
       end
       $fatal(1,"FIFO timeout sent=%0d received=%0d",sent,received);
    end
endmodule
