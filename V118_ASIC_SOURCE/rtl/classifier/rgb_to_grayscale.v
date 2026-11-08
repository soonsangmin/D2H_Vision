`timescale 1ns/1ps
`default_nettype none

// Exact RGB565 -> grayscale conversion used by the current CNN pipeline.
// Expands RGB565 fields by bit replication, then computes:
//   gray = (R8 >> 2) + (G8 >> 1) + (B8 >> 2)
// This intentionally replaces the older 77/150/29 approximation.
module rgb_to_grayscale (
    input  wire [15:0] rgb_data,
    output wire [7:0]  gray_data
);
    wire [7:0] r8 = {rgb_data[15:11], rgb_data[15:13]};
    wire [7:0] g8 = {rgb_data[10:5],  rgb_data[10:9]};
    wire [7:0] b8 = {rgb_data[4:0],   rgb_data[4:2]};

    wire [9:0] gray_sum = ({2'b00, r8} >> 2)
                        + ({2'b00, g8} >> 1)
                        + ({2'b00, b8} >> 2);

    assign gray_data = gray_sum[7:0];
endmodule

`default_nettype wire
