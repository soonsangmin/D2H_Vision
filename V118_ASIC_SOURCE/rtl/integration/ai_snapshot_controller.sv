module ai_snapshot_controller (
    input  logic clk_i,
    input  logic rstn_i,

    // Detector result pulse. Mapped ROI registers update on the same detector
    // edge, therefore this FSM intentionally checks roi_valid_i one cycle later.
    input  logic inference_done_i,
    input  logic roi_valid_i,

    // RGB565 crop/resize completion and Sobel completion.
    input  logic crop_done_i,
    input  logic sobel_done_i,

    // V5.8: the real classifier is the consumer.  SW1 is display-only and no
    // longer participates in the AI handshake.
    input  logic classifier_done_i,

    output logic crop_start_o,
    output logic sobel_start_o,
    output logic sobel96_ready_pulse_o,
    output logic release_ai_frame_o,
    output logic waiting_for_consumer_o,
    output logic no_hand_o
);
    typedef enum logic [2:0] {
        S_WAIT_RESULT,
        S_CHECK_RESULT,
        S_WAIT_CROP,
        S_WAIT_SOBEL,
        S_WAIT_CLASSIFIER
    } state_t;

    state_t state_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r                 <= S_WAIT_RESULT;
            crop_start_o            <= 1'b0;
            sobel_start_o           <= 1'b0;
            sobel96_ready_pulse_o   <= 1'b0;
            release_ai_frame_o      <= 1'b0;
            waiting_for_consumer_o  <= 1'b0;
            no_hand_o               <= 1'b0;
        end else begin
            crop_start_o          <= 1'b0;
            sobel_start_o         <= 1'b0;
            sobel96_ready_pulse_o <= 1'b0;
            release_ai_frame_o    <= 1'b0;
            no_hand_o             <= 1'b0;

            case (state_r)
                S_WAIT_RESULT: begin
                    waiting_for_consumer_o <= 1'b0;
                    if (inference_done_i)
                        state_r <= S_CHECK_RESULT;
                end

                S_CHECK_RESULT: begin
                    if (roi_valid_i) begin
                        crop_start_o <= 1'b1;
                        state_r      <= S_WAIT_CROP;
                    end else begin
                        // No hand -> no Sobel/classifier image is produced.
                        release_ai_frame_o <= 1'b1;
                        no_hand_o          <= 1'b1;
                        state_r            <= S_WAIT_RESULT;
                    end
                end

                S_WAIT_CROP: begin
                    if (crop_done_i) begin
                        // Keep the frozen camera snapshot locked while Sobel reads
                        // the RGB565 96x96 crop.
                        sobel_start_o <= 1'b1;
                        state_r       <= S_WAIT_SOBEL;
                    end
                end

                S_WAIT_SOBEL: begin
                    if (sobel_done_i) begin
                        // The SW1 Sobel debug image is complete and the shared
                        // RGB96 BRAM read port is now free. Start the V6.0
                        // classifier, which re-reads RGB565 and performs its own
                        // exact Gray/Sobel preprocessing internally.
                        sobel96_ready_pulse_o  <= 1'b1;
                        waiting_for_consumer_o <= 1'b1;
                        state_r                <= S_WAIT_CLASSIFIER;
                    end
                end

                S_WAIT_CLASSIFIER: begin
                    waiting_for_consumer_o <= 1'b1;
                    if (classifier_done_i) begin
                        // Conservative ownership rule: do not start the next AI
                        // cycle until the real classifier has completed.  This is
                        // slower but prevents every Sobel/crop overwrite race.
                        release_ai_frame_o     <= 1'b1;
                        waiting_for_consumer_o <= 1'b0;
                        state_r                <= S_WAIT_RESULT;
                    end
                end

                default: state_r <= S_WAIT_RESULT;
            endcase
        end
    end
endmodule
