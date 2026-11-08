module requant_u8_vec8 (
    input  logic [63:0] q_i,
    input  logic [7:0]  src_zero_point_i,
    input  logic [31:0] multiplier_i,
    input  logic [7:0]  right_shift_i,
    input  logic [7:0]  dst_zero_point_i,
    output logic [63:0] q_o
);
    function automatic signed [63:0] rne_shift64(input signed [63:0] value, input [7:0] shift);
        logic neg;
        logic [63:0] mag, quot, rem, mask, halfv, rounded;
        begin
            if (shift == 0) rne_shift64 = value;
            else if (shift >= 64) rne_shift64 = 64'sd0;
            else begin
                neg = value[63];
                mag = neg ? (~$unsigned(value) + 64'd1) : $unsigned(value);
                quot = mag >> shift;
                mask = {64{1'b1}} >> (64-shift);
                rem = mag & mask;
                halfv = 64'd1 << (shift-1);
                rounded = quot + ((rem > halfv) || ((rem == halfv) && quot[0]));
                rne_shift64 = neg ? -$signed(rounded) : $signed(rounded);
            end
        end
    endfunction

    function automatic [7:0] lane_requant(input [7:0] q);
        logic signed [8:0] centered;
        logic signed [32:0] mult_ext;
        logic signed [41:0] prod;
        logic signed [63:0] scaled;
        logic signed [64:0] with_zp;
        begin
            centered = $signed({1'b0,q}) - $signed({1'b0,src_zero_point_i});
            mult_ext = $signed({1'b0,multiplier_i});
            prod = centered * mult_ext;
            scaled = rne_shift64({{22{prod[41]}},prod}, right_shift_i);
            with_zp = scaled + $signed({1'b0,dst_zero_point_i});
            if (with_zp < 0) lane_requant = 8'd0;
            else if (with_zp > 255) lane_requant = 8'd255;
            else lane_requant = with_zp[7:0];
        end
    endfunction

    integer i;
    always_comb begin
        for (i=0; i<8; i=i+1)
            q_o[i*8 +: 8] = lane_requant(q_i[i*8 +: 8]);
    end
endmodule
