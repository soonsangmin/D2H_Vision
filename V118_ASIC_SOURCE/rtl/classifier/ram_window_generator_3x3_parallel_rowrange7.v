`timescale 1ns/1ps
`default_nettype none
module ram_window_generator_3x3_parallel_rowrange7 #(
    parameter integer WIDTH=96,
    parameter integer HEIGHT=96,
    parameter integer CHANNELS=16,
    parameter integer STRIDE=1,
    parameter integer ROW_ADDR_WIDTH=(HEIGHT>1)?$clog2(HEIGHT):1,
    parameter integer COL_ADDR_WIDTH=(WIDTH>1)?$clog2(WIDTH):1,
    parameter integer CHANNEL_INDEX_WIDTH=(CHANNELS>1)?$clog2(CHANNELS):1
)(
    input wire clk,input wire rst_n,input wire start,
    input wire [6:0] start_row,input wire [6:0] end_row,
    output wire [COL_ADDR_WIDTH-1:0] rd_center_col,
    output wire [CHANNEL_INDEX_WIDTH-1:0] rd_channel,
    output reg [ROW_ADDR_WIDTH-1:0] rd_top_row,output reg rd_top_valid,
    output reg [ROW_ADDR_WIDTH-1:0] rd_mid_row,output reg rd_mid_valid,
    output reg [ROW_ADDR_WIDTH-1:0] rd_bot_row,output reg rd_bot_valid,
    output wire rd_valid,
    input wire [7:0] rd_p00,rd_p01,rd_p02,rd_p10,rd_p11,rd_p12,rd_p20,rd_p21,rd_p22,
    input wire rd_data_valid,
    output reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22,
    output wire [CHANNEL_INDEX_WIDTH-1:0] channel_idx,
    output reg window_valid,input wire window_ready,
    output reg busy,output reg done,output reg [15:0] window_count
);
    localparam integer OUT_WIDTH=((WIDTH-1)/STRIDE)+1;
    localparam integer OUT_HEIGHT=((HEIGHT-1)/STRIDE)+1;
    localparam integer ORW=(OUT_HEIGHT>1)?$clog2(OUT_HEIGHT):1;
    localparam integer OCW=(OUT_WIDTH>1)?$clog2(OUT_WIDTH):1;
    localparam [2:0] S_IDLE=0,S_REQ=1,S_WAIT=2,S_OUTPUT=3,S_NEXT=4,S_DONE=5;
    initial $display("[FILECHECK] WG_3X3_PARALLEL_BUILD=20261016_STAGE5_CHANNEL_ADDR_DEBUG");
    reg [2:0] state;
    reg [ORW-1:0] win_row,row_end;
    reg [OCW-1:0] win_col;
    reg [CHANNEL_INDEX_WIDTH-1:0] channel_sel;
    reg [31:0] accepted_word_count;
    integer center_row_c;
    reg [COL_ADDR_WIDTH-1:0] center_col_reg;
    assign rd_center_col=win_col*STRIDE;
    assign rd_channel=channel_sel;
    // The channel index is a direct view of the held channel selector.
    // It remains stable throughout S_OUTPUT, exactly like the window payload.
    // Avoid a separately registered output that can become disconnected/stale
    // when mixing source revisions in a simulator project.
    assign channel_idx=channel_sel;
    assign rd_valid=(state==S_REQ);
    always @* begin
        center_row_c=win_row*STRIDE;
        rd_top_valid=(center_row_c>0) && (center_row_c-1<HEIGHT);
        rd_mid_valid=(center_row_c>=0) && (center_row_c<HEIGHT);
        rd_bot_valid=(center_row_c+1>=0) && (center_row_c+1<HEIGHT);
        rd_top_row=(center_row_c>0) ? center_row_c-1 : {ROW_ADDR_WIDTH{1'b0}};
        rd_mid_row=(center_row_c>=0 && center_row_c<HEIGHT) ? center_row_c : {ROW_ADDR_WIDTH{1'b0}};
        rd_bot_row=(center_row_c+1>=0 && center_row_c+1<HEIGHT) ? center_row_c+1 : {ROW_ADDR_WIDTH{1'b0}};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; busy<=0; done<=0; window_valid<=0; window_count<=0;
            win_row<=0;win_col<=0;row_end<=0;channel_sel<=0;
            accepted_word_count<=0;
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
        end else begin
            done<=0;
            case(state)
                S_IDLE: begin
                    busy<=0;window_valid<=0;
                    if(start) begin
                        busy<=1;win_row<=(start_row<OUT_HEIGHT)?start_row:0;win_col<=0;
                        row_end<=(end_row<OUT_HEIGHT)?end_row:OUT_HEIGHT-1;
                        channel_sel<=0;window_count<=0;accepted_word_count<=0;state<=S_REQ;
                        $display("[WG3X3][START] build=20261016_STAGE5_CHANNEL_ADDR_DEBUG row=%0d end_row=%0d OUT_WIDTH=%0d CHANNELS=%0d", start_row, end_row, OUT_WIDTH, CHANNELS);
                    end
                end
                S_REQ: begin busy<=1;state<=S_WAIT; end
                S_WAIT: begin
                    busy<=1;
                    if(rd_data_valid) begin
                        p00<=rd_p00;p01<=rd_p01;p02<=rd_p02;
                        p10<=rd_p10;p11<=rd_p11;p12<=rd_p12;
                        p20<=rd_p20;p21<=rd_p21;p22<=rd_p22;
                        window_valid<=1;
                        state<=S_OUTPUT;
                    end
                end
                S_OUTPUT: begin
                    busy<=1;
                    if(window_valid && window_ready) begin
                        if ((accepted_word_count < 4) || ((accepted_word_count % 512) == 0))
                            $display("[WG3X3][ACCEPT] n=%0d internal_channel=%0d output_channel=%0d row=%0d col=%0d",
                                     accepted_word_count, channel_sel, channel_idx, win_row, win_col);
                        if ((^channel_idx) === 1'bx)
                            $display("[WG3X3][ERROR] channel_idx contains X/Z at accepted_word=%0d internal_channel=%0d",
                                     accepted_word_count, channel_sel);
                        accepted_word_count<=accepted_word_count+1'b1;
                        window_valid<=0;
                        if(channel_sel==CHANNELS-1) begin channel_sel<=0;state<=S_NEXT;end
                        else begin channel_sel<=channel_sel+1'b1;state<=S_REQ;end
                    end
                end
                S_NEXT: begin
                    busy<=1;window_count<=window_count+1'b1;
                    if((win_row==row_end)&&(win_col==OUT_WIDTH-1)) state<=S_DONE;
                    else begin
                        channel_sel<=0;
                        if(win_col==OUT_WIDTH-1) begin win_col<=0;win_row<=win_row+1'b1;end
                        else win_col<=win_col+1'b1;
                        state<=S_REQ;
                    end
                end
                S_DONE: begin
                    busy<=0; window_valid<=0; done<=1; state<=S_IDLE;
                    $display("[WG3X3][DONE] build=20261016_STAGE5_CHANNEL_ADDR_DEBUG row=%0d windows=%0d expected_windows=%0d accepted_words=%0d expected_words=%0d", win_row, window_count, OUT_WIDTH, accepted_word_count, (OUT_WIDTH*CHANNELS));
                end
                default: begin state<=S_IDLE;busy<=0;window_valid<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire