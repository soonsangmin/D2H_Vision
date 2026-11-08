module mac_array_8 (
    input  logic                 clk_i,
    input  logic                 rstn_i,

    // ============================================================
    // CONTROL
    // ============================================================
    input  logic                 valid_i,
    input  logic                 start_i,
    input  logic                 last_i,

    // ============================================================
    // INPUT VECTORS
    // ============================================================
    // Byte 0 -> PE0
    // Byte 1 -> PE1
    // ...
    // Byte 7 -> PE7
    input  logic        [63:0]   activation_vec_i,
    input  logic        [63:0]   weight_vec_i,

    // ============================================================
    // RESULT
    // ============================================================
    output logic                 valid_o,

    output logic signed [31:0]   acc0_o,
    output logic signed [31:0]   acc1_o,
    output logic signed [31:0]   acc2_o,
    output logic signed [31:0]   acc3_o,
    output logic signed [31:0]   acc4_o,
    output logic signed [31:0]   acc5_o,
    output logic signed [31:0]   acc6_o,
    output logic signed [31:0]   acc7_o
);


    // ============================================================
    // INTERNAL VALID SIGNALS
    // ============================================================

    logic [7:0] pe_valid;


    // ============================================================
    // PE0
    // ============================================================

    mac_pe u_mac_pe0 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[7:0]),
        .weight_i     ($signed(weight_vec_i[7:0])),

        .valid_o      (pe_valid[0]),
        .acc_o        (acc0_o)
    );


    // ============================================================
    // PE1
    // ============================================================

    mac_pe u_mac_pe1 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[15:8]),
        .weight_i     ($signed(weight_vec_i[15:8])),

        .valid_o      (pe_valid[1]),
        .acc_o        (acc1_o)
    );


    // ============================================================
    // PE2
    // ============================================================

    mac_pe u_mac_pe2 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[23:16]),
        .weight_i     ($signed(weight_vec_i[23:16])),

        .valid_o      (pe_valid[2]),
        .acc_o        (acc2_o)
    );


    // ============================================================
    // PE3
    // ============================================================

    mac_pe u_mac_pe3 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[31:24]),
        .weight_i     ($signed(weight_vec_i[31:24])),

        .valid_o      (pe_valid[3]),
        .acc_o        (acc3_o)
    );


    // ============================================================
    // PE4
    // ============================================================

    mac_pe u_mac_pe4 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[39:32]),
        .weight_i     ($signed(weight_vec_i[39:32])),

        .valid_o      (pe_valid[4]),
        .acc_o        (acc4_o)
    );


    // ============================================================
    // PE5
    // ============================================================

    mac_pe u_mac_pe5 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[47:40]),
        .weight_i     ($signed(weight_vec_i[47:40])),

        .valid_o      (pe_valid[5]),
        .acc_o        (acc5_o)
    );


    // ============================================================
    // PE6
    // ============================================================

    mac_pe u_mac_pe6 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[55:48]),
        .weight_i     ($signed(weight_vec_i[55:48])),

        .valid_o      (pe_valid[6]),
        .acc_o        (acc6_o)
    );


    // ============================================================
    // PE7
    // ============================================================

    mac_pe u_mac_pe7 (
        .clk_i        (clk_i),
        .rstn_i       (rstn_i),

        .valid_i      (valid_i),
        .start_i      (start_i),
        .last_i       (last_i),

        .activation_i (activation_vec_i[63:56]),
        .weight_i     ($signed(weight_vec_i[63:56])),

        .valid_o      (pe_valid[7]),
        .acc_o        (acc7_o)
    );


    // ============================================================
    // OUTPUT VALID
    // ============================================================

    // All PEs receive the same control signals,
    // therefore they must finish on the same cycle.
    assign valid_o = &pe_valid;


endmodule