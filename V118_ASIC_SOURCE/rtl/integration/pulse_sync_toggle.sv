module pulse_sync_toggle (
    input  logic src_clk_i,
    input  logic src_rstn_i,
    input  logic src_pulse_i,

    input  logic dst_clk_i,
    input  logic dst_rstn_i,
    output logic dst_pulse_o
);

    logic src_toggle_r;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic dst_toggle_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic dst_toggle_sync_r;
    logic dst_toggle_delay_r;

    always_ff @(posedge src_clk_i or negedge src_rstn_i) begin
        if (!src_rstn_i) begin
            src_toggle_r <= 1'b0;
        end
        else if (src_pulse_i) begin
            src_toggle_r <= ~src_toggle_r;
        end
    end

    always_ff @(posedge dst_clk_i or negedge dst_rstn_i) begin
        if (!dst_rstn_i) begin
            dst_toggle_meta_r  <= 1'b0;
            dst_toggle_sync_r  <= 1'b0;
            dst_toggle_delay_r <= 1'b0;
        end
        else begin
            dst_toggle_meta_r  <= src_toggle_r;
            dst_toggle_sync_r  <= dst_toggle_meta_r;
            dst_toggle_delay_r <= dst_toggle_sync_r;
        end
    end

    assign dst_pulse_o =
        dst_toggle_sync_r ^ dst_toggle_delay_r;

endmodule
