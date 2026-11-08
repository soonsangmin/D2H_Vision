// -----------------------------------------------------------------------------
// Sobel result storage: 96 x 96 x 8-bit = 73,728 bits.
//
// V6.0 port usage:
//   Port A @ 50 MHz : Sobel writer. The legacy classifier-read inputs remain in
//                     the interface for compatibility but are tied inactive by
//                     DE10_NANO.v.
//   Port B @ 25 MHz : independent SW1 HDMI debug reader.
//
// The replacement classifier reads the frozen RGB565 image96_bram directly and
// performs its own Gray/Sobel preprocessing internally.
// -----------------------------------------------------------------------------
module sobel96_bram (
    input  logic        ai_clk_i,
    input  logic        wr_en_i,
    input  logic [13:0] wr_addr_i,
    input  logic [7:0]  wr_data_i,

    // Classifier also runs at 50 MHz and reuses physical Port A after Sobel.
    input  logic        classifier_read_active_i,
    input  logic [13:0] classifier_rd_addr_i,
    output logic [7:0]  classifier_rd_data_o,

    // HDMI keeps its independent 25-MHz physical Port B.
    input  logic        hdmi_clk_i,
    input  logic [13:0] hdmi_rd_addr_i,
    output logic [7:0]  hdmi_rd_data_o
);
    wire [13:0] port_a_addr = classifier_read_active_i
                            ? classifier_rd_addr_i
                            : wr_addr_i;

    wire [7:0] q_a;
    wire [7:0] q_b;

    assign classifier_rd_data_o = q_a;
    assign hdmi_rd_data_o       = q_b;

    altsyncram #(
        .address_reg_a                     ("CLOCK0"),
        .address_reg_b                     ("CLOCK1"),
        .clock_enable_input_a              ("BYPASS"),
        .clock_enable_input_b              ("BYPASS"),
        .clock_enable_output_a             ("BYPASS"),
        .clock_enable_output_b             ("BYPASS"),
        .intended_device_family            ("Cyclone V"),
        .lpm_type                          ("altsyncram"),
        .numwords_a                        (9216),
        .numwords_b                        (9216),
        .operation_mode                    ("BIDIR_DUAL_PORT"),
        .outdata_aclr_a                    ("NONE"),
        .outdata_aclr_b                    ("NONE"),
        .outdata_reg_a                     ("UNREGISTERED"),
        .outdata_reg_b                     ("UNREGISTERED"),
        .power_up_uninitialized            ("FALSE"),
        .ram_block_type                    ("M10K"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .width_a                           (8),
        .width_b                           (8),
        .widthad_a                         (14),
        .widthad_b                         (14),
        .width_byteena_a                   (1),
        .width_byteena_b                   (1)
    ) u_sobel96_m10k (
        .clock0         (ai_clk_i),
        .clock1         (hdmi_clk_i),
        .address_a      (port_a_addr),
        .address_b      (hdmi_rd_addr_i),
        .data_a         (wr_data_i),
        .data_b         (8'h00),
        .wren_a         (wr_en_i && !classifier_read_active_i),
        .wren_b         (1'b0),
        .rden_a         (classifier_read_active_i),
        .rden_b         (1'b1),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .q_a            (q_a),
        .q_b            (q_b),
        .eccstatus      ()
    );
endmodule
