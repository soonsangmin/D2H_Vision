module requantizer (
    input  logic                    clk_i,
    input  logic                    rstn_i,

    // ============================================================
    // INPUT HANDSHAKE
    // ============================================================
    input  logic                    valid_i,
    output logic                    ready_o,

    // ============================================================
    // INPUT DATA
    // ============================================================
    input  logic signed [31:0]      acc_i,

    // Positive UINT32 fixed-point multiplier
    input  logic        [31:0]      multiplier_i,

    // Bias already converted to post-scale fixed-point domain
    input  logic signed [63:0]      bias_postscale_i,

    // Divide by 2^right_shift
    input  logic        [7:0]       right_shift_i,

    // UINT8 output zero point
    input  logic        [7:0]       zero_point_i,

    // Quantized ReLU enable
    input  logic                    relu_en_i,

    // ============================================================
    // METADATA
    // ============================================================
    //
    // tag_i[2:0] = PE lane
    // tag_i[3]   = last active lane
    //
    input  logic        [3:0]       tag_i,

    // ============================================================
    // OUTPUT HANDSHAKE
    // ============================================================
    output logic                    valid_o,
    input  logic                    ready_i,

    // Quantized UINT8 output
    output logic        [7:0]       data_o,

    // Metadata corresponding exactly to data_o
    output logic        [3:0]       tag_o
);


    // ============================================================
    // PIPELINE OVERVIEW
    // ============================================================
    //
    // Stage 1:
    //
    //     numerator =
    //         acc * multiplier
    //         + bias_postscale
    //
    // Stage 2:
    //
    //     scaled =
    //         RNE(
    //             numerator / 2^right_shift
    //         )
    //
    // Stage 3 / output:
    //
    //     + zero_point
    //     quantized ReLU
    //     UINT8 clamp
    //
    // This extra Stage 2 register cuts the previous critical path:
    //
    //     right_shift_s1
    //       -> RNE
    //       -> zero point
    //       -> ReLU
    //       -> clamp
    //       -> data_o
    //
    // into two shorter timing paths.
    //
    // The pipeline remains fully elastic:
    //
    //     - valid/ready backpressure is preserved
    //     - output data/tag remain stable while stalled
    //     - throughput can still reach one transaction per cycle
    //
    // Latency increases by one clock cycle.
    // ============================================================


    // ============================================================
    // STAGE 1 REGISTERS
    // ============================================================

    logic signed [65:0] numerator_s1;

    logic        [7:0]  right_shift_s1;
    logic        [7:0]  zero_point_s1;
    logic               relu_en_s1;

    logic        [3:0]  tag_s1;

    logic               valid_s1;


    // ============================================================
    // STAGE 1 COMBINATIONAL
    // ============================================================

    logic signed [32:0] acc_ext_c;
    logic signed [32:0] multiplier_ext_c;

    logic signed [65:0] product_c;
    logic signed [65:0] bias_ext_c;

    logic signed [65:0] numerator_c;


    always_comb begin

        acc_ext_c = {
            acc_i[31],
            acc_i
        };


        multiplier_ext_c = {
            1'b0,
            multiplier_i
        };


        product_c =
            acc_ext_c *
            multiplier_ext_c;


        bias_ext_c = {
            {2{bias_postscale_i[63]}},
            bias_postscale_i
        };


        numerator_c =
            product_c +
            bias_ext_c;

    end


    // ============================================================
    // ROUND TO NEAREST EVEN
    //
    // RNE(value / 2^shift)
    //
    // Supports positive and negative values.
    // ============================================================

    function automatic logic signed [65:0]
        round_nearest_even (
            input logic signed [65:0] value_i,
            input logic        [7:0]  shift_i
        );

        logic               negative;

        logic        [65:0] magnitude;
        logic        [65:0] quotient;
        logic        [65:0] remainder;

        logic        [65:0] remainder_mask;
        logic        [65:0] half_value;

        logic               increment;

        logic        [65:0] rounded_magnitude;

        begin

            // ----------------------------------------------------
            // No shift
            // ----------------------------------------------------

            if (shift_i == 0) begin

                round_nearest_even =
                    value_i;

            end


            // ----------------------------------------------------
            // Shift larger than datapath width
            // ----------------------------------------------------

            else if (shift_i >= 66) begin

                round_nearest_even =
                    66'sd0;

            end


            else begin

                // ------------------------------------------------
                // Sign
                // ------------------------------------------------

                negative =
                    value_i[65];


                // ------------------------------------------------
                // Absolute magnitude
                // ------------------------------------------------

                if (negative) begin

                    magnitude =
                        (~$unsigned(value_i))
                        +
                        66'd1;

                end

                else begin

                    magnitude =
                        $unsigned(value_i);

                end


                // ------------------------------------------------
                // Integer quotient
                // ------------------------------------------------

                quotient =
                    magnitude
                    >>
                    shift_i;


                // ------------------------------------------------
                // Remainder mask
                // ------------------------------------------------

                remainder_mask =
                    {66{1'b1}}
                    >>
                    (
                        66
                        -
                        shift_i
                    );


                // ------------------------------------------------
                // Fractional remainder
                // ------------------------------------------------

                remainder =
                    magnitude
                    &
                    remainder_mask;


                // ------------------------------------------------
                // Half divisor
                // ------------------------------------------------

                half_value =
                    66'd1
                    <<
                    (
                        shift_i
                        -
                        1
                    );


                // ------------------------------------------------
                // Round-to-nearest-even decision
                // ------------------------------------------------

                if (
                    remainder
                    >
                    half_value
                ) begin

                    increment =
                        1'b1;

                end


                else if (
                    remainder
                    <
                    half_value
                ) begin

                    increment =
                        1'b0;

                end


                else begin

                    // Exactly halfway:
                    //
                    // increment only when quotient is odd,
                    // so the final result becomes even.
                    increment =
                        quotient[0];

                end


                // ------------------------------------------------
                // Apply rounding
                // ------------------------------------------------

                if (increment) begin

                    rounded_magnitude =
                        quotient
                        +
                        66'd1;

                end

                else begin

                    rounded_magnitude =
                        quotient;

                end


                // ------------------------------------------------
                // Restore sign
                // ------------------------------------------------

                if (negative) begin

                    round_nearest_even =
                        $signed(
                            (~rounded_magnitude)
                            +
                            66'd1
                        );

                end

                else begin

                    round_nearest_even =
                        $signed(
                            rounded_magnitude
                        );

                end

            end

        end

    endfunction


    // ============================================================
    // STAGE 2: RNE REGISTER
    // ============================================================

    logic signed [65:0] scaled_s2;

    logic        [7:0]  zero_point_s2;
    logic               relu_en_s2;

    logic        [3:0]  tag_s2;

    logic               valid_s2;


    // RNE is now terminated by the Stage 2 register.
    logic signed [65:0] scaled_next_c;


    always_comb begin

        scaled_next_c =
            round_nearest_even(
                numerator_s1,
                right_shift_s1
            );

    end


    // ============================================================
    // STAGE 3 / OUTPUT COMBINATIONAL
    // ============================================================

    // One additional bit for zero-point addition.
    logic signed [66:0] q_with_zp_c;

    logic signed [66:0] q_relu_c;

    logic        [7:0]  data_next_c;


    always_comb begin

        // --------------------------------------------------------
        // 1. Add output zero point
        // --------------------------------------------------------

        q_with_zp_c =
            $signed({
                scaled_s2[65],
                scaled_s2
            })
            +
            $signed({
                59'd0,
                zero_point_s2
            });


        // --------------------------------------------------------
        // 2. Quantized ReLU
        //
        // Real zero corresponds to zero_point.
        //
        // q = max(q, zero_point)
        // --------------------------------------------------------

        if (
            relu_en_s2
            &&
            (
                q_with_zp_c
                <
                $signed({
                    59'd0,
                    zero_point_s2
                })
            )
        ) begin

            q_relu_c =
                $signed({
                    59'd0,
                    zero_point_s2
                });

        end

        else begin

            q_relu_c =
                q_with_zp_c;

        end


        // --------------------------------------------------------
        // 3. UINT8 saturation
        // --------------------------------------------------------

        if (
            q_relu_c
            <
            0
        ) begin

            data_next_c =
                8'd0;

        end


        else if (
            q_relu_c
            >
            67'sd255
        ) begin

            data_next_c =
                8'd255;

        end


        else begin

            data_next_c =
                q_relu_c[7:0];

        end

    end


    // ============================================================
    // ELASTIC PIPELINE HANDSHAKE
    // ============================================================

    logic stage3_ready_c;
    logic stage2_ready_c;
    logic stage1_ready_c;


    // Output stage may update when empty or consumed.
    assign stage3_ready_c =
        (~valid_o)
        |
        ready_i;


    // Stage 2 may update when empty or when current Stage 2
    // transaction advances into Stage 3.
    assign stage2_ready_c =
        (~valid_s2)
        |
        stage3_ready_c;


    // Stage 1 may update when empty or when current Stage 1
    // transaction advances into Stage 2.
    assign stage1_ready_c =
        (~valid_s1)
        |
        stage2_ready_c;


    assign ready_o =
        stage1_ready_c;


    // ============================================================
    // PIPELINE REGISTERS
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            // ----------------------------------------------------
            // Stage 1
            // ----------------------------------------------------

            numerator_s1 <=
                66'sd0;


            right_shift_s1 <=
                8'd0;


            zero_point_s1 <=
                8'd0;


            relu_en_s1 <=
                1'b0;


            tag_s1 <=
                4'd0;


            valid_s1 <=
                1'b0;


            // ----------------------------------------------------
            // Stage 2
            // ----------------------------------------------------

            scaled_s2 <=
                66'sd0;


            zero_point_s2 <=
                8'd0;


            relu_en_s2 <=
                1'b0;


            tag_s2 <=
                4'd0;


            valid_s2 <=
                1'b0;


            // ----------------------------------------------------
            // Stage 3 / output
            // ----------------------------------------------------

            data_o <=
                8'd0;


            tag_o <=
                4'd0;


            valid_o <=
                1'b0;

        end

        else begin

            // ====================================================
            // STAGE 3 / OUTPUT
            // ====================================================

            if (stage3_ready_c) begin

                valid_o <=
                    valid_s2;


                if (valid_s2) begin

                    data_o <=
                        data_next_c;


                    tag_o <=
                        tag_s2;

                end

            end


            // ====================================================
            // STAGE 2 / RNE REGISTER
            // ====================================================

            if (stage2_ready_c) begin

                valid_s2 <=
                    valid_s1;


                if (valid_s1) begin

                    scaled_s2 <=
                        scaled_next_c;


                    zero_point_s2 <=
                        zero_point_s1;


                    relu_en_s2 <=
                        relu_en_s1;


                    tag_s2 <=
                        tag_s1;

                end

            end


            // ====================================================
            // STAGE 1 / MULTIPLY + BIAS
            // ====================================================

            if (stage1_ready_c) begin

                valid_s1 <=
                    valid_i;


                if (valid_i) begin

                    numerator_s1 <=
                        numerator_c;


                    right_shift_s1 <=
                        right_shift_i;


                    zero_point_s1 <=
                        zero_point_i;


                    relu_en_s1 <=
                        relu_en_i;


                    tag_s1 <=
                        tag_i;

                end

            end

        end

    end


endmodule
