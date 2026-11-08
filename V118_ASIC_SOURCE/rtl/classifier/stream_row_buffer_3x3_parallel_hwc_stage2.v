`timescale 1ns/1ps
`default_nettype none

// Configurable row-bank implementation: B1-B6 select 3 row banks; B7 selects 4.
// Each implementation keeps the 3 column-interleave banks needed for nine concurrent taps.
module stream_row_buffer_3x3_parallel_hwc_stage2 #(
    parameter integer WIDTH=96,
    parameter integer HEIGHT=96,
    parameter integer CHANNELS=48,
    parameter integer ROW_WIDTH=(HEIGHT>1)?$clog2(HEIGHT):1,
    parameter integer COL_WIDTH=(WIDTH>1)?$clog2(WIDTH):1,
    parameter integer CHANNEL_INDEX_WIDTH=(CHANNELS>1)?$clog2(CHANNELS):1,
    parameter integer ROW_BANKS=4
)(
    input wire clk, input wire rst_n,
    input wire wr_valid,
    input wire [ROW_WIDTH-1:0] wr_row,
    input wire [COL_WIDTH-1:0] wr_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] wr_channel,
    input wire [7:0] wr_data,
    output wire wr_ready,
    input wire rd_valid,
    input wire [ROW_WIDTH-1:0] rd_top_row,
    input wire rd_top_valid,
    input wire [ROW_WIDTH-1:0] rd_mid_row,
    input wire rd_mid_valid,
    input wire [ROW_WIDTH-1:0] rd_bot_row,
    input wire rd_bot_valid,
    input wire [COL_WIDTH-1:0] rd_center_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] rd_channel,
    output wire [7:0] rd_p00,rd_p01,rd_p02,
    output wire [7:0] rd_p10,rd_p11,rd_p12,
    output wire [7:0] rd_p20,rd_p21,rd_p22,
    output wire rd_data_valid
);

    generate
        if (ROW_BANKS == 3) begin : g_rowbuf3
            stream_row_buffer_3x3_parallel_hwc_stage2_banks3 #(
                .WIDTH(WIDTH), .HEIGHT(HEIGHT), .CHANNELS(CHANNELS),
                .ROW_WIDTH(ROW_WIDTH), .COL_WIDTH(COL_WIDTH),
                .CHANNEL_INDEX_WIDTH(CHANNEL_INDEX_WIDTH)
            ) u_impl (
                .clk(clk), .rst_n(rst_n), .wr_valid(wr_valid),
                .wr_row(wr_row), .wr_col(wr_col), .wr_channel(wr_channel),
                .wr_data(wr_data), .wr_ready(wr_ready), .rd_valid(rd_valid),
                .rd_top_row(rd_top_row), .rd_top_valid(rd_top_valid),
                .rd_mid_row(rd_mid_row), .rd_mid_valid(rd_mid_valid),
                .rd_bot_row(rd_bot_row), .rd_bot_valid(rd_bot_valid),
                .rd_center_col(rd_center_col), .rd_channel(rd_channel),
                .rd_p00(rd_p00), .rd_p01(rd_p01), .rd_p02(rd_p02),
                .rd_p10(rd_p10), .rd_p11(rd_p11), .rd_p12(rd_p12),
                .rd_p20(rd_p20), .rd_p21(rd_p21), .rd_p22(rd_p22),
                .rd_data_valid(rd_data_valid)
            );
        end else begin : g_rowbuf4
            stream_row_buffer_3x3_parallel_hwc_stage2_banks4 #(
                .WIDTH(WIDTH), .HEIGHT(HEIGHT), .CHANNELS(CHANNELS),
                .ROW_WIDTH(ROW_WIDTH), .COL_WIDTH(COL_WIDTH),
                .CHANNEL_INDEX_WIDTH(CHANNEL_INDEX_WIDTH)
            ) u_impl (
                .clk(clk), .rst_n(rst_n), .wr_valid(wr_valid),
                .wr_row(wr_row), .wr_col(wr_col), .wr_channel(wr_channel),
                .wr_data(wr_data), .wr_ready(wr_ready), .rd_valid(rd_valid),
                .rd_top_row(rd_top_row), .rd_top_valid(rd_top_valid),
                .rd_mid_row(rd_mid_row), .rd_mid_valid(rd_mid_valid),
                .rd_bot_row(rd_bot_row), .rd_bot_valid(rd_bot_valid),
                .rd_center_col(rd_center_col), .rd_channel(rd_channel),
                .rd_p00(rd_p00), .rd_p01(rd_p01), .rd_p02(rd_p02),
                .rd_p10(rd_p10), .rd_p11(rd_p11), .rd_p12(rd_p12),
                .rd_p20(rd_p20), .rd_p21(rd_p21), .rd_p22(rd_p22),
                .rd_data_valid(rd_data_valid)
            );
        end
    endgenerate

    initial begin
        if (ROW_BANKS != 3 && ROW_BANKS != 4) begin
            $display("[ROWBUF][ERROR] ROW_BANKS must be 3 or 4");
            $finish;
        end
        $display("[FILECHECK] ROWBUF_ALMOPT_V20_ROW_BANKS=%0d WIDTH=%0d HEIGHT=%0d CHANNELS=%0d",
                 ROW_BANKS, WIDTH, HEIGHT, CHANNELS);
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Three logical row banks x three column-interleave banks. B1-B6 do not accept row look-ahead,
// so three physical rows are sufficient. Rows use row mod 3; columns use column mod 3.
module stream_row_buffer_3x3_parallel_hwc_stage2_banks3 #(
    parameter integer WIDTH=96,
    parameter integer HEIGHT=96,
    parameter integer CHANNELS=48,
    parameter integer ROW_WIDTH=(HEIGHT>1)?$clog2(HEIGHT):1,
    parameter integer COL_WIDTH=(WIDTH>1)?$clog2(WIDTH):1,
    parameter integer CHANNEL_INDEX_WIDTH=(CHANNELS>1)?$clog2(CHANNELS):1
)(
    input wire clk, input wire rst_n,
    input wire wr_valid,
    input wire [ROW_WIDTH-1:0] wr_row,
    input wire [COL_WIDTH-1:0] wr_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] wr_channel,
    input wire [7:0] wr_data,
    output wire wr_ready,
    input wire rd_valid,
    input wire [ROW_WIDTH-1:0] rd_top_row,
    input wire rd_top_valid,
    input wire [ROW_WIDTH-1:0] rd_mid_row,
    input wire rd_mid_valid,
    input wire [ROW_WIDTH-1:0] rd_bot_row,
    input wire rd_bot_valid,
    input wire [COL_WIDTH-1:0] rd_center_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] rd_channel,
    output wire [7:0] rd_p00,rd_p01,rd_p02,
    output wire [7:0] rd_p10,rd_p11,rd_p12,
    output wire [7:0] rd_p20,rd_p21,rd_p22,
    output reg rd_data_valid
);
    initial begin
        $display("[FILECHECK] ROWBUF_ALMOPT_V20_THREE_ROW_BANKS WIDTH=%0d HEIGHT=%0d CHANNELS=%0d",
                 WIDTH, HEIGHT, CHANNELS);
    end

    localparam integer COL_GROUPS=(WIDTH+2)/3;
    localparam integer DEPTH=COL_GROUPS*CHANNELS;
    localparam integer ADDR_WIDTH=(DEPTH>1)?$clog2(DEPTH):1;
    // Keep column arithmetic no wider than the actual column index. The old
    // integer-signed intermediates caused Quartus to infer a 32-bit divider.
    localparam integer COL_CALC_W=(COL_WIDTH<2)?2:COL_WIDTH;
    localparam [ADDR_WIDTH-1:0] CHANNELS_ADDR=CHANNELS;

    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m00 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m01 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m02 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m10 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m11 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m12 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m20 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m21 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m22 [0:DEPTH-1];
    reg [7:0] q00;
    reg [7:0] q01;
    reg [7:0] q02;
    reg [7:0] q10;
    reg [7:0] q11;
    reg [7:0] q12;
    reg [7:0] q20;
    reg [7:0] q21;
    reg [7:0] q22;
    reg [ROW_WIDTH-1:0] tag0,tag1,tag2;
    reg v0,v1,v2;
    reg [1:0] wr_slot_ring;
    reg [1:0] top_slot_q,mid_slot_q,bot_slot_q;
    reg top_hit_q,mid_hit_q,bot_hit_q;
    reg [1:0] left_slot_q,center_slot_q,right_slot_q;
    reg left_hit_q,center_hit_q,right_hit_q;
    reg [ADDR_WIDTH-1:0] addr0,addr1,addr2;
    wire [ADDR_WIDTH-1:0] wr_addr;
    wire [COL_CALC_W-1:0] wr_col_ext=wr_col;
    wire [COL_CALC_W-1:0] rd_center_col_ext=rd_center_col;
    // Shared divide/modulo-by-3 implementation. Quartus previously inferred
    // separate quotient and remainder dividers for each of wr_col and
    // rd_center_col (four divider networks per instance). This restoring
    // divider produces quotient and remainder from the same narrow logic.
    wire [COL_CALC_W+1:0] wr_divmod3;
    wire [COL_CALC_W+1:0] center_divmod3;
    wire [COL_WIDTH-1:0] wr_group;
    wire [1:0] wr_col_mod3;
    wire [COL_WIDTH-1:0] center_group_w;
    wire [1:0] center_mod3_w;

    assign wr_divmod3     = divmod3_shared(wr_col_ext);
    assign center_divmod3 = divmod3_shared(rd_center_col_ext);
    assign wr_group       = wr_divmod3[COL_CALC_W+1:2];
    assign wr_col_mod3    = wr_divmod3[1:0];
    assign center_group_w = center_divmod3[COL_CALC_W+1:2];
    assign center_mod3_w   = center_divmod3[1:0];
    reg [COL_WIDTH-1:0] left_group_c,center_group_c,right_group_c;
    assign wr_ready=rst_n;

    // Exact unsigned quotient/remainder by 3 for any COL_CALC_W-bit input.
    // At each stage trial = 2*remainder + next_input_bit (0..5). A quotient
    // bit is one iff trial >= 3. Since remainder is always 0..2, the compare
    // simplifies to rem[1] | (rem[0] & value[bit_idx]); the new remainder is
    // trial-3 when quotient=1, expressed as the low two bits plus one modulo 4.
    // The loop unrolls to small shared logic; it does not add a clock cycle.
    function [COL_CALC_W+1:0] divmod3_shared;
        input [COL_CALC_W-1:0] value;
        integer bit_idx;
        reg [COL_CALC_W-1:0] quotient;
        reg [1:0] rem3;
        reg [2:0] trial;
        reg qbit;
        begin
            quotient = {COL_CALC_W{1'b0}};
            rem3 = 2'd0;
            trial = 3'd0;
            qbit = 1'b0;
            for (bit_idx = COL_CALC_W-1; bit_idx >= 0; bit_idx = bit_idx-1) begin
                trial = {rem3, value[bit_idx]};
                qbit = trial[2] | (trial[1] & trial[0]);
                quotient[bit_idx] = qbit;
                if (qbit)
                    rem3 = trial[1:0] + 2'd1;
                else
                    rem3 = trial[1:0];
            end
            divmod3_shared = {quotient, rem3};
        end
    endfunction

    // Map a row tag to its physical slot without a modulo/divider in the
    // read-address path. The write slot advances once per completed row.
    function [1:0] slot_of;
        input [ROW_WIDTH-1:0] row;
        begin
            if (v0 && (tag0 == row))
                slot_of = 2'd0;
            else if (v1 && (tag1 == row))
                slot_of = 2'd1;
            else if (v2 && (tag2 == row))
                slot_of = 2'd2;
            else
                slot_of = 2'd0;
        end
    endfunction
    function row_tag_hit;
        input [ROW_WIDTH-1:0] row;
        begin
            case(slot_of(row))
                2'd0: row_tag_hit=v0 && (tag0==row);
                2'd1: row_tag_hit=v1 && (tag1==row);
                2'd2: row_tag_hit=v2 && (tag2==row);
                default: row_tag_hit=1'b0;
            endcase
        end
    endfunction
    function [ADDR_WIDTH-1:0] group_channel_addr;
        input [COL_WIDTH-1:0] col_group;
        input [CHANNEL_INDEX_WIDTH-1:0] channel;
        reg [ADDR_WIDTH-1:0] group_sized;
        reg [ADDR_WIDTH-1:0] channel_sized;
        begin
            group_sized=col_group;
            channel_sized=channel;
            // Both operands are bounded to the actual RAM address width.
            group_channel_addr=(group_sized*CHANNELS_ADDR)+channel_sized;
        end
    endfunction
    assign wr_addr=group_channel_addr(wr_group,wr_channel);

    reg [1:0] left_slot_tmp,center_slot_tmp,right_slot_tmp;
    reg left_hit_tmp,center_hit_tmp,right_hit_tmp;

    // Decode the three adjacent columns from one narrow center-column
    // quotient/remainder. Avoid signed 32-bit integer % and / operators,
    // which created the long Mod0 divider path in TimeQuest.
    always @* begin
        left_group_c   = (center_mod3_w==0) ? (center_group_w-1'b1) : center_group_w;
        center_group_c = center_group_w;
        right_group_c  = (center_mod3_w==2) ? (center_group_w+1'b1) : center_group_w;

        left_hit_tmp   = (rd_center_col != 0) && (rd_center_col <= WIDTH);
        center_hit_tmp = (rd_center_col < WIDTH);
        right_hit_tmp  = (rd_center_col < (WIDTH-1));

        case (center_mod3_w)
            2'd0: begin
                left_slot_tmp=2'd2;
                center_slot_tmp=2'd0;
                right_slot_tmp=2'd1;
            end
            2'd1: begin
                left_slot_tmp=2'd0;
                center_slot_tmp=2'd1;
                right_slot_tmp=2'd2;
            end
            default: begin
                left_slot_tmp=2'd1;
                center_slot_tmp=2'd2;
                right_slot_tmp=2'd0;
            end
        endcase

        addr0=0; addr1=0; addr2=0;
        if (left_hit_tmp) begin
            case(left_slot_tmp)
                2'd0: addr0=group_channel_addr(left_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(left_group_c,rd_channel);
                default: addr2=group_channel_addr(left_group_c,rd_channel);
            endcase
        end
        if (center_hit_tmp) begin
            case(center_slot_tmp)
                2'd0: addr0=group_channel_addr(center_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(center_group_c,rd_channel);
                default: addr2=group_channel_addr(center_group_c,rd_channel);
            endcase
        end
        if (right_hit_tmp) begin
            case(right_slot_tmp)
                2'd0: addr0=group_channel_addr(right_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(right_group_c,rd_channel);
                default: addr2=group_channel_addr(right_group_c,rd_channel);
            endcase
        end
    end


    // One write per accepted HWC scalar. Separate arrays preserve independent RAM inference.
    always @(posedge clk) begin
        if(rst_n && wr_valid && wr_ready && wr_row<HEIGHT && wr_col<WIDTH && wr_channel<CHANNELS) begin
            case(wr_slot_ring)

                2'd0: case(wr_col_mod3)

                    0: m00[wr_addr] <= wr_data;

                    1: m01[wr_addr] <= wr_data;

                    2: m02[wr_addr] <= wr_data;

                    default: begin end
                endcase

                2'd1: case(wr_col_mod3)

                    0: m10[wr_addr] <= wr_data;

                    1: m11[wr_addr] <= wr_data;

                    2: m12[wr_addr] <= wr_data;

                    default: begin end
                endcase

                2'd2: case(wr_col_mod3)

                    0: m20[wr_addr] <= wr_data;

                    1: m21[wr_addr] <= wr_data;

                    2: m22[wr_addr] <= wr_data;

                    default: begin end
                endcase

                default: begin end
            endcase
        end
        if(rst_n && rd_valid) begin

            q00 <= m00[addr0];

            q01 <= m01[addr1];

            q02 <= m02[addr2];

            q10 <= m10[addr0];

            q11 <= m11[addr1];

            q12 <= m12[addr2];

            q20 <= m20[addr0];

            q21 <= m21[addr1];

            q22 <= m22[addr2];

        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tag0<=0;tag1<=0;tag2<=0;
            v0<=0;v1<=0;v2<=0;
            wr_slot_ring<=2'd0;
            top_slot_q<=0;mid_slot_q<=0;bot_slot_q<=0;
            top_hit_q<=0;mid_hit_q<=0;bot_hit_q<=0;
            left_slot_q<=0;center_slot_q<=0;right_slot_q<=0;
            left_hit_q<=0;center_hit_q<=0;right_hit_q<=0;
            rd_data_valid<=0;
        end else begin
            rd_data_valid<=rd_valid;
            if(wr_valid && wr_ready && wr_row<HEIGHT && wr_col<WIDTH && wr_channel<CHANNELS && wr_col==0 && wr_channel==0) begin
                case(wr_slot_ring)
                    2'd0: begin tag0<=wr_row;v0<=1;end
                    2'd1: begin tag1<=wr_row;v1<=1;end
                    2'd2: begin tag2<=wr_row;v2<=1;end
                    default: begin end
                endcase
            end
            // Advance the physical ring after the final byte of each row.
            // The RAM write on this edge still uses the current slot.
            if (wr_valid && wr_ready && wr_row<HEIGHT && wr_col<WIDTH &&
                wr_channel<CHANNELS && wr_col==(WIDTH-1) &&
                wr_channel==(CHANNELS-1)) begin
                if (wr_slot_ring == 2'd2)
                    wr_slot_ring <= 2'd0;
                else
                    wr_slot_ring <= wr_slot_ring + 1'b1;
            end
            if(rd_valid) begin
                top_slot_q<=slot_of(rd_top_row); mid_slot_q<=slot_of(rd_mid_row); bot_slot_q<=slot_of(rd_bot_row);
                top_hit_q<=rd_top_valid && row_tag_hit(rd_top_row);
                mid_hit_q<=rd_mid_valid && row_tag_hit(rd_mid_row);
                bot_hit_q<=rd_bot_valid && row_tag_hit(rd_bot_row);
                left_slot_q<=left_slot_tmp; center_slot_q<=center_slot_tmp; right_slot_q<=right_slot_tmp;
                left_hit_q<=left_hit_tmp; center_hit_q<=center_hit_tmp; right_hit_q<=right_hit_tmp;
            end
        end
    end

    // Factor column-bank selection from row-bank selection.
    function [7:0] q_col_select;
        input [1:0] c;
        input [7:0] v0, v1, v2;
        begin
            case (c)
                2'd0: q_col_select = v0;
                2'd1: q_col_select = v1;
                2'd2: q_col_select = v2;
                default: q_col_select = 8'd0;
            endcase
        end
    endfunction

    function [7:0] q_row_select;
        input [1:0] r;
        input [7:0] v0, v1, v2;
        begin
            case (r)
                2'd0: q_row_select = v0;
                2'd1: q_row_select = v1;
                2'd2: q_row_select = v2;
                default: q_row_select = 8'd0;
            endcase
        end
    endfunction

    wire [7:0] left_r0   = q_col_select(left_slot_q,   q00, q01, q02);
    wire [7:0] left_r1   = q_col_select(left_slot_q,   q10, q11, q12);
    wire [7:0] left_r2   = q_col_select(left_slot_q,   q20, q21, q22);
    wire [7:0] center_r0 = q_col_select(center_slot_q, q00, q01, q02);
    wire [7:0] center_r1 = q_col_select(center_slot_q, q10, q11, q12);
    wire [7:0] center_r2 = q_col_select(center_slot_q, q20, q21, q22);
    wire [7:0] right_r0  = q_col_select(right_slot_q,  q00, q01, q02);
    wire [7:0] right_r1  = q_col_select(right_slot_q,  q10, q11, q12);
    wire [7:0] right_r2  = q_col_select(right_slot_q,  q20, q21, q22);

    assign rd_p00 = (top_hit_q && left_hit_q) ?
        q_row_select(top_slot_q, left_r0, left_r1, left_r2) : 8'd0;
    assign rd_p01 = (top_hit_q && center_hit_q) ?
        q_row_select(top_slot_q, center_r0, center_r1, center_r2) : 8'd0;
    assign rd_p02 = (top_hit_q && right_hit_q) ?
        q_row_select(top_slot_q, right_r0, right_r1, right_r2) : 8'd0;

    assign rd_p10 = (mid_hit_q && left_hit_q) ?
        q_row_select(mid_slot_q, left_r0, left_r1, left_r2) : 8'd0;
    assign rd_p11 = (mid_hit_q && center_hit_q) ?
        q_row_select(mid_slot_q, center_r0, center_r1, center_r2) : 8'd0;
    assign rd_p12 = (mid_hit_q && right_hit_q) ?
        q_row_select(mid_slot_q, right_r0, right_r1, right_r2) : 8'd0;

    assign rd_p20 = (bot_hit_q && left_hit_q) ?
        q_row_select(bot_slot_q, left_r0, left_r1, left_r2) : 8'd0;
    assign rd_p21 = (bot_hit_q && center_hit_q) ?
        q_row_select(bot_slot_q, center_r0, center_r1, center_r2) : 8'd0;
    assign rd_p22 = (bot_hit_q && right_hit_q) ?
        q_row_select(bot_slot_q, right_r0, right_r1, right_r2) : 8'd0;

endmodule
`default_nettype wire
`timescale 1ns/1ps
`default_nettype none

// Configurable row-bank implementation: B1-B6 select 3 row banks; B7 selects 4.
// Each implementation keeps the 3 column-interleave banks needed for nine concurrent taps.
module stream_row_buffer_3x3_parallel_hwc_stage2_banks4 #(
    parameter integer WIDTH=96,
    parameter integer HEIGHT=96,
    parameter integer CHANNELS=48,
    parameter integer ROW_WIDTH=(HEIGHT>1)?$clog2(HEIGHT):1,
    parameter integer COL_WIDTH=(WIDTH>1)?$clog2(WIDTH):1,
    parameter integer CHANNEL_INDEX_WIDTH=(CHANNELS>1)?$clog2(CHANNELS):1
)(
    input wire clk, input wire rst_n,
    input wire wr_valid,
    input wire [ROW_WIDTH-1:0] wr_row,
    input wire [COL_WIDTH-1:0] wr_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] wr_channel,
    input wire [7:0] wr_data,
    output wire wr_ready,
    input wire rd_valid,
    input wire [ROW_WIDTH-1:0] rd_top_row,
    input wire rd_top_valid,
    input wire [ROW_WIDTH-1:0] rd_mid_row,
    input wire rd_mid_valid,
    input wire [ROW_WIDTH-1:0] rd_bot_row,
    input wire rd_bot_valid,
    input wire [COL_WIDTH-1:0] rd_center_col,
    input wire [CHANNEL_INDEX_WIDTH-1:0] rd_channel,
    output wire [7:0] rd_p00,rd_p01,rd_p02,
    output wire [7:0] rd_p10,rd_p11,rd_p12,
    output wire [7:0] rd_p20,rd_p21,rd_p22,
    output reg rd_data_valid
);
    initial begin
        $display("[FILECHECK] ROWBUF_ALMOPT_V3_SHARED_DIVMOD3_FACTORED_QMUX WIDTH=%0d HEIGHT=%0d CHANNELS=%0d",
                 WIDTH, HEIGHT, CHANNELS);
    end

    localparam integer COL_GROUPS=(WIDTH+2)/3;
    localparam integer DEPTH=COL_GROUPS*CHANNELS;
    localparam integer ADDR_WIDTH=(DEPTH>1)?$clog2(DEPTH):1;
    // Keep column arithmetic no wider than the actual column index. The old
    // integer-signed intermediates caused Quartus to infer a 32-bit divider.
    localparam integer COL_CALC_W=(COL_WIDTH<2)?2:COL_WIDTH;
    localparam [ADDR_WIDTH-1:0] CHANNELS_ADDR=CHANNELS;

    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m00 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m01 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m02 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m10 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m11 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m12 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m20 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m21 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m22 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m30 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m31 [0:DEPTH-1];
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] m32 [0:DEPTH-1];
    reg [7:0] q00;
    reg [7:0] q01;
    reg [7:0] q02;
    reg [7:0] q10;
    reg [7:0] q11;
    reg [7:0] q12;
    reg [7:0] q20;
    reg [7:0] q21;
    reg [7:0] q22;
    reg [7:0] q30;
    reg [7:0] q31;
    reg [7:0] q32;
    reg [ROW_WIDTH-1:0] tag0,tag1,tag2,tag3;
    reg v0,v1,v2,v3;
    reg [1:0] top_slot_q,mid_slot_q,bot_slot_q;
    reg top_hit_q,mid_hit_q,bot_hit_q;
    reg [1:0] left_slot_q,center_slot_q,right_slot_q;
    reg left_hit_q,center_hit_q,right_hit_q;
    reg [ADDR_WIDTH-1:0] addr0,addr1,addr2;
    wire [ADDR_WIDTH-1:0] wr_addr;
    wire [COL_CALC_W-1:0] wr_col_ext=wr_col;
    wire [COL_CALC_W-1:0] rd_center_col_ext=rd_center_col;
    // Shared divide/modulo-by-3 implementation. Quartus previously inferred
    // separate quotient and remainder dividers for each of wr_col and
    // rd_center_col (four divider networks per instance). This restoring
    // divider produces quotient and remainder from the same narrow logic.
    wire [COL_CALC_W+1:0] wr_divmod3;
    wire [COL_CALC_W+1:0] center_divmod3;
    wire [COL_WIDTH-1:0] wr_group;
    wire [1:0] wr_col_mod3;
    wire [COL_WIDTH-1:0] center_group_w;
    wire [1:0] center_mod3_w;

    assign wr_divmod3     = divmod3_shared(wr_col_ext);
    assign center_divmod3 = divmod3_shared(rd_center_col_ext);
    assign wr_group       = wr_divmod3[COL_CALC_W+1:2];
    assign wr_col_mod3    = wr_divmod3[1:0];
    assign center_group_w = center_divmod3[COL_CALC_W+1:2];
    assign center_mod3_w   = center_divmod3[1:0];
    reg [COL_WIDTH-1:0] left_group_c,center_group_c,right_group_c;
    assign wr_ready=rst_n;

    // Exact unsigned quotient/remainder by 3 for any COL_CALC_W-bit input.
    // At each stage trial = 2*remainder + next_input_bit (0..5). A quotient
    // bit is one iff trial >= 3. Since remainder is always 0..2, the compare
    // simplifies to rem[1] | (rem[0] & value[bit_idx]); the new remainder is
    // trial-3 when quotient=1, expressed as the low two bits plus one modulo 4.
    // The loop unrolls to small shared logic; it does not add a clock cycle.
    function [COL_CALC_W+1:0] divmod3_shared;
        input [COL_CALC_W-1:0] value;
        integer bit_idx;
        reg [COL_CALC_W-1:0] quotient;
        reg [1:0] rem3;
        reg [2:0] trial;
        reg qbit;
        begin
            quotient = {COL_CALC_W{1'b0}};
            rem3 = 2'd0;
            trial = 3'd0;
            qbit = 1'b0;
            for (bit_idx = COL_CALC_W-1; bit_idx >= 0; bit_idx = bit_idx-1) begin
                trial = {rem3, value[bit_idx]};
                qbit = trial[2] | (trial[1] & trial[0]);
                quotient[bit_idx] = qbit;
                if (qbit)
                    rem3 = trial[1:0] + 2'd1;
                else
                    rem3 = trial[1:0];
            end
            divmod3_shared = {quotient, rem3};
        end
    endfunction

    function [1:0] slot_of;
        input [ROW_WIDTH-1:0] row;
        begin slot_of=row[1:0]; end
    endfunction
    function row_tag_hit;
        input [ROW_WIDTH-1:0] row;
        begin
            case(slot_of(row))
                2'd0: row_tag_hit=v0 && (tag0==row);
                2'd1: row_tag_hit=v1 && (tag1==row);
                2'd2: row_tag_hit=v2 && (tag2==row);
                default: row_tag_hit=v3 && (tag3==row);
            endcase
        end
    endfunction
    function [ADDR_WIDTH-1:0] group_channel_addr;
        input [COL_WIDTH-1:0] col_group;
        input [CHANNEL_INDEX_WIDTH-1:0] channel;
        reg [ADDR_WIDTH-1:0] group_sized;
        reg [ADDR_WIDTH-1:0] channel_sized;
        begin
            group_sized=col_group;
            channel_sized=channel;
            // Both operands are bounded to the actual RAM address width.
            group_channel_addr=(group_sized*CHANNELS_ADDR)+channel_sized;
        end
    endfunction
    assign wr_addr=group_channel_addr(wr_group,wr_channel);

    reg [1:0] left_slot_tmp,center_slot_tmp,right_slot_tmp;
    reg left_hit_tmp,center_hit_tmp,right_hit_tmp;

    // Decode the three adjacent columns from one narrow center-column
    // quotient/remainder. Avoid signed 32-bit integer % and / operators,
    // which created the long Mod0 divider path in TimeQuest.
    always @* begin
        left_group_c   = (center_mod3_w==0) ? (center_group_w-1'b1) : center_group_w;
        center_group_c = center_group_w;
        right_group_c  = (center_mod3_w==2) ? (center_group_w+1'b1) : center_group_w;

        left_hit_tmp   = (rd_center_col != 0) && (rd_center_col <= WIDTH);
        center_hit_tmp = (rd_center_col < WIDTH);
        right_hit_tmp  = (rd_center_col < (WIDTH-1));

        case (center_mod3_w)
            2'd0: begin
                left_slot_tmp=2'd2;
                center_slot_tmp=2'd0;
                right_slot_tmp=2'd1;
            end
            2'd1: begin
                left_slot_tmp=2'd0;
                center_slot_tmp=2'd1;
                right_slot_tmp=2'd2;
            end
            default: begin
                left_slot_tmp=2'd1;
                center_slot_tmp=2'd2;
                right_slot_tmp=2'd0;
            end
        endcase

        addr0=0; addr1=0; addr2=0;
        if (left_hit_tmp) begin
            case(left_slot_tmp)
                2'd0: addr0=group_channel_addr(left_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(left_group_c,rd_channel);
                default: addr2=group_channel_addr(left_group_c,rd_channel);
            endcase
        end
        if (center_hit_tmp) begin
            case(center_slot_tmp)
                2'd0: addr0=group_channel_addr(center_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(center_group_c,rd_channel);
                default: addr2=group_channel_addr(center_group_c,rd_channel);
            endcase
        end
        if (right_hit_tmp) begin
            case(right_slot_tmp)
                2'd0: addr0=group_channel_addr(right_group_c,rd_channel);
                2'd1: addr1=group_channel_addr(right_group_c,rd_channel);
                default: addr2=group_channel_addr(right_group_c,rd_channel);
            endcase
        end
    end


    // One write per accepted HWC scalar. Separate arrays preserve independent RAM inference.
    always @(posedge clk) begin
        if(rst_n && wr_valid && wr_ready && wr_row<HEIGHT && wr_col<WIDTH && wr_channel<CHANNELS) begin
            case(slot_of(wr_row))

                2'd0: case(wr_col_mod3)

                    0: m00[wr_addr] <= wr_data;

                    1: m01[wr_addr] <= wr_data;

                    2: m02[wr_addr] <= wr_data;

                    default: begin end
                endcase

                2'd1: case(wr_col_mod3)

                    0: m10[wr_addr] <= wr_data;

                    1: m11[wr_addr] <= wr_data;

                    2: m12[wr_addr] <= wr_data;

                    default: begin end
                endcase

                2'd2: case(wr_col_mod3)

                    0: m20[wr_addr] <= wr_data;

                    1: m21[wr_addr] <= wr_data;

                    2: m22[wr_addr] <= wr_data;

                    default: begin end
                endcase

                2'd3: case(wr_col_mod3)

                    0: m30[wr_addr] <= wr_data;

                    1: m31[wr_addr] <= wr_data;

                    2: m32[wr_addr] <= wr_data;

                    default: begin end
                endcase

                default: begin end
            endcase
        end
        if(rst_n && rd_valid) begin

            q00 <= m00[addr0];

            q01 <= m01[addr1];

            q02 <= m02[addr2];

            q10 <= m10[addr0];

            q11 <= m11[addr1];

            q12 <= m12[addr2];

            q20 <= m20[addr0];

            q21 <= m21[addr1];

            q22 <= m22[addr2];

            q30 <= m30[addr0];

            q31 <= m31[addr1];

            q32 <= m32[addr2];

        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tag0<=0;tag1<=0;tag2<=0;tag3<=0;
            v0<=0;v1<=0;v2<=0;v3<=0;
            top_slot_q<=0;mid_slot_q<=0;bot_slot_q<=0;
            top_hit_q<=0;mid_hit_q<=0;bot_hit_q<=0;
            left_slot_q<=0;center_slot_q<=0;right_slot_q<=0;
            left_hit_q<=0;center_hit_q<=0;right_hit_q<=0;
            rd_data_valid<=0;
        end else begin
            rd_data_valid<=rd_valid;
            if(wr_valid && wr_ready && wr_row<HEIGHT && wr_col<WIDTH && wr_channel<CHANNELS && wr_col==0 && wr_channel==0) begin
                case(slot_of(wr_row))
                    2'd0: begin tag0<=wr_row;v0<=1;end
                    2'd1: begin tag1<=wr_row;v1<=1;end
                    2'd2: begin tag2<=wr_row;v2<=1;end
                    2'd3: begin tag3<=wr_row;v3<=1;end
                endcase
            end
            if(rd_valid) begin
                top_slot_q<=slot_of(rd_top_row); mid_slot_q<=slot_of(rd_mid_row); bot_slot_q<=slot_of(rd_bot_row);
                top_hit_q<=rd_top_valid && row_tag_hit(rd_top_row);
                mid_hit_q<=rd_mid_valid && row_tag_hit(rd_mid_row);
                bot_hit_q<=rd_bot_valid && row_tag_hit(rd_bot_row);
                left_slot_q<=left_slot_tmp; center_slot_q<=center_slot_tmp; right_slot_q<=right_slot_tmp;
                left_hit_q<=left_hit_tmp; center_hit_q<=center_hit_tmp; right_hit_q<=right_hit_tmp;
            end
        end
    end

    // Factor column-bank selection from row-bank selection. The old q_select
    // built a 4-row x 3-column mux independently for each of the nine outputs.
    // Column selectors are shared by the three output rows, so select columns
    // once per physical row bank and then select the row for each output.
    function [7:0] q_col_select;
        input [1:0] c;
        input [7:0] v0, v1, v2;
        begin
            case (c)
                2'd0: q_col_select = v0;
                2'd1: q_col_select = v1;
                2'd2: q_col_select = v2;
                default: q_col_select = 8'd0;
            endcase
        end
    endfunction

    function [7:0] q_row_select;
        input [1:0] r;
        input [7:0] v0, v1, v2, v3;
        begin
            case (r)
                2'd0: q_row_select = v0;
                2'd1: q_row_select = v1;
                2'd2: q_row_select = v2;
                2'd3: q_row_select = v3;
                default: q_row_select = 8'd0;
            endcase
        end
    endfunction

    wire [7:0] left_r0   = q_col_select(left_slot_q,   q00, q01, q02);
    wire [7:0] left_r1   = q_col_select(left_slot_q,   q10, q11, q12);
    wire [7:0] left_r2   = q_col_select(left_slot_q,   q20, q21, q22);
    wire [7:0] left_r3   = q_col_select(left_slot_q,   q30, q31, q32);
    wire [7:0] center_r0 = q_col_select(center_slot_q, q00, q01, q02);
    wire [7:0] center_r1 = q_col_select(center_slot_q, q10, q11, q12);
    wire [7:0] center_r2 = q_col_select(center_slot_q, q20, q21, q22);
    wire [7:0] center_r3 = q_col_select(center_slot_q, q30, q31, q32);
    wire [7:0] right_r0  = q_col_select(right_slot_q,  q00, q01, q02);
    wire [7:0] right_r1  = q_col_select(right_slot_q,  q10, q11, q12);
    wire [7:0] right_r2  = q_col_select(right_slot_q,  q20, q21, q22);
    wire [7:0] right_r3  = q_col_select(right_slot_q,  q30, q31, q32);

    assign rd_p00 = (top_hit_q && left_hit_q) ?
        q_row_select(top_slot_q, left_r0, left_r1, left_r2, left_r3) : 8'd0;
    assign rd_p01 = (top_hit_q && center_hit_q) ?
        q_row_select(top_slot_q, center_r0, center_r1, center_r2, center_r3) : 8'd0;
    assign rd_p02 = (top_hit_q && right_hit_q) ?
        q_row_select(top_slot_q, right_r0, right_r1, right_r2, right_r3) : 8'd0;

    assign rd_p10 = (mid_hit_q && left_hit_q) ?
        q_row_select(mid_slot_q, left_r0, left_r1, left_r2, left_r3) : 8'd0;
    assign rd_p11 = (mid_hit_q && center_hit_q) ?
        q_row_select(mid_slot_q, center_r0, center_r1, center_r2, center_r3) : 8'd0;
    assign rd_p12 = (mid_hit_q && right_hit_q) ?
        q_row_select(mid_slot_q, right_r0, right_r1, right_r2, right_r3) : 8'd0;

    assign rd_p20 = (bot_hit_q && left_hit_q) ?
        q_row_select(bot_slot_q, left_r0, left_r1, left_r2, left_r3) : 8'd0;
    assign rd_p21 = (bot_hit_q && center_hit_q) ?
        q_row_select(bot_slot_q, center_r0, center_r1, center_r2, center_r3) : 8'd0;
    assign rd_p22 = (bot_hit_q && right_hit_q) ?
        q_row_select(bot_slot_q, right_r0, right_r1, right_r2, right_r3) : 8'd0;

endmodule
`default_nettype wire