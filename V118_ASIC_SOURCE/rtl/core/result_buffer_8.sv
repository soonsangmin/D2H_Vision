module result_buffer_8 (
    input  logic          clk_i,
    input  logic          rstn_i,

    // ============================================================
    // INPUT SIDE
    // ============================================================

    // New MAC result is available
    input  logic          valid_i,

    // Buffer can accept a new result
    output logic          ready_o,

    // 8 × INT32 accumulator
    //
    // [31:0]    -> PE0
    // [63:32]   -> PE1
    // ...
    // [255:224] -> PE7
    input  logic [255:0]  acc_vec_i,

    // Active PE lanes
    input  logic [7:0]    lane_mask_i,

    // ============================================================
    // OUTPUT SIDE
    // ============================================================

    // Buffered result is available
    output logic          valid_o,

    // Next stage accepts current result
    input  logic          ready_i,

    output logic [255:0]  acc_vec_o,
    output logic [7:0]    lane_mask_o
);


    // ============================================================
    // READY LOGIC
    // ============================================================
    //
    // Buffer can accept new data when:
    //
    // 1. It is currently empty
    //
    // OR
    //
    // 2. Current data will be consumed this cycle.
    //
    // This allows consume + replace in the same clock cycle.
    // ============================================================

    always_comb begin

        ready_o =
            (~valid_o) |
            ready_i;

    end


    // ============================================================
    // BUFFER REGISTER
    // ============================================================

    always_ff @(posedge clk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            valid_o     <= 1'b0;
            acc_vec_o   <= 256'd0;
            lane_mask_o <= 8'd0;

        end else begin

            // Only modify buffer state when the input side is ready.
            //
            // If ready_o = 0:
            //     hold current data and valid state.
            //
            // If ready_o = 1:
            //     valid_i decides whether we load new data
            //     or leave the buffer empty.
            if (ready_o) begin

                valid_o <= valid_i;

                if (valid_i) begin

                    acc_vec_o   <= acc_vec_i;
                    lane_mask_o <= lane_mask_i;

                end

            end

        end

    end


endmodule