`timescale 1ns/1ps
`default_nettype none
// Hard-SRAM implementation of the unchanged V1.06 2R1W ready/valid API.
// V109 uses a SINGLE 1RW+1R copy per 64-bit block (two 32-bit macros).
// EXPLICIT DIFFERENCE vs V1.06: on read/write same logical word, the write
// is deasserted by wr_ready until the conflicting read is no longer accepted.
// Never assume macro read-during-write collision returns old data.
module v109_handseg_feature_memory_macro #(
    parameter integer B0=122880, B1=61440, B2=46080, B3=5120,
    parameter integer B4=1280, B5=384, B6=46080, B7=5120
)(
    input wire clk_i, input wire rstn_i,
    input wire rd0_req_valid_i, output wire rd0_req_ready_o,
    input wire [2:0] rd0_req_bank_i, input wire [16:0] rd0_req_addr_i,
    output wire rd0_rsp_valid_o, input wire rd0_rsp_ready_i,
    output wire [63:0] rd0_rsp_data_o,
    input wire rd1_req_valid_i, output wire rd1_req_ready_o,
    input wire [2:0] rd1_req_bank_i, input wire [16:0] rd1_req_addr_i,
    output wire rd1_rsp_valid_o, input wire rd1_rsp_ready_i,
    output wire [63:0] rd1_rsp_data_o,
    input wire wr_valid_i, output wire wr_ready_o,
    input wire [2:0] wr_bank_i, input wire [16:0] wr_addr_i,
    input wire [63:0] wr_data_i
);
    reg rd0_v_r, rd1_v_r;
    reg [2:0] sel0_r, sel1_r;
    // The OpenRAM 1RW1R model invalidates dout1 after each clock edge
    // even if csb1 is inactive. The data therefore cannot directly drive
    // a stalled ready/valid response. Capture it BEFORE that invalidation
    // at the first edge on which a valid response is backpressured.
    reg hold0_r, hold1_r;
    reg [63:0] hold0_data_r, hold1_data_r;
    wire [63:0] bank_d0 [0:7];
    wire [63:0] bank_d1 [0:7];

    assign rd0_req_ready_o = ~rd0_v_r | rd0_rsp_ready_i;
    assign rd1_req_ready_o = ~rd1_v_r | rd1_rsp_ready_i;
    wire rd0_fire = rstn_i && rd0_req_valid_i && rd0_req_ready_o;
    wire rd1_fire = rstn_i && rd1_req_valid_i && rd1_req_ready_o;
    // Same address across ports is deliberately serialized. Read is accepted;
    // write handshakes only later, once the read conflict has cleared.
    wire collide0 = rd0_fire && (wr_bank_i == rd0_req_bank_i)
                       && (wr_addr_i == rd0_req_addr_i);
    wire collide1 = rd1_fire && (wr_bank_i == rd1_req_bank_i)
                       && (wr_addr_i == rd1_req_addr_i);
    // 1RW+1R physical macro: read0 uses port0 (RW), read1 uses port1 (R).
    // A write to the SAME 512-word tile as an accepted read0 is deferred,
    // even at a different word, because read0 occupies the RW macro port.
    // Read1 may coexist with a write to a different word of the same tile;
    // exact word collision is always blocked for deterministic semantics.
    wire rd0_rw_port_busy = rd0_fire && (wr_bank_i == rd0_req_bank_i)
                             && (wr_addr_i[16:9] == rd0_req_addr_i[16:9]);
    assign wr_ready_o = ~(wr_valid_i && (rd0_rw_port_busy || collide1));
    wire wr_fire = rstn_i && wr_valid_i && wr_ready_o;

    assign rd0_rsp_valid_o = rd0_v_r;
    assign rd1_rsp_valid_o = rd1_v_r;
    assign rd0_rsp_data_o = hold0_r ? hold0_data_r : bank_d0[sel0_r];
    assign rd1_rsp_data_o = hold1_r ? hold1_data_r : bank_d1[sel1_r];

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            rd0_v_r <= 1'b0; rd1_v_r <= 1'b0;
            sel0_r <= 3'd0; sel1_r <= 3'd0;
            hold0_r <= 1'b0; hold1_r <= 1'b0;
            hold0_data_r <= 64'd0; hold1_data_r <= 64'd0;
        end else begin
            if (rd0_req_ready_o) begin
                // Old response was accepted or no response was pending;
                // allow the next accepted SRAM read to use the raw macro Q.
                rd0_v_r <= rd0_req_valid_i;
                hold0_r <= 1'b0;
                if (rd0_req_valid_i) sel0_r <= rd0_req_bank_i;
            end else if (!hold0_r) begin
                // Stalled response: at this rising edge the macro's data
                // from the PREVIOUS read is stable, before OpenRAM's
                // positive clock-to-X modeling delay invalidates dout1.
                // Capture just once and hold throughout downstream stall.
                hold0_data_r <= bank_d0[sel0_r];
                hold0_r <= 1'b1;
            end
            if (rd1_req_ready_o) begin
                rd1_v_r <= rd1_req_valid_i;
                hold1_r <= 1'b0;
                if (rd1_req_valid_i) sel1_r <= rd1_req_bank_i;
            end else if (!hold1_r) begin
                hold1_data_r <= bank_d1[sel1_r];
                hold1_r <= 1'b1;
            end
        end
    end

    v109_handseg_feature_sram_bank #(.WORDS(B0)) u_bank0 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd0),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd0),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd0),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[0]),.rd1_data_o(bank_d1[0]));
    v109_handseg_feature_sram_bank #(.WORDS(B1)) u_bank1 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd1),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd1),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd1),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[1]),.rd1_data_o(bank_d1[1]));
    v109_handseg_feature_sram_bank #(.WORDS(B2)) u_bank2 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd2),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd2),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd2),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[2]),.rd1_data_o(bank_d1[2]));
    v109_handseg_feature_sram_bank #(.WORDS(B3)) u_bank3 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd3),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd3),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd3),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[3]),.rd1_data_o(bank_d1[3]));
    v109_handseg_feature_sram_bank #(.WORDS(B4)) u_bank4 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd4),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd4),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd4),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[4]),.rd1_data_o(bank_d1[4]));
    v109_handseg_feature_sram_bank #(.WORDS(B5)) u_bank5 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd5),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd5),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd5),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[5]),.rd1_data_o(bank_d1[5]));
    v109_handseg_feature_sram_bank #(.WORDS(B6)) u_bank6 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd6),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd6),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd6),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[6]),.rd1_data_o(bank_d1[6]));
    v109_handseg_feature_sram_bank #(.WORDS(B7)) u_bank7 (
        .clk_i(clk_i),.rstn_i(rstn_i),
        .rd0_fire_i(rd0_fire && rd0_req_bank_i==3'd7),.rd0_addr_i(rd0_req_addr_i),
        .rd1_fire_i(rd1_fire && rd1_req_bank_i==3'd7),.rd1_addr_i(rd1_req_addr_i),
        .wr_fire_i(wr_fire && wr_bank_i==3'd7),.wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i),.rd0_data_o(bank_d0[7]),.rd1_data_o(bank_d1[7]));

`ifndef SYNTHESIS
    function integer depth_for_bank(input [2:0] bank);
        case (bank)
            3'd0: depth_for_bank=B0; 3'd1: depth_for_bank=B1;
            3'd2: depth_for_bank=B2; 3'd3: depth_for_bank=B3;
            3'd4: depth_for_bank=B4; 3'd5: depth_for_bank=B5;
            3'd6: depth_for_bank=B6; default: depth_for_bank=B7;
        endcase
    endfunction
    always @(posedge clk_i) if (rstn_i) begin
        if (rd0_fire && (rd0_req_addr_i >= depth_for_bank(rd0_req_bank_i)))
            $fatal(1,"V109 OOB rd0 bank=%0d addr=%0d",rd0_req_bank_i,rd0_req_addr_i);
        if (rd1_fire && (rd1_req_addr_i >= depth_for_bank(rd1_req_bank_i)))
            $fatal(1,"V109 OOB rd1 bank=%0d addr=%0d",rd1_req_bank_i,rd1_req_addr_i);
        if (wr_fire && (wr_addr_i >= depth_for_bank(wr_bank_i)))
            $fatal(1,"V109 OOB wr bank=%0d addr=%0d",wr_bank_i,wr_addr_i);
    end
`endif
endmodule
`default_nettype wire
