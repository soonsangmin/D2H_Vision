`timescale 1ns/1ps
`default_nettype none

// 3x3 Sobel magnitude used by the current CNN algorithm.
// Border zero-padding is supplied by sobel_rgb_preprocessor.
// magnitude = min(abs(Gx) + abs(Gy), 255); NOT the older binary threshold.
module sobel_convolution (
    output wire signed [11:0] gradient_x,
    output wire signed [11:0] gradient_y,
    output wire        [7:0]  magnitude,

    input wire [7:0] pixel_00, pixel_01, pixel_02,
    input wire [7:0] pixel_10, pixel_11, pixel_12,
    input wire [7:0] pixel_20, pixel_21, pixel_22
);
    wire signed [11:0] p00 = {4'b0000, pixel_00};
    wire signed [11:0] p01 = {4'b0000, pixel_01};
    wire signed [11:0] p02 = {4'b0000, pixel_02};
    wire signed [11:0] p10 = {4'b0000, pixel_10};
    wire signed [11:0] p11 = {4'b0000, pixel_11};
    wire signed [11:0] p12 = {4'b0000, pixel_12};
    wire signed [11:0] p20 = {4'b0000, pixel_20};
    wire signed [11:0] p21 = {4'b0000, pixel_21};
    wire signed [11:0] p22 = {4'b0000, pixel_22};

    wire signed [11:0] gx_calc = -p00 + p02 - (p10 <<< 1)
                                + (p12 <<< 1) - p20 + p22;
    wire signed [11:0] gy_calc =  p00 + (p01 <<< 1) + p02
                                - p20 - (p21 <<< 1) - p22;

    wire [11:0] abs_gx = gx_calc[11] ? -gx_calc : gx_calc;
    wire [11:0] abs_gy = gy_calc[11] ? -gy_calc : gy_calc;
    wire [12:0] magnitude_sum = {1'b0, abs_gx} + {1'b0, abs_gy};

    assign gradient_x = gx_calc;
    assign gradient_y = gy_calc;
    assign magnitude  = (magnitude_sum > 13'd255) ? 8'hff : magnitude_sum[7:0];
endmodule

`default_nettype wire
