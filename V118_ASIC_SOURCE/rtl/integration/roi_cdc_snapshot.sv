module roi_cdc_snapshot (
    // ============================================================
    // SOURCE DOMAIN
    // ============================================================
    input  logic        src_clk_i,
    input  logic        src_rstn_i,

    input  logic        src_update_i,
    input  logic        src_valid_i,
    input  logic [9:0]  src_xmin_i,
    input  logic [8:0]  src_ymin_i,
    input  logic [9:0]  src_xmax_i,
    input  logic [8:0]  src_ymax_i,
    input  logic [15:0] src_score_q16_i,

    // ============================================================
    // DESTINATION DOMAIN
    // ============================================================
    input  logic        dst_clk_i,
    input  logic        dst_rstn_i,

    output logic        dst_update_o,
    output logic        dst_valid_o,
    output logic [9:0]  dst_xmin_o,
    output logic [8:0]  dst_ymin_o,
    output logic [9:0]  dst_xmax_o,
    output logic [8:0]  dst_ymax_o,
    output logic [15:0] dst_score_q16_o
);

    // The ROI is a bundled-data snapshot.  Source data is first
    // copied into holding registers and then kept unchanged until
    // the next update.  The update event crosses the clock boundary
    // through a toggle synchronizer.  The extra toggle stage gives
    // the data bus enough time to settle through its two FF stages
    // before the destination latches the complete snapshot.

    logic        src_toggle_r;
    logic        src_valid_hold_r;
    logic [9:0]  src_xmin_hold_r;
    logic [8:0]  src_ymin_hold_r;
    logic [9:0]  src_xmax_hold_r;
    logic [8:0]  src_ymax_hold_r;
    logic [15:0] src_score_hold_r;

    always_ff @(posedge src_clk_i or negedge src_rstn_i) begin
        if (!src_rstn_i) begin
            src_toggle_r     <= 1'b0;
            src_valid_hold_r <= 1'b0;
            src_xmin_hold_r  <= '0;
            src_ymin_hold_r  <= '0;
            src_xmax_hold_r  <= '0;
            src_ymax_hold_r  <= '0;
            src_score_hold_r <= '0;
        end
        else if (src_update_i) begin
            src_valid_hold_r <= src_valid_i;
            src_xmin_hold_r  <= src_xmin_i;
            src_ymin_hold_r  <= src_ymin_i;
            src_xmax_hold_r  <= src_xmax_i;
            src_ymax_hold_r  <= src_ymax_i;
            src_score_hold_r <= src_score_q16_i;
            src_toggle_r     <= ~src_toggle_r;
        end
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic toggle_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic toggle_sync_r;
    logic toggle_delay_r;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic        valid_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic        valid_sync_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [9:0]  xmin_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [9:0]  xmin_sync_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [8:0]  ymin_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [8:0]  ymin_sync_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [9:0]  xmax_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [9:0]  xmax_sync_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [8:0]  ymax_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [8:0]  ymax_sync_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [15:0] score_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic [15:0] score_sync_r;

    always_ff @(posedge dst_clk_i or negedge dst_rstn_i) begin
        if (!dst_rstn_i) begin
            toggle_meta_r      <= 1'b0;
            toggle_sync_r      <= 1'b0;
            toggle_delay_r     <= 1'b0;

            valid_meta_r       <= 1'b0;
            valid_sync_r       <= 1'b0;
            xmin_meta_r        <= '0;
            xmin_sync_r        <= '0;
            ymin_meta_r        <= '0;
            ymin_sync_r        <= '0;
            xmax_meta_r        <= '0;
            xmax_sync_r        <= '0;
            ymax_meta_r        <= '0;
            ymax_sync_r        <= '0;
            score_meta_r       <= '0;
            score_sync_r       <= '0;

            dst_update_o       <= 1'b0;
            dst_valid_o        <= 1'b0;
            dst_xmin_o         <= '0;
            dst_ymin_o         <= '0;
            dst_xmax_o         <= '0;
            dst_ymax_o         <= '0;
            dst_score_q16_o    <= '0;
        end
        else begin
            toggle_meta_r  <= src_toggle_r;
            toggle_sync_r  <= toggle_meta_r;
            toggle_delay_r <= toggle_sync_r;

            valid_meta_r <= src_valid_hold_r;
            valid_sync_r <= valid_meta_r;
            xmin_meta_r  <= src_xmin_hold_r;
            xmin_sync_r  <= xmin_meta_r;
            ymin_meta_r  <= src_ymin_hold_r;
            ymin_sync_r  <= ymin_meta_r;
            xmax_meta_r  <= src_xmax_hold_r;
            xmax_sync_r  <= xmax_meta_r;
            ymax_meta_r  <= src_ymax_hold_r;
            ymax_sync_r  <= ymax_meta_r;
            score_meta_r <= src_score_hold_r;
            score_sync_r <= score_meta_r;

            dst_update_o <= 1'b0;

            if (toggle_sync_r != toggle_delay_r) begin
                dst_update_o    <= 1'b1;
                dst_valid_o     <= valid_sync_r;
                dst_xmin_o      <= xmin_sync_r;
                dst_ymin_o      <= ymin_sync_r;
                dst_xmax_o      <= xmax_sync_r;
                dst_ymax_o      <= ymax_sync_r;
                dst_score_q16_o <= score_sync_r;
            end
        end
    end

endmodule
