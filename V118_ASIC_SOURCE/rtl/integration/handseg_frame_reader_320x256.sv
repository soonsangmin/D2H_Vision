module handseg_frame_reader_320x256 (
    input  logic        clk_i,
    input  logic        rstn_i,

    input  logic        frame_available_i,
    output logic        frame_take_o,

    output logic        rd_req_o,
    output logic [16:0] rd_addr_o,
    input  logic        rd_valid_i,
    input  logic [23:0] rd_data_i,

    output logic        pixel_valid_o,
    input  logic        pixel_ready_i,
    output logic [23:0] pixel_data_o,

    output logic        frame_start_o,
    output logic        frame_done_o,
    output logic        busy_o
);

    localparam integer FRAME_PIXELS = 320 * 256;

    typedef enum logic [2:0] {
        S_IDLE,
        S_REQ,
        S_WAIT,
        S_HOLD
    } state_t;

    state_t state_r;
    logic [16:0] addr_r;
    logic [23:0] hold_data_r;

    assign busy_o       = (state_r != S_IDLE);
    assign rd_addr_o    = addr_r;
    assign rd_req_o     = (state_r == S_REQ);
    assign pixel_valid_o = (state_r == S_HOLD);
    assign pixel_data_o = hold_data_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r       <= S_IDLE;
            addr_r        <= 17'd0;
            hold_data_r   <= 24'd0;
            frame_take_o  <= 1'b0;
            frame_start_o <= 1'b0;
            frame_done_o  <= 1'b0;
        end
        else begin
            frame_take_o  <= 1'b0;
            frame_start_o <= 1'b0;
            frame_done_o  <= 1'b0;

            case (state_r)
                S_IDLE: begin
                    if (frame_available_i) begin
                        frame_take_o  <= 1'b1;
                        frame_start_o <= 1'b1;
                        addr_r        <= 17'd0;
                        state_r       <= S_REQ;
                    end
                end

                S_REQ: begin
                    state_r <= S_WAIT;
                end

                S_WAIT: begin
                    if (rd_valid_i) begin
                        hold_data_r <= rd_data_i;
                        state_r     <= S_HOLD;
                    end
                end

                S_HOLD: begin
                    if (pixel_ready_i) begin
                        if (addr_r == FRAME_PIXELS-1) begin
                            frame_done_o <= 1'b1;
                            addr_r       <= 17'd0;
                            state_r      <= S_IDLE;
                        end
                        else begin
                            addr_r  <= addr_r + 1'b1;
                            state_r <= S_REQ;
                        end
                    end
                end

                default: state_r <= S_IDLE;
            endcase
        end
    end

endmodule
