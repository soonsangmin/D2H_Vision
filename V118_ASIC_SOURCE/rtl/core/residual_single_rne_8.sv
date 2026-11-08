module residual_single_rne_8 (
    input  logic [63:0] main_q_i,
    input  logic [63:0] shortcut_q_i,
    input  handseg_config_pkg::residual_cfg_t cfg_i,
    output logic [63:0] q_o
);
    import handseg_config_pkg::*;

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

    function automatic [7:0] residual_lane(input [7:0] qm, input [7:0] qs);
        logic signed [8:0] cm, cs;
        logic signed [32:0] mm, ms;
        logic signed [41:0] pm, ps;
        logic signed [63:0] numerator, scaled;
        logic signed [64:0] with_zp;
        begin
            cm = $signed({1'b0,qm}) - $signed({1'b0,cfg_i.main_zero_point});
            cs = $signed({1'b0,qs}) - $signed({1'b0,cfg_i.shortcut_zero_point});
            mm = $signed({1'b0,cfg_i.main_multiplier});
            ms = $signed({1'b0,cfg_i.shortcut_multiplier});
            pm = cm * mm;
            ps = cs * ms;
            numerator = $signed({{22{pm[41]}},pm}) + $signed({{22{ps[41]}},ps});
            scaled = rne_shift64(numerator, cfg_i.shared_right_shift);
            with_zp = scaled + $signed({1'b0,cfg_i.output_zero_point});
            if (with_zp < 0) residual_lane = 8'd0;
            else if (with_zp > 255) residual_lane = 8'd255;
            else residual_lane = with_zp[7:0];
        end
    endfunction

    integer i;
    always_comb begin
        for (i=0; i<8; i=i+1)
            q_o[i*8 +: 8] = residual_lane(main_q_i[i*8 +: 8], shortcut_q_i[i*8 +: 8]);
    end
endmodule
