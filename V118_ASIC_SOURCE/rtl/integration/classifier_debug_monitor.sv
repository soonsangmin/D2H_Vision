// V6.1.1 DEBUG, DE10-Nano 50MHz diagnostic LEDs.
// Observation only; does not drive handshake, clocks, or CNN data.
// SW[3:2] = 00 original classification, 01 DDR first two words,
//           10 progress milestones, 11 FC logit inspector.
// KEY[1] active-low, debounced: advance FC inspector page.
// V6.1.2: pages 9 and 10 now expose independent FC stream argmax and
// competing-score bitmask for class 3 (other modes remain unchanged).
module classifier_debug_monitor (
    input wire clk_i,
    input wire rstn_i,
    input wire [1:0] sw_page_async_i,
    input wire key_next_n_async_i,
    input wire [7:0] normal_led_i,
    output reg [7:0] led_o,
    input wire image_ready_i,
    input wire classifier_busy_i,
    input wire classifier_done_i,
    input wire alignment_error_i,
    input wire pair_fire_i,
    input wire fc_valid_i,
    input wire [2:0] fc_index_i,
    input wire signed [31:0] fc_value_i,
    input wire fc_frame_done_i,
    input wire [6:0] stage_mask_i,
    input wire [2:0] active_block_i,
    input wire exp_req_valid_i,
    input wire exp_req_ready_i,
    input wire [31:0] exp_req_addr_i,
    input wire exp_rsp_valid_i,
    input wire exp_rsp_ready_i,
    input wire [63:0] exp_rsp_data_i,
    input wire proj_req_valid_i,
    input wire proj_req_ready_i,
    input wire [31:0] proj_req_addr_i,
    input wire proj_rsp_valid_i,
    input wire proj_rsp_ready_i,
    input wire [63:0] proj_rsp_data_i
);
    reg [1:0] sw_meta, sw_sync;
    reg key_meta_n, key_sync_n;
    reg [18:0] key_stable_low;
    reg key_hold;
    reg [3:0] fc_page;
    reg image_seen, pair_seen, fc_seen, fc_done_seen, done_seen;
    reg alignment_seen, done_toggle;

    reg exp_req_seen, exp_rsp_seen, exp_first_low_match, exp_first_high_match;
    reg proj_req_seen, proj_rsp_seen, proj_first_low_match, proj_first_high_match;
    reg [31:0] exp_outstanding_addr, proj_outstanding_addr;

    reg [6:0] fc_mask_work, fc_mask_last;
    reg [6:0] stage_mask_last;
    reg frame_done_last;
    reg signed [31:0] score_work [0:6];
    reg signed [31:0] score_last [0:6];
    integer k;
    reg [7:0] score_digest;
    reg [7:0] fc_view;

    // Independent serial signed argmax scoreboard. This intentionally avoids
    // the CNN core's registered tournament tree. It operates on accepted FC
    // score events only and does not feed back into the inference datapath.
    reg winner_work_valid, winner_last_valid;
    reg signed [31:0] winner_work_score;
    reg [2:0] winner_work_index, winner_last_index;
    reg [6:0] class3_competitors;

    // 50 MHz: 500000 cycles approximately 10ms, one event per key press.
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            sw_meta <= 2'd0;
            sw_sync <= 2'd0;
            key_meta_n <= 1'b1;
            key_sync_n <= 1'b1;
            key_stable_low <= 19'd0;
            key_hold <= 1'b0;
            fc_page <= 4'd0;
        end else begin
            sw_meta <= sw_page_async_i;
            sw_sync <= sw_meta;
            key_meta_n <= key_next_n_async_i;
            key_sync_n <= key_meta_n;
            if (key_sync_n) begin
                key_stable_low <= 19'd0;
                key_hold <= 1'b0;
            end else if (!key_hold) begin
                if (key_stable_low == 19'd500000) begin
                    key_hold <= 1'b1;
                    if (fc_page == 4'd10) fc_page <= 4'd0;
                    else fc_page <= fc_page + 4'd1;
                end else begin
                    key_stable_low <= key_stable_low + 19'd1;
                end
            end
        end
    end

    // Accepted requests are tracked independently; one inflight per engine.
    // First two words of each file have known little-endian reference values.
    // Match bits are STICKY; a failed match never sets the corresponding LED.
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            exp_req_seen <= 1'b0;
            exp_rsp_seen <= 1'b0;
            exp_first_low_match <= 1'b0;
            exp_first_high_match <= 1'b0;
            proj_req_seen <= 1'b0;
            proj_rsp_seen <= 1'b0;
            proj_first_low_match <= 1'b0;
            proj_first_high_match <= 1'b0;
            exp_outstanding_addr <= 32'd0;
            proj_outstanding_addr <= 32'd0;
        end else begin
            if (exp_req_valid_i && exp_req_ready_i) begin
                exp_req_seen <= 1'b1;
                exp_outstanding_addr <= exp_req_addr_i;
            end
            if (exp_rsp_valid_i && exp_rsp_ready_i) begin
                exp_rsp_seen <= 1'b1;
                if (exp_outstanding_addr == 32'h3500_0000 &&
                    exp_rsp_data_i == 64'hEFF0_FAB8_3D2A_2210)
                    exp_first_low_match <= 1'b1;
                if (exp_outstanding_addr == 32'h3500_0008 &&
                    exp_rsp_data_i == 64'h0000_0000_1128_F44C)
                    exp_first_high_match <= 1'b1;
            end
            if (proj_req_valid_i && proj_req_ready_i) begin
                proj_req_seen <= 1'b1;
                proj_outstanding_addr <= proj_req_addr_i;
            end
            if (proj_rsp_valid_i && proj_rsp_ready_i) begin
                proj_rsp_seen <= 1'b1;
                if (proj_outstanding_addr == 32'h3502_0000 &&
                    proj_rsp_data_i == 64'hB2EF_EF17_001E_42DB)
                    proj_first_low_match <= 1'b1;
                if (proj_outstanding_addr == 32'h3502_0008 &&
                    proj_rsp_data_i == 64'h0000_0000_DD04_2000)
                    proj_first_high_match <= 1'b1;
            end
        end
    end

    // Persist observation across per-image classifier reset (bridge locally
    // resets CNN). Capturing logits at classifier_done preserves final scores.
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            image_seen <= 1'b0;
            pair_seen <= 1'b0;
            fc_seen <= 1'b0;
            fc_done_seen <= 1'b0;
            done_seen <= 1'b0;
            alignment_seen <= 1'b0;
            done_toggle <= 1'b0;
            fc_mask_work <= 7'd0;
            fc_mask_last <= 7'd0;
            stage_mask_last <= 7'd0;
            frame_done_last <= 1'b0;
            winner_work_valid <= 1'b0;
            winner_last_valid <= 1'b0;
            winner_work_score <= 32'sd0;
            winner_work_index <= 3'd0;
            winner_last_index <= 3'd0;
            for (k=0; k<7; k=k+1) begin
                score_work[k] <= 32'sd0;
                score_last[k] <= 32'sd0;
            end
        end else begin
            if (image_ready_i) begin
                image_seen <= 1'b1;
                fc_mask_work <= 7'd0;
                winner_work_valid <= 1'b0;
                for (k=0; k<7; k=k+1)
                    score_work[k] <= 32'sd0;
            end
            if (pair_fire_i) pair_seen <= 1'b1;
            if (fc_valid_i && fc_index_i < 3'd7) begin
                fc_seen <= 1'b1;
                fc_mask_work[fc_index_i] <= 1'b1;
                score_work[fc_index_i] <= fc_value_i;
                if (!winner_work_valid ||
                    (fc_value_i > winner_work_score) ||
                    ((fc_value_i == winner_work_score) &&
                     (fc_index_i < winner_work_index))) begin
                    winner_work_valid <= 1'b1;
                    winner_work_score <= fc_value_i;
                    winner_work_index <= fc_index_i;
                end
            end
            if (fc_frame_done_i) fc_done_seen <= 1'b1;
            if (alignment_error_i) alignment_seen <= 1'b1;
            if (classifier_done_i) begin
                done_seen <= 1'b1;
                done_toggle <= ~done_toggle;
                fc_mask_last <= fc_mask_work;
                winner_last_valid <= winner_work_valid;
                winner_last_index <= winner_work_index;
                stage_mask_last <= stage_mask_i;
                frame_done_last <= fc_done_seen;
                for (k=0; k<7; k=k+1)
                    score_last[k] <= score_work[k];
            end
        end
    end

    // Signature incorporates ALL FOUR bytes of each of seven signed FC logits.
    // It is a coarse quick-check only; SignalTap can capture full 32-bit values.
    always @(*) begin
        score_digest = 8'd0;
        for (integer j=0; j<7; j=j+1)
            score_digest = {score_digest[6:0], score_digest[7]} ^
                           score_last[j][7:0] ^ score_last[j][15:8] ^
                           score_last[j][23:16] ^ score_last[j][31:24] ^ j;
        // Any lit bit means that class would beat class 3 under the signed
        // tournament tie policy (equal score -> smaller class index).
        class3_competitors = 7'd0;
        for (integer c=0; c<7; c=c+1) begin
            if (c < 3)
                class3_competitors[c] = (score_last[c] >= score_last[3]);
            else if (c > 3)
                class3_competitors[c] = (score_last[c] > score_last[3]);
        end
        case (fc_page)
            4'd0: fc_view = {frame_done_last, fc_mask_last};
            4'd1: fc_view = score_last[0][7:0];
            4'd2: fc_view = score_last[1][7:0];
            4'd3: fc_view = score_last[2][7:0];
            4'd4: fc_view = score_last[3][7:0];
            4'd5: fc_view = score_last[4][7:0];
            4'd6: fc_view = score_last[5][7:0];
            4'd7: fc_view = score_last[6][7:0];
            4'd8: fc_view = score_digest;
            // Page 9: bit7=valid, bits[6:0]=independent winning class.
            // Expect 0x88 for class 3. Compare this with normal mode 00.
            4'd9: fc_view = winner_last_valid ?
                           {1'b1, (7'b0000001 << winner_last_index)} : 8'd0;
            // Page 10: bit i means score[i] would beat score[3].
            // Expect 0x00 if class 3 truly wins all signed logits.
            4'd10: fc_view = {1'b0, class3_competitors};
            default: fc_view = 8'd0;
        endcase
    end

    always @(*) begin
        case (sw_sync)
            2'b00: led_o = normal_led_i;
            2'b01: led_o = 8'h00; // BRAM classifier: DDR test not applicable
            2'b10: led_o = {classifier_busy_i, done_toggle, alignment_seen,
                            done_seen, fc_done_seen, fc_seen,
                            pair_seen, image_seen};
            2'b11: led_o = fc_view;
            default: led_o = normal_led_i;
        endcase
    end
endmodule
