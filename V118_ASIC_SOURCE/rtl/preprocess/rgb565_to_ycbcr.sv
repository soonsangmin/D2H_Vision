module rgb565_to_ycbcr(
    input  logic [15:0] rgb565_i,
    output logic [23:0] ycbcr_o
);
    // Bit-exact integer RGB565 -> RGB888 -> YCbCr conversion.
    // V4 expresses all fixed coefficients as shifts/adds so the frontend does
    // not consume DSP blocks. Arithmetic is identical to:
    // Y  = ( 77R +150G + 29B +128)>>8
    // Cb = (-43R - 85G +128B +128)>>8 +128
    // Cr = (128R -107G - 21B +128)>>8 +128

    logic [7:0] r_u, g_u, b_u;
    logic signed [18:0] y_acc, cb_acc, cr_acc;
    logic signed [18:0] y_s, cb_s, cr_s;

    function automatic [7:0] clip8(input logic signed [18:0] v);
        begin
            if (v < 0) clip8 = 8'd0;
            else if (v > 255) clip8 = 8'd255;
            else clip8 = v[7:0];
        end
    endfunction

    always_comb begin
        r_u = {rgb565_i[15:11],rgb565_i[15:13]};
        g_u = {rgb565_i[10:5], rgb565_i[10:9]};
        b_u = {rgb565_i[4:0],  rgb565_i[4:2]};

        // 77 = 64+8+4+1; 150 = 128+16+4+2; 29 = 16+8+4+1
        y_acc = $signed({11'd0,r_u} << 6) + $signed({11'd0,r_u} << 3) +
                $signed({11'd0,r_u} << 2) + $signed({11'd0,r_u}) +
                $signed({11'd0,g_u} << 7) + $signed({11'd0,g_u} << 4) +
                $signed({11'd0,g_u} << 2) + $signed({11'd0,g_u} << 1) +
                $signed({11'd0,b_u} << 4) + $signed({11'd0,b_u} << 3) +
                $signed({11'd0,b_u} << 2) + $signed({11'd0,b_u}) + 19'sd128;

        // -43 = -(32+8+2+1), -85 = -(64+16+4+1), +128B
        cb_acc = -$signed({11'd0,r_u} << 5) - $signed({11'd0,r_u} << 3) -
                 $signed({11'd0,r_u} << 1) - $signed({11'd0,r_u}) -
                 $signed({11'd0,g_u} << 6) - $signed({11'd0,g_u} << 4) -
                 $signed({11'd0,g_u} << 2) - $signed({11'd0,g_u}) +
                 $signed({11'd0,b_u} << 7) + 19'sd128;

        // +128R, -107 = -(64+32+8+2+1), -21 = -(16+4+1)
        cr_acc =  $signed({11'd0,r_u} << 7) -
                 $signed({11'd0,g_u} << 6) - $signed({11'd0,g_u} << 5) -
                 $signed({11'd0,g_u} << 3) - $signed({11'd0,g_u} << 1) -
                 $signed({11'd0,g_u}) -
                 $signed({11'd0,b_u} << 4) - $signed({11'd0,b_u} << 2) -
                 $signed({11'd0,b_u}) + 19'sd128;

        y_s  = y_acc >>> 8;
        cb_s = (cb_acc >>> 8) + 19'sd128;
        cr_s = (cr_acc >>> 8) + 19'sd128;

        ycbcr_o = {clip8(y_s),clip8(cb_s),clip8(cr_s)};
    end
endmodule
