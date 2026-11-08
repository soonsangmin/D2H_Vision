// KEY[0] press-and-release RUN/STOP toggle for the DE10-Nano CTW MASK.
// KEY is active-low. The controller is intentionally NOT reset by KEY[0]:
// resetting it on button press would make a release-toggle impossible.
// Quartus Cyclone V supports initialized registers at FPGA configuration.
module key_release_run_toggle #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer DEBOUNCE_CYCLES = (CLK_HZ / 1000) * DEBOUNCE_MS,
    parameter integer CNTR_W = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES)
)(
    input  logic clk_i,
    input  logic key_n_i,
    output logic run_enable_o
);
    // Two-stage synchronizer for the asynchronous push button.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic key_meta = 1'b1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    logic key_sync = 1'b1;
    logic stable_key_n = 1'b1;
    logic [CNTR_W-1:0] debounce_count = '0;
    logic press_armed = 1'b0;
    initial run_enable_o = 1'b1;

    always_ff @(posedge clk_i) begin
        key_meta <= key_n_i;
        key_sync <= key_meta;

        if (key_sync == stable_key_n) begin
            debounce_count <= '0;
        end else if (debounce_count == (DEBOUNCE_CYCLES - 1)) begin
            debounce_count <= '0;
            stable_key_n <= key_sync;
            if (!key_sync) begin
                // A stable press arms a future release; no toggle yet.
                press_armed <= 1'b1;
            end else if (press_armed) begin
                // Only a stable RELEASE after a stable PRESS counts as one hit.
                press_armed <= 1'b0;
                run_enable_o <= ~run_enable_o;
            end
        end else begin
            debounce_count <= debounce_count + 1'b1;
        end
    end
endmodule
