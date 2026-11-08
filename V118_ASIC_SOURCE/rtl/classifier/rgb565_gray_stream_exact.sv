`timescale 1ns/1ps


// Exact grayscale for a source that is ALREADY packed RGB565.
// No RGB888->RGB565 conversion/quantization is performed by this RTL.
// The R5/G6/B5 fields are expanded to 8-bit by bit replication, matching
// the Python reference when it decodes an existing RGB565 word.
//   gray = (R8 >> 2) + (G8 >> 1) + (B8 >> 2)
//
// This stage is combinational and transparent in valid/ready. No latency is
// added; the upstream RGB565 response must remain stable while valid && !ready.
module rgb565_gray_stream_exact (
    input  logic        in_valid_i,
    output logic        in_ready_o,
    input  logic [16:0] in_addr_i,
    input  logic [15:0] in_rgb565_i,

    output logic        out_valid_o,
    input  logic        out_ready_i,
    output logic [16:0] out_addr_o,
    output logic [7:0]  gray_o
);
    logic [7:0] r8;
    logic [7:0] g8;
    logic [7:0] b8;
    logic [9:0] gray_sum;

    always_comb begin
        // Unpack an existing RGB565 word; this is not an RGB888->RGB565 conversion.
// Bit replication matches Python rgb565_to_rgb8().
        r8 = {in_rgb565_i[15:11], in_rgb565_i[15:13]};
        g8 = {in_rgb565_i[10:5],  in_rgb565_i[10:9]};
        b8 = {in_rgb565_i[4:0],   in_rgb565_i[4:2]};

        gray_sum = ({2'b00, r8} >> 2)
                 + ({2'b00, g8} >> 1)
                 + ({2'b00, b8} >> 2);

        gray_o      = gray_sum[7:0]; // range is 0..253; no wrap/saturation occurs
        out_addr_o  = in_addr_i;
        out_valid_o = in_valid_i;
        in_ready_o  = out_ready_i;
    end
endmodule

`default_nettype wire
