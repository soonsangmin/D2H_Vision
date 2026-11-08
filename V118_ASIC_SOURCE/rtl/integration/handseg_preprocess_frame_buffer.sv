module handseg_preprocess_frame_buffer #(
    parameter integer XRES = 320,
    parameter integer YRES = 256
)(
    input  logic        wr_clk_i,
    input  logic        wr_rstn_i,
    input  logic        frame_start_i,
    input  logic        pixel_valid_i,
    input  logic [23:0] pixel_data_i,
    input  logic        frame_done_i,

    input  logic        rd_clk_i,
    input  logic        rd_rstn_i,
    output logic        frame_available_o,
    output logic        frame_ready_pulse_o,
    input  logic        frame_take_i,

    input  logic                         rd_req_i,
    input  logic [$clog2(XRES*YRES)-1:0] rd_addr_i,
    output logic                         rd_valid_o,
    output logic [23:0]                  rd_data_o
);

    localparam integer FRAME_PIXELS = XRES * YRES;
    localparam integer ADDR_WIDTH   = $clog2(FRAME_PIXELS);

    // Temporary full-frame CDC buffer used for functional integration.
    // No reset is applied to the RAM array so Quartus can infer block RAM.
    (* ramstyle = "M10K, no_rw_check" *)
    logic [23:0] frame_mem [0:FRAME_PIXELS-1];

    logic [ADDR_WIDTH-1:0] wr_addr_r;
    logic [ADDR_WIDTH-1:0] wr_addr_used_c;

    always_comb begin
        if (frame_start_i)
            wr_addr_used_c = '0;
        else
            wr_addr_used_c = wr_addr_r;
    end

    always_ff @(posedge wr_clk_i) begin
        if (pixel_valid_i)
            frame_mem[wr_addr_used_c] <= pixel_data_i;
    end

    always_ff @(posedge wr_clk_i or negedge wr_rstn_i) begin
        if (!wr_rstn_i) begin
            wr_addr_r <= '0;
        end
        else begin
            if (frame_start_i) begin
                if (pixel_valid_i && (FRAME_PIXELS > 1))
                    wr_addr_r <= {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                else
                    wr_addr_r <= '0;
            end
            else if (pixel_valid_i) begin
                if (wr_addr_r == FRAME_PIXELS-1)
                    wr_addr_r <= '0;
                else
                    wr_addr_r <= wr_addr_r + 1'b1;
            end
        end
    end

    logic frame_done_toggle_r;

    always_ff @(posedge wr_clk_i or negedge wr_rstn_i) begin
        if (!wr_rstn_i)
            frame_done_toggle_r <= 1'b0;
        else if (frame_done_i)
            frame_done_toggle_r <= ~frame_done_toggle_r;
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic frame_toggle_meta_r;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic frame_toggle_sync_r;
    logic frame_toggle_delay_r;

    always_ff @(posedge rd_clk_i or negedge rd_rstn_i) begin
        if (!rd_rstn_i) begin
            frame_toggle_meta_r  <= 1'b0;
            frame_toggle_sync_r  <= 1'b0;
            frame_toggle_delay_r <= 1'b0;
        end
        else begin
            frame_toggle_meta_r  <= frame_done_toggle_r;
            frame_toggle_sync_r  <= frame_toggle_meta_r;
            frame_toggle_delay_r <= frame_toggle_sync_r;
        end
    end

    assign frame_ready_pulse_o = frame_toggle_sync_r ^ frame_toggle_delay_r;

    always_ff @(posedge rd_clk_i or negedge rd_rstn_i) begin
        if (!rd_rstn_i)
            frame_available_o <= 1'b0;
        else begin
            if (frame_ready_pulse_o)
                frame_available_o <= 1'b1;
            else if (frame_take_i)
                frame_available_o <= 1'b0;
        end
    end

    logic [23:0] rd_data_r;

    always_ff @(posedge rd_clk_i) begin
        if (rd_req_i)
            rd_data_r <= frame_mem[rd_addr_i];
    end

    assign rd_data_o = rd_data_r;

    always_ff @(posedge rd_clk_i or negedge rd_rstn_i) begin
        if (!rd_rstn_i)
            rd_valid_o <= 1'b0;
        else
            rd_valid_o <= rd_req_i;
    end

endmodule
