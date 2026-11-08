module result_serializer_8 (
    input  logic               clk_i,
    input  logic               rstn_i,

    // ============================================================
    // INPUT VECTOR
    // ============================================================

    input  logic               valid_i,
    output logic               ready_o,

    // 8 × INT32
    //
    // [31:0]    -> lane 0
    // [63:32]   -> lane 1
    // ...
    // [255:224] -> lane 7
    input  logic [255:0]       acc_vec_i,

    // Active lanes
    input  logic [7:0]         lane_mask_i,

    // ============================================================
    // SERIAL OUTPUT
    // ============================================================

    output logic               valid_o,
    input  logic               ready_i,

    output logic signed [31:0] acc_o,
    output logic [2:0]         lane_o,

    // Asserted together with valid_o when current lane
    // is the last active lane of this vector.
    output logic               last_o
);


    // ============================================================
    // INTERNAL STORAGE
    // ============================================================

    logic [255:0] acc_vec_r;

    // One bit for every lane still waiting to be transmitted.
    logic [7:0] remaining_mask_r;

    logic       busy_r;


    // ============================================================
    // CURRENT LANE
    // ============================================================

    logic [2:0] current_lane_c;

    logic [7:0] mask_after_current_c;


    // ============================================================
    // PRIORITY ENCODER
    //
    // Always select the lowest active lane.
    //
    // Example:
    //
    // 0010_1100
    //       ^
    //       lane 2 selected first
    // ============================================================

    always_comb begin

        current_lane_c = 3'd0;

        if (remaining_mask_r[0])
            current_lane_c = 3'd0;

        else if (remaining_mask_r[1])
            current_lane_c = 3'd1;

        else if (remaining_mask_r[2])
            current_lane_c = 3'd2;

        else if (remaining_mask_r[3])
            current_lane_c = 3'd3;

        else if (remaining_mask_r[4])
            current_lane_c = 3'd4;

        else if (remaining_mask_r[5])
            current_lane_c = 3'd5;

        else if (remaining_mask_r[6])
            current_lane_c = 3'd6;

        else if (remaining_mask_r[7])
            current_lane_c = 3'd7;

    end


    // ============================================================
    // SELECT CURRENT ACCUMULATOR
    // ============================================================

    always_comb begin

        acc_o = 32'sd0;

        case (current_lane_c)

            3'd0:
                acc_o = $signed(acc_vec_r[31:0]);

            3'd1:
                acc_o = $signed(acc_vec_r[63:32]);

            3'd2:
                acc_o = $signed(acc_vec_r[95:64]);

            3'd3:
                acc_o = $signed(acc_vec_r[127:96]);

            3'd4:
                acc_o = $signed(acc_vec_r[159:128]);

            3'd5:
                acc_o = $signed(acc_vec_r[191:160]);

            3'd6:
                acc_o = $signed(acc_vec_r[223:192]);

            3'd7:
                acc_o = $signed(acc_vec_r[255:224]);

            default:
                acc_o = 32'sd0;

        endcase

    end


    // ============================================================
    // OUTPUT STATUS
    // ============================================================

    assign lane_o = current_lane_c;

    assign valid_o =
        busy_r &&
        (remaining_mask_r != 8'd0);


    // Mask after current lane has been consumed.
    always_comb begin

        mask_after_current_c =
            remaining_mask_r;

        if (valid_o) begin

            mask_after_current_c[current_lane_c] =
                1'b0;

        end

    end


    // Current lane is the final active lane.
    assign last_o =
        valid_o &&
        (mask_after_current_c == 8'd0);


    // ============================================================
    // INPUT READY
    // ============================================================
    //
    // We can accept a new vector when:
    //
    // 1. Serializer is idle.
    //
    // OR
    //
    // 2. Current final lane is being consumed this cycle.
    //
    // This permits:
    //
    // old vector final lane -> downstream
    // new vector            -> serializer
    //
    // on the same clock edge.
    // ============================================================

    assign ready_o =
        (~busy_r) ||
        (valid_o && ready_i && last_o);


    // ============================================================
    // STATE
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            acc_vec_r        <= 256'd0;
            remaining_mask_r <= 8'd0;

            busy_r            <= 1'b0;

        end else begin

            // ----------------------------------------------------
            // Accept a new complete result vector
            // ----------------------------------------------------

            if (valid_i && ready_o) begin

                acc_vec_r <=
                    acc_vec_i;

                remaining_mask_r <=
                    lane_mask_i;

                // Zero lane mask means there is nothing to emit.
                busy_r <=
                    (lane_mask_i != 8'd0);

            end

            // ----------------------------------------------------
            // Current serialized result consumed
            // ----------------------------------------------------

            else if (valid_o && ready_i) begin

                remaining_mask_r <=
                    mask_after_current_c;

                if (last_o) begin

                    busy_r <= 1'b0;

                end

            end

        end

    end


endmodule