`timescale 1ns/1ps
// Stub CNN validates 9216 RGB565 pixels and returns class 5.
// This is a PROTOCOL test, NOT CNN model equivalence.
module cnn_ip_rgb_sobel # (parameter integer WIDTH=96, HEIGHT=96)(
    input wire clk,rst_n,frame_start,
    input wire [15:0] rgb_data,
    input wire rgb_valid,
    output wire rgb_ready,
    output reg busy,
    output reg done,
    output reg [2:0] predicted_class,
    output wire [31:0] predicted_score,
    output wire debug_input_pair_fire_o,
    output wire debug_fc_valid_o,
    output wire [2:0] debug_fc_index_o,
    output wire signed [31:0] debug_fc_value_o,
    output wire debug_fc_frame_done_o,
    output wire [6:0] debug_stage_mask_o,
    output wire [2:0] debug_active_block_o
);
    integer accepted=0;
    reg finishing=0;
    function [15:0] pixel_pattern(input integer n);
        pixel_pattern = (n ^ (n<<3) ^ 16'hA5C3);
    endfunction
    // Backpressure must advance with CLOCK cycles, not accepted pixels.
    // Otherwise accepted==3 permanently deasserts rgb_ready (deadlock).
    reg [2:0] bp_phase=3'd0;
    assign rgb_ready=busy && (bp_phase!=3'd3);
    assign predicted_score=0;
    assign debug_input_pair_fire_o=0;
    assign debug_fc_valid_o=0;
    assign debug_fc_index_o=0;
    assign debug_fc_value_o=0;
    assign debug_fc_frame_done_o=0;
    assign debug_stage_mask_o=0;
    assign debug_active_block_o=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;predicted_class<=0;accepted<=0;finishing<=0;
            bp_phase<=3'd0;
        end else begin
            bp_phase <= (bp_phase==3'd6) ? 3'd0 : bp_phase+3'd1;
            done<=0;
            if(frame_start) begin
                busy<=1;accepted<=0;finishing<=0;
            end else if(rgb_valid && rgb_ready) begin
                if(rgb_data !== pixel_pattern(accepted))
                    $fatal(1,"RGB mismatch pixel %0d got %04h want %04h",accepted,rgb_data,pixel_pattern(accepted));
                accepted<=accepted+1;
                if(accepted==9215) finishing<=1;
            end
            if(finishing) begin
                finishing<=0;busy<=0;done<=1;predicted_class<=3'd5;
            end
        end
    end
endmodule

module tb_rgb96_classifier;
    reg clk=0;always #5 clk=~clk;
    reg rstn=0,start=0,ready=0,rsp_valid=0;
    wire req_valid,rsp_ready,busy,done,alignment_error;
    wire [31:0] req_addr;
    reg [63:0] rsp_data=0;
    wire [2:0] cls;
    reg pending=0;
    integer delay_count=0,req_count=0,cycle_count=0;
    reg [63:0] pending_data=0;
    function [15:0] pixel_pattern(input integer n);
        pixel_pattern = (n ^ (n<<3) ^ 16'hA5C3);
    endfunction
    function [63:0] word_pattern(input integer n);
        word_pattern={pixel_pattern(n*4+3),pixel_pattern(n*4+2),pixel_pattern(n*4+1),pixel_pattern(n*4)};
    endfunction
    asic_rgb96_ddr_classifier dut(
        .clk_i(clk),.rstn_i(rstn),.image_ready_pulse_i(start),
        .rd_req_valid_o(req_valid),.rd_req_ready_i(ready),
        .rd_req_addr_o(req_addr),.rd_rsp_valid_i(rsp_valid),
        .rd_rsp_ready_o(rsp_ready),.rd_rsp_data_i(rsp_data),
        .busy_o(busy),.done_pulse_o(done),.predicted_class_o(cls),
        .alignment_error_o(alignment_error),
        .debug_input_pair_fire_o(),.debug_fc_valid_o(),.debug_fc_index_o(),
        .debug_fc_value_o(),.debug_fc_frame_done_o(),
        .debug_stage_mask_o(),.debug_active_block_o()
    );
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        while(!done && cycle_count<160000) begin
            @(negedge clk);
            cycle_count=cycle_count+1;
            ready=(cycle_count%11!=0 && cycle_count%11!=1);
        end
        if(!done || alignment_error || cls!=5 || req_count!=2304)
            $fatal(1,"Classifier bridge failed done=%b err=%b class=%0d reads=%0d",done,alignment_error,cls,req_count);
        $display("PASS tb_rgb96_classifier: %0d reads, 9216 pixels, class=%0d, cycles=%0d",req_count,cls,cycle_count);
        $finish;
    end
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin pending<=0;delay_count<=0;req_count<=0;rsp_valid<=0;rsp_data<=0;pending_data<=0; end
        else begin
            if(req_valid && ready) begin
                if(pending || req_addr!==32'h36000000+req_count*8)
                    $fatal(1,"Bad or overlapping read at word %0d addr %h",req_count,req_addr);
                pending<=1;
                pending_data<=word_pattern(req_count);
                delay_count<=1+(req_count%5);
                req_count<=req_count+1;
            end
            if(pending && !rsp_valid) begin
                if(delay_count>0) delay_count<=delay_count-1;
                else begin
                    rsp_valid<=1;
                    rsp_data<=pending_data;
                end
            end
            if(rsp_valid && rsp_ready) begin
                rsp_valid<=0;
                pending<=0;
            end
        end
    end
endmodule
