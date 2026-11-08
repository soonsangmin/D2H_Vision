module presence_gap_engine (
    input  logic        clk_i,
    input  logic        rstn_i,
    input  logic        start_i,

    input  logic [2:0]  src_bank_i,
    input  logic [2:0]  dst_bank_i,

    output logic        busy_o,
    output logic        done_o,

    output logic        rd_req_valid_o,
    input  logic        rd_req_ready_i,
    output logic [2:0]  rd_req_bank_o,
    output logic [16:0] rd_req_addr_o,

    input  logic        rd_rsp_valid_i,
    output logic        rd_rsp_ready_o,
    input  logic [63:0] rd_rsp_data_i,

    output logic        wr_valid_o,
    input  logic        wr_ready_i,
    output logic [2:0]  wr_bank_o,
    output logic [16:0] wr_addr_o,
    output logic [63:0] wr_data_o
);

    // V4 low-resource GAP:
    // - process one channel-group at a time
    // - only 8 accumulators instead of 160
    // - explicit group/spatial counters (no %20)
    // - one multiplier reused across 8 output lanes

    localparam integer GROUPS  = 20;
    localparam integer SPATIAL = 80;
    localparam logic [7:0] ZOUT = 8'd128;
    localparam logic [31:0] MULT = 32'd1110019115;
    localparam logic [7:0] SHIFT = 8'd34;
    localparam logic signed [31:0] CENTER_OFFSET = 32'sd10640; // 80*133

    typedef enum logic [3:0] {
        S_IDLE, S_REQ, S_WAIT, S_PREP, S_MUL, S_ROUND, S_QUANT, S_WRITE, S_DONE
    } state_t;

    state_t state_r;
    logic [2:0] src_bank_r, dst_bank_r;
    logic [4:0] group_r;
    logic [6:0] spatial_r;
    logic [2:0] lane_r;
    logic signed [31:0] sums_r [0:7];
    logic [63:0] out_word_r;

    logic [16:0] read_addr_c;
    logic signed [15:0] centered_c, centered_r;
    logic signed [48:0] product_r;
    logic signed [65:0] product_c, scaled_r;
    logic signed [66:0] with_zp_c;
    logic [7:0] lane_q_c;

    integer i;

    function automatic signed [65:0] rne_shift66(
        input signed [65:0] value,
        input [7:0] shift
    );
        logic neg;
        logic [65:0] mag, quot, rem, mask, halfv, rounded;
        begin
            if (shift == 0) rne_shift66 = value;
            else if (shift >= 66) rne_shift66 = 66'sd0;
            else begin
                neg = value[65];
                mag = neg ? (~$unsigned(value) + 66'd1) : $unsigned(value);
                quot = mag >> shift;
                mask = {66{1'b1}} >> (66-shift);
                rem = mag & mask;
                halfv = 66'd1 << (shift-1);
                rounded = quot + ((rem > halfv) || ((rem == halfv) && quot[0]));
                rne_shift66 = neg ? -$signed(rounded) : $signed(rounded);
            end
        end
    endfunction

    always_comb begin
        // addr = spatial*20 + group = spatial*16 + spatial*4 + group
        read_addr_c = ({10'd0,spatial_r} << 4) +
                      ({10'd0,spatial_r} << 2) +
                      {12'd0,group_r};

        centered_c = $signed({1'b0,sums_r[lane_r][14:0]}) - 16'sd10640;
        product_c = $signed({{17{product_r[48]}},product_r});
        with_zp_c = $signed({scaled_r[65],scaled_r}) + 67'sd128;

        if (with_zp_c < 0) lane_q_c = 8'd0;
        else if (with_zp_c > 255) lane_q_c = 8'd255;
        else lane_q_c = with_zp_c[7:0];
    end

    assign busy_o = (state_r != S_IDLE) && (state_r != S_DONE);
    assign done_o = (state_r == S_DONE);

    assign rd_req_valid_o = (state_r == S_REQ);
    assign rd_req_bank_o = src_bank_r;
    assign rd_req_addr_o = read_addr_c;
    assign rd_rsp_ready_o = (state_r == S_WAIT);

    assign wr_valid_o = (state_r == S_WRITE);
    assign wr_bank_o = dst_bank_r;
    assign wr_addr_o = {12'd0,group_r};
    assign wr_data_o = out_word_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_IDLE;
            src_bank_r <= 3'd0;
            dst_bank_r <= 3'd0;
            group_r <= 5'd0;
            spatial_r <= 7'd0;
            lane_r <= 3'd0;
            out_word_r <= 64'd0;
            centered_r <= 16'sd0;
            product_r <= 49'sd0;
            scaled_r <= 66'sd0;
            for (i=0; i<8; i=i+1)
                sums_r[i] <= 32'sd0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (start_i) begin
                        src_bank_r <= src_bank_i;
                        dst_bank_r <= dst_bank_i;
                        group_r <= 5'd0;
                        spatial_r <= 7'd0;
                        out_word_r <= 64'd0;
                        for (i=0; i<8; i=i+1)
                            sums_r[i] <= 32'sd0;
                        state_r <= S_REQ;
                    end
                end

                S_REQ: if (rd_req_ready_i) state_r <= S_WAIT;

                S_WAIT: begin
                    if (rd_rsp_valid_i) begin
                        for (i=0; i<8; i=i+1)
                            sums_r[i] <= sums_r[i] + $signed({24'd0,rd_rsp_data_i[i*8 +: 8]});

                        if (spatial_r == SPATIAL-1) begin
                            lane_r <= 3'd0;
                            out_word_r <= 64'd0;
                            state_r <= S_PREP;
                        end else begin
                            spatial_r <= spatial_r + 1'b1;
                            state_r <= S_REQ;
                        end
                    end
                end

                S_PREP: begin
                    centered_r <= centered_c;
                    state_r <= S_MUL;
                end

                S_MUL: begin
                    product_r <= centered_r * $signed({1'b0,MULT});
                    state_r <= S_ROUND;
                end

                S_ROUND: begin
                    scaled_r <= rne_shift66(product_c, SHIFT);
                    state_r <= S_QUANT;
                end

                S_QUANT: begin
                    out_word_r[lane_r*8 +: 8] <= lane_q_c;
                    if (lane_r == 3'd7)
                        state_r <= S_WRITE;
                    else begin
                        lane_r <= lane_r + 1'b1;
                        state_r <= S_PREP;
                    end
                end

                S_WRITE: begin
                    if (wr_ready_i) begin
                        if (group_r == GROUPS-1) begin
                            state_r <= S_DONE;
                        end else begin
                            group_r <= group_r + 1'b1;
                            spatial_r <= 7'd0;
                            out_word_r <= 64'd0;
                            for (i=0; i<8; i=i+1)
                                sums_r[i] <= 32'sd0;
                            state_r <= S_REQ;
                        end
                    end
                end

                S_DONE: state_r <= S_IDLE;
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
