module mac_pe (
    input  logic               clk_i,
    input  logic               rstn_i,

    // ============================================================
    // CONTROL
    // ============================================================
    input  logic               valid_i,
    input  logic               start_i,
    input  logic               last_i,

    // ============================================================
    // MAC OPERANDS
    // ============================================================
    // Activation is UINT8: 0 ... 255
    input  logic        [7:0]  activation_i,

    // Weight is signed INT8: -128 ... 127
    input  logic signed [7:0]  weight_i,

    // ============================================================
    // RESULT
    // ============================================================
    // Pulses for one cycle when a dot-product is completed.
    output logic               valid_o,

    // Final INT32 accumulator of the completed dot-product.
    output logic signed [31:0] acc_o
);


    // ============================================================
    // INTERNAL ACCUMULATOR
    // ============================================================

    logic signed [31:0] acc_r;


    // ============================================================
    // MULTIPLICATION SIGNALS
    // ============================================================

    // UINT8 must be extended to 9-bit signed before multiplication
    // so values 128...255 remain positive.
    logic signed [8:0] activation_ext_c;

    // 9-bit signed × 8-bit signed = 17-bit signed
    logic signed [16:0] product_c;

    // Sign-extended product used by INT32 accumulator
    logic signed [31:0] product_ext_c;

    // Accumulator value after the current MAC operation
    logic signed [31:0] acc_next_c;


    // ============================================================
    // MULTIPLY + ACCUMULATE
    // ============================================================

    always_comb begin

        // UINT8 -> positive signed 9-bit
        activation_ext_c = $signed({
            1'b0,
            activation_i
        });

        // UINT8 × INT8
        product_c =
            activation_ext_c * weight_i;

        // Sign extend 17-bit product -> INT32
        product_ext_c = {
            {15{product_c[16]}},
            product_c
        };

        // First MAC of a new dot-product
        if (start_i) begin

            acc_next_c =
                product_ext_c;

        end else begin

            acc_next_c =
                acc_r + product_ext_c;

        end

    end


    // ============================================================
    // ACCUMULATOR
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            acc_r   <= 32'sd0;
            acc_o   <= 32'sd0;
            valid_o <= 1'b0;

        end else begin

            // Default: no completed result
            valid_o <= 1'b0;

            // Only perform MAC when input is valid
            if (valid_i) begin

                acc_r <= acc_next_c;

                // Last MAC of current dot-product
                if (last_i) begin

                    acc_o   <= acc_next_c;
                    valid_o <= 1'b1;

                end

            end

        end

    end


endmodule