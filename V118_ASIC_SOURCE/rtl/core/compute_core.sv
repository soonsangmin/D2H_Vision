module compute_core (
    input  logic                 clk_i,
    input  logic                 rstn_i,

    // ============================================================
    // MAC INPUT HANDSHAKE
    // ============================================================

    input  logic                 mac_valid_i,
    output logic                 mac_ready_o,

    input  logic                 mac_start_i,
    input  logic                 mac_last_i,

    // ============================================================
    // MAC OPERANDS
    //
    // lane 0 = LSB
    //
    // activation_vec_i[7:0]   -> PE0
    // activation_vec_i[15:8]  -> PE1
    // ...
    //
    // weight mapping is identical.
    // ============================================================

    input  logic [63:0]          activation_vec_i,
    input  logic [63:0]          weight_vec_i,

    // ============================================================
    // ACTIVE OUTPUT LANES
    //
    // Normal 8-output group:
    //
    //     8'b1111_1111
    //
    // Example 4-output head:
    //
    //     8'b0000_1111
    //
    // Captured together with the FINAL MAC.
    // ============================================================

    input  logic [7:0]           lane_mask_i,

    // ============================================================
    // QUANTIZATION PARAMETERS
    //
    // One parameter set per PE/output lane.
    //
    // Lane 0 is always stored in the least-significant slice.
    //
    // multiplier:
    //     lane0 = [31:0]
    //     lane1 = [63:32]
    //     ...
    //
    // bias:
    //     lane0 = [63:0]
    //     lane1 = [127:64]
    //     ...
    //
    // These parameters are captured when the final MAC of the
    // dot-product is accepted.
    // ============================================================

    input  logic [255:0]         multiplier_vec_i,
    input  logic [511:0]         bias_postscale_vec_i,
    input  logic [63:0]          right_shift_vec_i,
    input  logic [63:0]          zero_point_vec_i,
    input  logic [7:0]           relu_en_vec_i,

    // ============================================================
    // QUANTIZED OUTPUT
    // ============================================================

    output logic                 out_valid_o,
    input  logic                 out_ready_i,

    output logic [7:0]           out_data_o,

    // Original PE lane
    output logic [2:0]           out_lane_o,

    // Asserted for the final active lane of current 8-PE result
    output logic                 out_last_o
);


    // ============================================================
    // MAC ARRAY SIGNALS
    // ============================================================

    logic                        mac_array_valid_i;
    logic                        mac_array_valid_o;

    logic signed [31:0]          mac_acc0;
    logic signed [31:0]          mac_acc1;
    logic signed [31:0]          mac_acc2;
    logic signed [31:0]          mac_acc3;
    logic signed [31:0]          mac_acc4;
    logic signed [31:0]          mac_acc5;
    logic signed [31:0]          mac_acc6;
    logic signed [31:0]          mac_acc7;

    logic [255:0]                mac_acc_vec;


    // ============================================================
    // RESULT BUFFER SIGNALS
    // ============================================================

    logic                        result_buffer_ready_in;
    logic                        result_buffer_valid_out;

    logic [255:0]                result_buffer_acc_vec;
    logic [7:0]                  result_buffer_lane_mask;


    // ============================================================
    // SERIALIZER SIGNALS
    // ============================================================

    logic                        serializer_ready_in;

    logic                        serializer_valid_out;
    logic                        serializer_ready_out;

    logic signed [31:0]          serializer_acc;
    logic [2:0]                  serializer_lane;
    logic                        serializer_last;


    // ============================================================
    // REQUANTIZER SIGNALS
    // ============================================================

    logic                        requant_ready_in;
    logic                        requant_valid_out;

    logic [7:0]                  requant_data;
    logic [3:0]                  requant_tag;


    // ============================================================
    // FINAL RESULT PENDING
    //
    // mac_array_8 produces valid_o one cycle after the FINAL
    // MAC input is accepted.
    //
    // This flag prevents another final MAC from being accepted
    // before the previous result has safely entered result_buffer.
    // ============================================================

    logic                        final_pending_r;


    // ============================================================
    // PENDING METADATA
    //
    // Captured at the same time as the final MAC input.
    // ============================================================

    logic [7:0]                  pending_lane_mask_r;

    logic [255:0]                pending_multiplier_vec_r;
    logic [511:0]                pending_bias_vec_r;
    logic [63:0]                 pending_shift_vec_r;
    logic [63:0]                 pending_zero_point_vec_r;
    logic [7:0]                  pending_relu_vec_r;


    // ============================================================
    // QPARAM ASSOCIATED WITH RESULT BUFFER
    //
    // result_buffer contains ACC values.
    //
    // These registers contain the corresponding qparams.
    // ============================================================

    logic [255:0]                buffer_multiplier_vec_r;
    logic [511:0]                buffer_bias_vec_r;
    logic [63:0]                 buffer_shift_vec_r;
    logic [63:0]                 buffer_zero_point_vec_r;
    logic [7:0]                  buffer_relu_vec_r;


    // ============================================================
    // QPARAM ASSOCIATED WITH SERIALIZER
    //
    // Once the serializer accepts an ACC vector, its matching
    // qparams are copied here and remain stable while lanes are
    // serialized.
    // ============================================================

    logic [255:0]                active_multiplier_vec_r;
    logic [511:0]                active_bias_vec_r;
    logic [63:0]                 active_shift_vec_r;
    logic [63:0]                 active_zero_point_vec_r;
    logic [7:0]                  active_relu_vec_r;


    // ============================================================
    // SELECTED QPARAM
    // ============================================================

    logic [31:0]                 selected_multiplier_c;
    logic signed [63:0]          selected_bias_c;
    logic [7:0]                  selected_shift_c;
    logic [7:0]                  selected_zero_point_c;
    logic                        selected_relu_c;


    // ============================================================
    // MAC INPUT FLOW CONTROL
    // ============================================================

    logic                        mac_fire_c;
    logic                        final_slot_ready_c;


    // A final MAC can only be accepted when:
    //
    // 1. no previous final result is waiting for mac_array output
    //
    // 2. result_buffer has capacity
    //
    assign final_slot_ready_c =
        (~final_pending_r) &&
        result_buffer_ready_in;


    // Non-final MAC operations can continue normally.
    //
    // Only the final MAC may be stalled.
    assign mac_ready_o =
        (~mac_last_i) |
        final_slot_ready_c;


    // Actual accepted MAC operation
    assign mac_fire_c =
        mac_valid_i &&
        mac_ready_o;


    assign mac_array_valid_i =
        mac_fire_c;


    // ============================================================
    // MAC ARRAY
    // ============================================================

    mac_array_8 u_mac_array_8 (
        .clk_i             (clk_i),
        .rstn_i            (rstn_i),

        .valid_i           (mac_array_valid_i),
        .start_i           (mac_start_i),
        .last_i            (mac_last_i),

        .activation_vec_i  (activation_vec_i),
        .weight_vec_i      (weight_vec_i),

        .valid_o           (mac_array_valid_o),

        .acc0_o            (mac_acc0),
        .acc1_o            (mac_acc1),
        .acc2_o            (mac_acc2),
        .acc3_o            (mac_acc3),
        .acc4_o            (mac_acc4),
        .acc5_o            (mac_acc5),
        .acc6_o            (mac_acc6),
        .acc7_o            (mac_acc7)
    );


    // ============================================================
    // PACK MAC RESULTS
    //
    // lane 0 = LSB
    // ============================================================

    assign mac_acc_vec = {
        mac_acc7,
        mac_acc6,
        mac_acc5,
        mac_acc4,
        mac_acc3,
        mac_acc2,
        mac_acc1,
        mac_acc0
    };


    // ============================================================
    // CAPTURE FINAL MAC METADATA
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            final_pending_r <=
                1'b0;

            pending_lane_mask_r <=
                8'd0;

            pending_multiplier_vec_r <=
                256'd0;

            pending_bias_vec_r <=
                512'd0;

            pending_shift_vec_r <=
                64'd0;

            pending_zero_point_vec_r <=
                64'd0;

            pending_relu_vec_r <=
                8'd0;

        end

        else begin

            // ----------------------------------------------------
            // Final MAC accepted
            // ----------------------------------------------------

            if (
                mac_fire_c &&
                mac_last_i
            ) begin

                final_pending_r <=
                    1'b1;

                pending_lane_mask_r <=
                    lane_mask_i;

                pending_multiplier_vec_r <=
                    multiplier_vec_i;

                pending_bias_vec_r <=
                    bias_postscale_vec_i;

                pending_shift_vec_r <=
                    right_shift_vec_i;

                pending_zero_point_vec_r <=
                    zero_point_vec_i;

                pending_relu_vec_r <=
                    relu_en_vec_i;

            end


            // ----------------------------------------------------
            // MAC result safely enters result buffer
            // ----------------------------------------------------

            if (
                mac_array_valid_o &&
                result_buffer_ready_in
            ) begin

                final_pending_r <=
                    1'b0;

            end

        end

    end


    // ============================================================
    // RESULT BUFFER
    // ============================================================

    result_buffer_8 u_result_buffer_8 (
        .clk_i       (clk_i),
        .rstn_i      (rstn_i),

        .valid_i     (mac_array_valid_o),
        .ready_o     (result_buffer_ready_in),

        .acc_vec_i   (mac_acc_vec),
        .lane_mask_i (pending_lane_mask_r),

        .valid_o     (result_buffer_valid_out),
        .ready_i     (serializer_ready_in),

        .acc_vec_o   (result_buffer_acc_vec),
        .lane_mask_o (result_buffer_lane_mask)
    );


    // ============================================================
    // CAPTURE QPARAM INTO RESULT-BUFFER CONTEXT
    //
    // This event occurs on exactly the same clock that
    // result_buffer captures the corresponding accumulator vector.
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            buffer_multiplier_vec_r <=
                256'd0;

            buffer_bias_vec_r <=
                512'd0;

            buffer_shift_vec_r <=
                64'd0;

            buffer_zero_point_vec_r <=
                64'd0;

            buffer_relu_vec_r <=
                8'd0;

        end

        else begin

            if (
                mac_array_valid_o &&
                result_buffer_ready_in
            ) begin

                buffer_multiplier_vec_r <=
                    pending_multiplier_vec_r;

                buffer_bias_vec_r <=
                    pending_bias_vec_r;

                buffer_shift_vec_r <=
                    pending_shift_vec_r;

                buffer_zero_point_vec_r <=
                    pending_zero_point_vec_r;

                buffer_relu_vec_r <=
                    pending_relu_vec_r;

            end

        end

    end


    // ============================================================
    // RESULT SERIALIZER
    // ============================================================

    result_serializer_8 u_result_serializer_8 (
        .clk_i       (clk_i),
        .rstn_i      (rstn_i),

        .valid_i     (result_buffer_valid_out),
        .ready_o     (serializer_ready_in),

        .acc_vec_i   (result_buffer_acc_vec),
        .lane_mask_i (result_buffer_lane_mask),

        .valid_o     (serializer_valid_out),
        .ready_i     (serializer_ready_out),

        .acc_o       (serializer_acc),
        .lane_o      (serializer_lane),
        .last_o      (serializer_last)
    );


    // ============================================================
    // MOVE QPARAM CONTEXT INTO SERIALIZER CONTEXT
    //
    // result_buffer_valid_out && serializer_ready_in
    //
    // means serializer has accepted the complete ACC vector.
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            active_multiplier_vec_r <=
                256'd0;

            active_bias_vec_r <=
                512'd0;

            active_shift_vec_r <=
                64'd0;

            active_zero_point_vec_r <=
                64'd0;

            active_relu_vec_r <=
                8'd0;

        end

        else begin

            if (
                result_buffer_valid_out &&
                serializer_ready_in
            ) begin

                active_multiplier_vec_r <=
                    buffer_multiplier_vec_r;

                active_bias_vec_r <=
                    buffer_bias_vec_r;

                active_shift_vec_r <=
                    buffer_shift_vec_r;

                active_zero_point_vec_r <=
                    buffer_zero_point_vec_r;

                active_relu_vec_r <=
                    buffer_relu_vec_r;

            end

        end

    end


    // ============================================================
    // QPARAM SELECTOR
    //
    // Select parameters belonging to the lane currently emitted
    // by result_serializer_8.
    // ============================================================

    always_comb begin

        selected_multiplier_c =
            32'd0;

        selected_bias_c =
            64'sd0;

        selected_shift_c =
            8'd0;

        selected_zero_point_c =
            8'd0;

        selected_relu_c =
            1'b0;


        case (serializer_lane)

            3'd0: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[31:0];

                selected_bias_c =
                    $signed(active_bias_vec_r[63:0]);

                selected_shift_c =
                    active_shift_vec_r[7:0];

                selected_zero_point_c =
                    active_zero_point_vec_r[7:0];

                selected_relu_c =
                    active_relu_vec_r[0];

            end


            3'd1: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[63:32];

                selected_bias_c =
                    $signed(active_bias_vec_r[127:64]);

                selected_shift_c =
                    active_shift_vec_r[15:8];

                selected_zero_point_c =
                    active_zero_point_vec_r[15:8];

                selected_relu_c =
                    active_relu_vec_r[1];

            end


            3'd2: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[95:64];

                selected_bias_c =
                    $signed(active_bias_vec_r[191:128]);

                selected_shift_c =
                    active_shift_vec_r[23:16];

                selected_zero_point_c =
                    active_zero_point_vec_r[23:16];

                selected_relu_c =
                    active_relu_vec_r[2];

            end


            3'd3: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[127:96];

                selected_bias_c =
                    $signed(active_bias_vec_r[255:192]);

                selected_shift_c =
                    active_shift_vec_r[31:24];

                selected_zero_point_c =
                    active_zero_point_vec_r[31:24];

                selected_relu_c =
                    active_relu_vec_r[3];

            end


            3'd4: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[159:128];

                selected_bias_c =
                    $signed(active_bias_vec_r[319:256]);

                selected_shift_c =
                    active_shift_vec_r[39:32];

                selected_zero_point_c =
                    active_zero_point_vec_r[39:32];

                selected_relu_c =
                    active_relu_vec_r[4];

            end


            3'd5: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[191:160];

                selected_bias_c =
                    $signed(active_bias_vec_r[383:320]);

                selected_shift_c =
                    active_shift_vec_r[47:40];

                selected_zero_point_c =
                    active_zero_point_vec_r[47:40];

                selected_relu_c =
                    active_relu_vec_r[5];

            end


            3'd6: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[223:192];

                selected_bias_c =
                    $signed(active_bias_vec_r[447:384]);

                selected_shift_c =
                    active_shift_vec_r[55:48];

                selected_zero_point_c =
                    active_zero_point_vec_r[55:48];

                selected_relu_c =
                    active_relu_vec_r[6];

            end


            3'd7: begin

                selected_multiplier_c =
                    active_multiplier_vec_r[255:224];

                selected_bias_c =
                    $signed(active_bias_vec_r[511:448]);

                selected_shift_c =
                    active_shift_vec_r[63:56];

                selected_zero_point_c =
                    active_zero_point_vec_r[63:56];

                selected_relu_c =
                    active_relu_vec_r[7];

            end

        endcase

    end


    // ============================================================
    // REQUANTIZER
    // ============================================================

    requantizer u_requantizer (
        .clk_i             (clk_i),
        .rstn_i            (rstn_i),

        .valid_i           (serializer_valid_out),
        .ready_o           (requant_ready_in),

        .acc_i             (serializer_acc),

        .multiplier_i      (selected_multiplier_c),
        .bias_postscale_i  (selected_bias_c),

        .right_shift_i     (selected_shift_c),
        .zero_point_i      (selected_zero_point_c),

        .relu_en_i         (selected_relu_c),

        .tag_i             ({
            serializer_last,
            serializer_lane
        }),

        .valid_o           (requant_valid_out),
        .ready_i           (out_ready_i),

        .data_o            (requant_data),
        .tag_o             (requant_tag)
    );


    // Serializer advances only when requantizer can accept
    // the corresponding ACC + qparam transaction.
    assign serializer_ready_out =
        requant_ready_in;


    // ============================================================
    // FINAL OUTPUT
    // ============================================================

    assign out_valid_o =
        requant_valid_out;

    assign out_data_o =
        requant_data;

    assign out_lane_o =
        requant_tag[2:0];

    assign out_last_o =
        requant_tag[3];


endmodule