// -----------------------------------------------------------------------------
// V6.20 - Human-readable classifier result on the CTW MASK LED display.
//
// Contract:
//   - A valid classification is shown for at least 2 seconds at 50 MHz.
//   - Starting another camera frame or another classifier run NEVER clears it.
//   - While a result is in its minimum display interval, keep ONLY the latest
//     subsequent result as a pending update (no unbounded queue).
//   - A confirmed no-hand event supersedes any older pending classification,
//     but does not cut short the minimum 2-second readable display interval.
//   - If no new result comes, remove a stale result after 5 seconds.
//   - Reset/KEY0 STOP/F45 fabric recovery may clear immediately, intentionally.
//   - LED[7] is valid, LED[0:6] selects class 0..6, from the SAME state as
//     the 7-segment C0x output. No duplicated validity register at top level.
//
// MIN_SHOW_CYCLES / MAX_STALE_CYCLES can be overridden in a testbench.
// -----------------------------------------------------------------------------
module classifier_led_display #(
    parameter integer MIN_SHOW_CYCLES  = 100_000_000, // 2s @50MHz
    parameter integer MAX_STALE_CYCLES = 250_000_000  // 5s @50MHz
)(
    input  logic       clk_i,
    input  logic       rstn_i,
    input  logic       done_pulse_i,
    input  logic       no_hand_i,
    input  logic [2:0] predicted_class_i,
    output logic [7:0] led_o,
    output logic       result_valid_o,
    output logic [2:0] result_class_o
);
    localparam integer AGE_W = $clog2(MAX_STALE_CYCLES + 1);
    logic [AGE_W-1:0] display_age_q;
    logic             pending_result_q;
    logic [2:0]       pending_class_q;
    logic             pending_no_hand_q;

    wire valid_new_result = done_pulse_i && (predicted_class_i <= 3'd6);
    wire min_elapsed = (display_age_q >= (MIN_SHOW_CYCLES - 1));
    wire ttl_elapsed = (display_age_q >= (MAX_STALE_CYCLES - 1));

    // LED one-hot result and the MASK C0x result always share state.
    always_comb begin
        led_o = 8'h00;
        if (result_valid_o)
            led_o = 8'h80 | (8'h01 << result_class_o);
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            result_valid_o   <= 1'b0;
            result_class_o   <= 3'd0;
            display_age_q    <= '0;
            pending_result_q <= 1'b0;
            pending_class_q  <= 3'd0;
            pending_no_hand_q <= 1'b0;
        end else if (valid_new_result) begin
            // A genuine new result takes precedence over a coincident no-hand
            // pulse. If the current result is already readable, show it now;
            // otherwise defer to the end of the current 2-second interval.
            if (!result_valid_o || min_elapsed) begin
                result_valid_o   <= 1'b1;
                result_class_o   <= predicted_class_i;
                display_age_q    <= '0;
                pending_result_q <= 1'b0;
            end else begin
                pending_result_q <= 1'b1;
                pending_class_q  <= predicted_class_i;
            end
            pending_no_hand_q <= 1'b0;
        end else if (no_hand_i) begin
            // Unlike V6.19, a no-hand event does not make a just-displayed
            // class flash once and vanish. It is applied after min hold.
            pending_result_q <= 1'b0;
            if (!result_valid_o || min_elapsed) begin
                result_valid_o   <= 1'b0;
                display_age_q    <= '0;
                pending_no_hand_q <= 1'b0;
            end else begin
                pending_no_hand_q <= 1'b1;
                display_age_q <= display_age_q + 1'b1;
            end
        end else if (result_valid_o) begin
            if (min_elapsed && pending_no_hand_q) begin
                result_valid_o    <= 1'b0;
                display_age_q     <= '0;
                pending_no_hand_q <= 1'b0;
            end else if (min_elapsed && pending_result_q) begin
                result_class_o    <= pending_class_q;
                display_age_q     <= '0;
                pending_result_q  <= 1'b0;
                pending_no_hand_q <= 1'b0;
            end else if (ttl_elapsed) begin
                result_valid_o    <= 1'b0;
                display_age_q     <= '0;
                pending_result_q  <= 1'b0;
                pending_no_hand_q <= 1'b0;
            end else begin
                display_age_q <= display_age_q + 1'b1;
            end
        end else begin
            // Idle: no stale class is ever shown.
            display_age_q <= '0;
            pending_result_q <= 1'b0;
            pending_no_hand_q <= 1'b0;
        end
    end
endmodule
