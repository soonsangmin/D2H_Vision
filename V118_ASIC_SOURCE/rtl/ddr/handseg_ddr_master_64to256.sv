module handseg_ddr_master_64to256 #(
    parameter logic [31:0] UNCACHED_ADDR = 32'h349F_F000,
    parameter logic [31:0] AI_DDR_BASE   = 32'h3400_0000,
    parameter logic [31:0] AI_DDR_END    = 32'h34A0_0000,
    parameter logic [31:0] SNAPSHOT_BASE = 32'h3200_0000,
    parameter logic [31:0] SNAPSHOT_END  = 32'h3209_6000,
    parameter logic [31:0] CLASSIFIER_BASE=32'h3500_0000,
    parameter logic [31:0] CLASSIFIER_END =32'h3504_0000
) (
    input  logic         clk_i,
    input  logic         rstn_i,
    input  logic         quiesce_i,
    output logic         drain_idle_o,

    input  logic         rd_req_valid_i,
    output logic         rd_req_ready_o,
    input  logic [31:0]  rd_req_addr_i,
    output logic         rd_rsp_valid_o,
    input  logic         rd_rsp_ready_i,
    output logic [63:0]  rd_rsp_data_o,

    input  logic         wr_req_valid_i,
    output logic         wr_req_ready_o,
    input  logic [31:0]  wr_req_addr_i,
    input  logic [63:0]  wr_req_data_i,

    output logic         avm_read_o,
    output logic         avm_write_o,
    output logic [255:0] avm_writedata_o,
    output logic [31:0]  avm_address_o,
    input  logic [255:0] avm_readdata_i,
    input  logic         avm_readdatavalid_i,
    output logic [31:0]  avm_byteenable_o,
    input  logic         avm_waitrequest_i,
    output logic [10:0]  avm_burstcount_o
);

    // =====================================================================
    // V5.1 - 24 PE / BURST-8 / PING-PONG DDR FRONT END
    // =====================================================================
    // No tracking/debug modes are added here.  The CNN datapath remains the
    // proven V4.9 24-PE pixel-major engine.
    //
    // READ PATH
    //   * cached AI reads use one 8-beat x 256-bit Avalon burst = 256 bytes;
    //   * two 256-byte read banks are kept on-chip (ping/pong);
    //   * while one bank serves cache hits, the other bank may be filled with
    //     the next sequential 256-byte line;
    //   * prefetch starts only after accesses reach the upper half of a line,
    //     reducing useless speculative DDR traffic;
    //   * the magic/uncached address still uses a single beat.
    //
    // WRITE PATH
    //   * two independent 256-bit write-combine lines absorb 64-bit result
    //     writes while the other line is draining to DDR;
    //   * DDR writes intentionally remain burstcount=1 for video safety;
    //   * all dirty write lines are drained before any read is accepted, so a
    //     following layer always observes completed results.
    //
    // Address firewall:
    //   WRITE: 0x3400_0000 <= address < 0x34A0_0000 only.
    //   READ : same AI workspace plus the frozen RGB565 snapshot
    //          0x3200_0000 <= address < 0x3209_6000.
    // The live HDMI framebuffer at 0x3000_0000 remains unreachable from AI.
    // =====================================================================

    localparam integer RD_BURST_BEATS = 8;
    localparam logic [10:0] RD_BURST_COUNT = 11'd8;
    localparam integer WR_IDLE_FLUSH_CYCLES = 1024;

    typedef enum logic [2:0] {
        B_IDLE,
        B_RD_ISSUE,
        B_RD_WAIT,
        B_WR_ISSUE
    } bus_state_t;

    bus_state_t bus_state_r;
    // Ignore discarded client responses when stopped, but drain all accepted DDR beats.
    assign drain_idle_o = (bus_state_r == B_IDLE) && !any_dirty_c;

    // ---------------------------------------------------------------------
    // Address helpers
    // ---------------------------------------------------------------------
    function automatic logic ai_addr_ok(input logic [31:0] a);
        begin
            ai_addr_ok = (a >= AI_DDR_BASE) && (a < AI_DDR_END) &&
                         (a[2:0] == 3'b000);
        end
    endfunction

    function automatic logic snapshot_addr_ok(input logic [31:0] a);
        begin
            snapshot_addr_ok = (a >= SNAPSHOT_BASE) && (a < SNAPSHOT_END) &&
                               (a[2:0] == 3'b000);
        end
    endfunction

    function automatic logic classifier_addr_ok(input logic [31:0] a);
        begin
            classifier_addr_ok = (a>=CLASSIFIER_BASE) && (a<CLASSIFIER_END) && (a[2:0]==3'b000);
        end
    endfunction

    function automatic logic rd_addr_ok(input logic [31:0] a);
        begin
            rd_addr_ok = ai_addr_ok(a) || snapshot_addr_ok(a) || classifier_addr_ok(a);
        end
    endfunction

    function automatic [63:0] select_lane64(
        input logic [255:0] beat,
        input logic [1:0] lane
    );
        begin
            case (lane)
                2'd0: select_lane64 = beat[63:0];
                2'd1: select_lane64 = beat[127:64];
                2'd2: select_lane64 = beat[191:128];
                default: select_lane64 = beat[255:192];
            endcase
        end
    endfunction

    function automatic [31:0] lane_be64(input logic [1:0] lane);
        begin
            case (lane)
                2'd0: lane_be64 = 32'h0000_00FF;
                2'd1: lane_be64 = 32'h0000_FF00;
                2'd2: lane_be64 = 32'h00FF_0000;
                default: lane_be64 = 32'hFF00_0000;
            endcase
        end
    endfunction

    function automatic [255:0] merge_lane64(
        input logic [255:0] old_word,
        input logic [1:0] lane,
        input logic [63:0] data
    );
        reg [255:0] tmp;
        begin
            tmp = old_word;
            case (lane)
                2'd0: tmp[63:0]    = data;
                2'd1: tmp[127:64]  = data;
                2'd2: tmp[191:128] = data;
                default: tmp[255:192] = data;
            endcase
            merge_lane64 = tmp;
        end
    endfunction

    // ---------------------------------------------------------------------
    // Ping-pong read cache: two 256-byte lines.
    // ---------------------------------------------------------------------
    logic        rd_tag0_valid_r, rd_tag1_valid_r;
    logic [23:0] rd_tag0_base_r,  rd_tag1_base_r; // address[31:8]
    logic        rd_last_bank_r;

    logic        rd_ram_wr_en_c;
    logic [3:0]  rd_ram_wr_addr_c;
    logic [255:0] rd_ram_wr_data_c;
    logic [3:0]  rd_ram_rd_addr_r;
    logic [255:0] rd_ram_rd_data;

    handseg_ddr_read_pingpong_ram u_read_pingpong_ram (
        .clk_i(clk_i),
        .wr_en_i(rd_ram_wr_en_c),
        .wr_addr_i(rd_ram_wr_addr_c),
        .wr_data_i(rd_ram_wr_data_c),
        .rd_addr_i(rd_ram_rd_addr_r),
        .rd_data_o(rd_ram_rd_data)
    );

    logic rd_req_addr_ok_c;
    logic rd_req_uncached_c;
    logic rd_req_snapshot_c;
    logic snapshot_session_r;
    logic [31:0] rd_region_end_c;
    logic rd_hit0_c, rd_hit1_c, rd_hit_c, rd_hit_bank_c;
    logic [23:0] rd_req_line_c;
    logic [2:0] rd_req_beat_c;
    logic [1:0] rd_req_lane_c;

    assign rd_req_addr_ok_c  = rd_addr_ok(rd_req_addr_i);
    assign rd_req_uncached_c = (rd_req_addr_i == UNCACHED_ADDR);
    assign rd_req_snapshot_c = snapshot_addr_ok(rd_req_addr_i);
    assign rd_region_end_c   = rd_req_snapshot_c ? SNAPSHOT_END :
                               classifier_addr_ok(rd_req_addr_i) ? CLASSIFIER_END : AI_DDR_END;
    assign rd_req_line_c     = rd_req_addr_i[31:8];
    assign rd_req_beat_c     = rd_req_addr_i[7:5];
    assign rd_req_lane_c     = rd_req_addr_i[4:3];
    // Snapshot memory is written by the independent camera writer, so cache
    // lines from the previous AI frame must never survive into the next crop.
    // The first snapshot access of each detector->crop session is forced to
    // miss; its acceptance invalidates both tags. Subsequent accesses may hit.
    assign rd_hit0_c = rd_tag0_valid_r && !rd_req_uncached_c &&
                       rd_req_addr_ok_c &&
                       (!rd_req_snapshot_c || snapshot_session_r) &&
                       (rd_tag0_base_r == rd_req_line_c);
    assign rd_hit1_c = rd_tag1_valid_r && !rd_req_uncached_c &&
                       rd_req_addr_ok_c &&
                       (!rd_req_snapshot_c || snapshot_session_r) &&
                       (rd_tag1_base_r == rd_req_line_c);
    assign rd_hit_c = rd_hit0_c | rd_hit1_c;
    assign rd_hit_bank_c = rd_hit1_c;

    // One-deep read response plus a two-clock synchronous M10K read pipeline.
    logic        rd_rsp_valid_r;
    logic [63:0] rd_rsp_data_r;
    logic        rd_lookup_d1_r, rd_lookup_d2_r;
    logic [1:0]  rd_lookup_lane_d1_r, rd_lookup_lane_d2_r;

    assign rd_rsp_valid_o = rd_rsp_valid_r;
    assign rd_rsp_data_o  = rd_rsp_data_r;

    // Accepted demand miss / uncached request.
    logic        demand_pending_r;
    logic        demand_uncached_r;
    logic [31:0] demand_addr_r;
    logic        demand_fill_bank_r;

    // Optional sequential prefetch request.
    logic        prefetch_pending_r;
    logic [23:0] prefetch_line_r;
    logic        prefetch_fill_bank_r;

    // Read bus transaction bookkeeping.
    logic        bus_rd_prefetch_r;
    logic        bus_rd_uncached_r;
    logic [31:0] bus_rd_addr_r;
    logic        bus_rd_fill_bank_r;
    logic [3:0]  bus_rd_recv_count_r;

    // ---------------------------------------------------------------------
    // Two write-combine buffers.  Each buffer represents one aligned 32-byte
    // Avalon beat and may collect four independent 64-bit writes.
    // ---------------------------------------------------------------------
    logic        wr0_valid_r, wr1_valid_r;
    logic [26:0] wr0_base_r,  wr1_base_r; // address[31:5]
    logic [255:0] wr0_data_r, wr1_data_r;
    logic [31:0] wr0_be_r, wr1_be_r;
    logic [9:0]  wr_idle_count_r;

    logic        bus_wr_bank_r;

    logic wr_req_addr_ok_c;
    logic [26:0] wr_req_base_c;
    logic [1:0]  wr_req_lane_c;
    logic [31:0] wr_req_lane_be_c;
    logic wr_match0_c, wr_match1_c;
    logic wr0_locked_c, wr1_locked_c;
    logic wr_can_use0_c, wr_can_use1_c;
    logic wr_need_space_c;
    logic any_dirty_c;
    logic wr0_full_c, wr1_full_c;

    assign wr_req_addr_ok_c = ai_addr_ok(wr_req_addr_i);
    assign wr_req_base_c    = wr_req_addr_i[31:5];
    assign wr_req_lane_c    = wr_req_addr_i[4:3];
    assign wr_req_lane_be_c = lane_be64(wr_req_lane_c);

    assign wr0_locked_c = (bus_state_r == B_WR_ISSUE) && (bus_wr_bank_r == 1'b0);
    assign wr1_locked_c = (bus_state_r == B_WR_ISSUE) && (bus_wr_bank_r == 1'b1);
    assign wr_match0_c = wr0_valid_r && !wr0_locked_c &&
                         (wr0_base_r == wr_req_base_c);
    assign wr_match1_c = wr1_valid_r && !wr1_locked_c &&
                         (wr1_base_r == wr_req_base_c);
    assign wr_can_use0_c = wr_match0_c || (!wr0_valid_r && !wr0_locked_c);
    assign wr_can_use1_c = wr_match1_c || (!wr1_valid_r && !wr1_locked_c);
    assign wr_need_space_c = wr_req_valid_i && wr_req_addr_ok_c &&
                             !wr_can_use0_c && !wr_can_use1_c;
    assign any_dirty_c = wr0_valid_r | wr1_valid_r;
    assign wr0_full_c = wr0_valid_r && (wr0_be_r == 32'hFFFF_FFFF);
    assign wr1_full_c = wr1_valid_r && (wr1_be_r == 32'hFFFF_FFFF);

    // ---------------------------------------------------------------------
    // Upstream ready policy
    // ---------------------------------------------------------------------
    // Preserve write->read ordering: no read is accepted until both write
    // buffers have drained.  A cache hit may still be served while a background
    // prefetch burst is in flight because it uses only the local M10K bank.
    logic read_pipe_busy_c;
    assign read_pipe_busy_c = rd_rsp_valid_r | rd_lookup_d1_r | rd_lookup_d2_r |
                              demand_pending_r;

    assign rd_req_ready_o = rstn_i && !quiesce_i && !any_dirty_c && !read_pipe_busy_c &&
                            (rd_hit_c ||
                             (!rd_req_addr_ok_c) ||
                             (bus_state_r == B_IDLE));

    // Reads retain priority at the logical request interface.  Writes may be
    // accepted while a previous write buffer is draining as long as the other
    // ping-pong line can absorb the new word.
    assign wr_req_ready_o = rstn_i && !quiesce_i && !rd_req_valid_i &&
                            (!wr_req_addr_ok_c ||
                             (((bus_state_r != B_RD_ISSUE) &&
                               (bus_state_r != B_RD_WAIT)) &&
                              (wr_can_use0_c || wr_can_use1_c)));

    // ---------------------------------------------------------------------
    // Avalon outputs from independent bus engine
    // ---------------------------------------------------------------------
    always_comb begin
        avm_read_o       = 1'b0;
        avm_write_o      = 1'b0;
        avm_writedata_o  = 256'd0;
        avm_address_o    = 32'd0;
        avm_byteenable_o = 32'd0;
        avm_burstcount_o = 11'd1;

        case (bus_state_r)
            B_RD_ISSUE: begin
                avm_read_o       = 1'b1;
                avm_byteenable_o = 32'hFFFF_FFFF;
                if (bus_rd_uncached_r) begin
                    avm_address_o    = {bus_rd_addr_r[31:5], 5'b0};
                    avm_burstcount_o = 11'd1;
                end else begin
                    avm_address_o    = {bus_rd_addr_r[31:8], 8'b0};
                    avm_burstcount_o = RD_BURST_COUNT;
                end
            end

            B_WR_ISSUE: begin
                avm_write_o      = 1'b1;
                avm_burstcount_o = 11'd1;
                if (!bus_wr_bank_r) begin
                    avm_address_o    = {wr0_base_r, 5'b0};
                    avm_writedata_o  = wr0_data_r;
                    avm_byteenable_o = wr0_be_r;
                end else begin
                    avm_address_o    = {wr1_base_r, 5'b0};
                    avm_writedata_o  = wr1_data_r;
                    avm_byteenable_o = wr1_be_r;
                end
            end

            default: begin end
        endcase
    end

    // V6.23 timing: register the complete Avalon DDR read beat together
    // with readdatavalid.  HPS hard-interface flops no longer directly drive
    // the MLAB write data pins.  Crucially, the bus FSM and RAM write enable
    // both consume this *same delayed beat/valid pair*, keeping burst-8
    // addressing, last-beat/tag completion, and quiesce/drain consistent.
    logic [255:0] avm_readdata_q;
    logic         avm_readdatavalid_q;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            avm_readdata_q      <= 256'd0;
            avm_readdatavalid_q <= 1'b0;
        end else begin
            avm_readdata_q      <= avm_readdata_i;
            avm_readdatavalid_q <= avm_readdatavalid_i;
        end
    end

    // Bus-fill write port for the ping-pong read RAM.
    always_comb begin
        rd_ram_wr_en_c   = 1'b0;
        rd_ram_wr_addr_c = 4'd0;
        rd_ram_wr_data_c = avm_readdata_q;

        if ((bus_state_r == B_RD_WAIT) && avm_readdatavalid_q &&
            !bus_rd_uncached_r) begin
            rd_ram_wr_en_c   = 1'b1;
            rd_ram_wr_addr_c = {bus_rd_fill_bank_r, bus_rd_recv_count_r[2:0]};
        end
    end

    // ---------------------------------------------------------------------
    // Sequential control
    // ---------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            bus_state_r <= B_IDLE;

            rd_tag0_valid_r <= 1'b0;
            rd_tag1_valid_r <= 1'b0;
            snapshot_session_r <= 1'b0;
            rd_tag0_base_r  <= 24'd0;
            rd_tag1_base_r  <= 24'd0;
            rd_last_bank_r  <= 1'b0;
            rd_ram_rd_addr_r <= 4'd0;

            rd_rsp_valid_r <= 1'b0;
            rd_rsp_data_r  <= 64'd0;
            rd_lookup_d1_r <= 1'b0;
            rd_lookup_d2_r <= 1'b0;
            rd_lookup_lane_d1_r <= 2'd0;
            rd_lookup_lane_d2_r <= 2'd0;

            demand_pending_r   <= 1'b0;
            demand_uncached_r  <= 1'b0;
            demand_addr_r      <= 32'd0;
            demand_fill_bank_r <= 1'b0;

            prefetch_pending_r   <= 1'b0;
            prefetch_line_r      <= 24'd0;
            prefetch_fill_bank_r <= 1'b0;

            bus_rd_prefetch_r   <= 1'b0;
            bus_rd_uncached_r   <= 1'b0;
            bus_rd_addr_r       <= 32'd0;
            bus_rd_fill_bank_r  <= 1'b0;
            bus_rd_recv_count_r <= 4'd0;

            wr0_valid_r <= 1'b0;
            wr1_valid_r <= 1'b0;
            wr0_base_r <= 27'd0;
            wr1_base_r <= 27'd0;
            wr0_data_r <= 256'd0;
            wr1_data_r <= 256'd0;
            wr0_be_r <= 32'd0;
            wr1_be_r <= 32'd0;
            wr_idle_count_r <= 10'd0;
            bus_wr_bank_r <= 1'b0;
        end else begin
            // -------------------------------------------------------------
            // Read response hold and synchronous local-RAM pipeline.
            // -------------------------------------------------------------
            if (rd_rsp_valid_r && rd_rsp_ready_i)
                rd_rsp_valid_r <= 1'b0;

            rd_lookup_d2_r <= rd_lookup_d1_r;
            rd_lookup_lane_d2_r <= rd_lookup_lane_d1_r;
            rd_lookup_d1_r <= 1'b0;

            if (rd_lookup_d2_r && !rd_rsp_valid_r) begin
                rd_rsp_data_r  <= select_lane64(rd_ram_rd_data,
                                                rd_lookup_lane_d2_r);
                rd_rsp_valid_r <= 1'b1;
            end

            // -------------------------------------------------------------
            // Accept a read request.
            // -------------------------------------------------------------
            if (rd_req_valid_i && rd_req_ready_o) begin
                if (rd_req_snapshot_c) begin
                    if (!snapshot_session_r) begin
                        // New frozen camera frame at the same fixed address.
                        // Drop any cached lines from the previous frame.
                        rd_tag0_valid_r <= 1'b0;
                        rd_tag1_valid_r <= 1'b0;
                    end
                    snapshot_session_r <= 1'b1;
                end else begin
                    // Detector/parameter traffic separates snapshot sessions.
                    snapshot_session_r <= 1'b0;
                end

                if (!rd_req_addr_ok_c) begin
                    rd_rsp_data_r  <= 64'd0;
                    rd_rsp_valid_r <= 1'b1;
                end else if (rd_hit_c) begin
                    rd_ram_rd_addr_r <= {rd_hit_bank_c, rd_req_beat_c};
                    rd_lookup_lane_d1_r <= rd_req_lane_c;
                    rd_lookup_d1_r <= 1'b1;
                    rd_last_bank_r <= rd_hit_bank_c;

                    // Conservative next-line prefetch.  Trigger only after the
                    // requester has entered the upper 128 bytes of the current
                    // 256-byte line and only when the next line remains inside
                    // the AI DDR firewall.
                    if (rd_req_addr_i[7] &&
                        ({rd_req_line_c,8'h00} + 32'd256 < rd_region_end_c) &&
                        !((rd_tag0_valid_r &&
                           (rd_tag0_base_r == rd_req_line_c + 1'b1)) ||
                          (rd_tag1_valid_r &&
                           (rd_tag1_base_r == rd_req_line_c + 1'b1)))) begin
                        prefetch_pending_r <= 1'b1;
                        prefetch_line_r <= rd_req_line_c + 1'b1;
                        prefetch_fill_bank_r <= ~rd_hit_bank_c;
                    end
                end else begin
                    // Demand miss or the explicitly uncached magic read.
                    demand_pending_r  <= 1'b1;
                    demand_uncached_r <= rd_req_uncached_c;
                    demand_addr_r     <= rd_req_addr_i;

                    if (!rd_req_uncached_c) begin
                        if (!rd_tag0_valid_r)
                            demand_fill_bank_r <= 1'b0;
                        else if (!rd_tag1_valid_r)
                            demand_fill_bank_r <= 1'b1;
                        else
                            demand_fill_bank_r <= ~rd_last_bank_r;
                    end

                    // A real demand miss supersedes a not-yet-launched guess.
                    prefetch_pending_r <= 1'b0;
                end
            end

            // -------------------------------------------------------------
            // Accept/merge a 64-bit write into either ping-pong line.
            // Existing-line matches are always preferred over allocating a
            // free bank, preventing duplicate copies of one 256-bit line.
            // -------------------------------------------------------------
            if (wr_req_valid_i && wr_req_ready_o) begin
                // Any detector write separates two frozen-snapshot sessions.
                // This guarantees that the next 0x3200_0000 crop begins with
                // a compulsory cache miss even if no detector read occurred.
                if (wr_req_addr_ok_c)
                    snapshot_session_r <= 1'b0;

                if (!wr_req_addr_ok_c) begin
                    // Firewall drop, intentionally acknowledged.
                    wr_idle_count_r <= 10'd0;
                end else if (wr_match0_c) begin
                    wr0_be_r   <= wr0_be_r | wr_req_lane_be_c;
                    wr0_data_r <= merge_lane64(wr0_data_r, wr_req_lane_c,
                                               wr_req_data_i);
                    wr_idle_count_r <= 10'd0;

                    if (rd_tag0_valid_r &&
                        (rd_tag0_base_r == wr_req_addr_i[31:8]))
                        rd_tag0_valid_r <= 1'b0;
                    if (rd_tag1_valid_r &&
                        (rd_tag1_base_r == wr_req_addr_i[31:8]))
                        rd_tag1_valid_r <= 1'b0;
                end else if (wr_match1_c) begin
                    wr1_be_r   <= wr1_be_r | wr_req_lane_be_c;
                    wr1_data_r <= merge_lane64(wr1_data_r, wr_req_lane_c,
                                               wr_req_data_i);
                    wr_idle_count_r <= 10'd0;

                    if (rd_tag0_valid_r &&
                        (rd_tag0_base_r == wr_req_addr_i[31:8]))
                        rd_tag0_valid_r <= 1'b0;
                    if (rd_tag1_valid_r &&
                        (rd_tag1_base_r == wr_req_addr_i[31:8]))
                        rd_tag1_valid_r <= 1'b0;
                end else if (!wr0_valid_r && !wr0_locked_c) begin
                    wr0_valid_r <= 1'b1;
                    wr0_base_r  <= wr_req_base_c;
                    wr0_be_r    <= wr_req_lane_be_c;
                    wr0_data_r  <= merge_lane64(256'd0, wr_req_lane_c,
                                                wr_req_data_i);
                    wr_idle_count_r <= 10'd0;

                    if (rd_tag0_valid_r &&
                        (rd_tag0_base_r == wr_req_addr_i[31:8]))
                        rd_tag0_valid_r <= 1'b0;
                    if (rd_tag1_valid_r &&
                        (rd_tag1_base_r == wr_req_addr_i[31:8]))
                        rd_tag1_valid_r <= 1'b0;
                end else begin
                    // READY guarantees that buffer 1 is available here.
                    wr1_valid_r <= 1'b1;
                    wr1_base_r  <= wr_req_base_c;
                    wr1_be_r    <= wr_req_lane_be_c;
                    wr1_data_r  <= merge_lane64(256'd0, wr_req_lane_c,
                                                wr_req_data_i);
                    wr_idle_count_r <= 10'd0;

                    if (rd_tag0_valid_r &&
                        (rd_tag0_base_r == wr_req_addr_i[31:8]))
                        rd_tag0_valid_r <= 1'b0;
                    if (rd_tag1_valid_r &&
                        (rd_tag1_base_r == wr_req_addr_i[31:8]))
                        rd_tag1_valid_r <= 1'b0;
                end
            end else if (any_dirty_c && !rd_req_valid_i) begin
                if (wr_idle_count_r == WR_IDLE_FLUSH_CYCLES-1)
                    wr_idle_count_r <= wr_idle_count_r;
                else
                    wr_idle_count_r <= wr_idle_count_r + 1'b1;
            end else if (!any_dirty_c) begin
                wr_idle_count_r <= 10'd0;
            end

            // -------------------------------------------------------------
            // Shared Avalon bus engine.
            // Priority when idle:
            //   1) drain writes before a requested read (coherency)
            //   2) demand read miss
            //   3) full/aged write buffer
            //   4) background sequential prefetch
            // -------------------------------------------------------------
            case (bus_state_r)
                B_IDLE: begin
                    // FIX3: at STOP, flush buffered writes before acknowledging
                    // idle, but never issue new speculative/demand reads.
                    if (quiesce_i) begin
                        prefetch_pending_r <= 1'b0;
                        demand_pending_r <= 1'b0;
                        rd_rsp_valid_r <= 1'b0;
                        rd_lookup_d1_r <= 1'b0;
                        rd_lookup_d2_r <= 1'b0;
                        if (any_dirty_c) begin
                            bus_wr_bank_r <= wr0_valid_r ? 1'b0 : 1'b1;
                            bus_state_r <= B_WR_ISSUE;
                        end
                    end else if (any_dirty_c && rd_req_valid_i) begin
                        if (wr0_valid_r) bus_wr_bank_r <= 1'b0;
                        else             bus_wr_bank_r <= 1'b1;
                        bus_state_r <= B_WR_ISSUE;
                    end else if (demand_pending_r) begin
                        bus_rd_prefetch_r  <= 1'b0;
                        bus_rd_uncached_r  <= demand_uncached_r;
                        bus_rd_addr_r      <= demand_addr_r;
                        bus_rd_fill_bank_r <= demand_fill_bank_r;
                        bus_rd_recv_count_r <= 4'd0;
                        if (!demand_uncached_r) begin
                            if (!demand_fill_bank_r)
                                rd_tag0_valid_r <= 1'b0;
                            else
                                rd_tag1_valid_r <= 1'b0;
                        end
                        bus_state_r <= B_RD_ISSUE;
                    end else if (wr0_full_c || wr1_full_c || wr_need_space_c ||
                                 (any_dirty_c &&
                                  (wr_idle_count_r == WR_IDLE_FLUSH_CYCLES-1))) begin
                        if (wr0_full_c)      bus_wr_bank_r <= 1'b0;
                        else if (wr1_full_c) bus_wr_bank_r <= 1'b1;
                        else if (wr0_valid_r) bus_wr_bank_r <= 1'b0;
                        else                 bus_wr_bank_r <= 1'b1;
                        bus_state_r <= B_WR_ISSUE;
                    end else if (prefetch_pending_r && !any_dirty_c &&
                                 !rd_req_valid_i) begin
                        // Re-check the tag immediately before launch in case a
                        // demand fill already brought this line on-chip.
                        if ((rd_tag0_valid_r &&
                             (rd_tag0_base_r == prefetch_line_r)) ||
                            (rd_tag1_valid_r &&
                             (rd_tag1_base_r == prefetch_line_r))) begin
                            prefetch_pending_r <= 1'b0;
                        end else begin
                            bus_rd_prefetch_r  <= 1'b1;
                            bus_rd_uncached_r  <= 1'b0;
                            bus_rd_addr_r      <= {prefetch_line_r,8'h00};
                            bus_rd_fill_bank_r <= prefetch_fill_bank_r;
                            bus_rd_recv_count_r <= 4'd0;
                            if (!prefetch_fill_bank_r)
                                rd_tag0_valid_r <= 1'b0;
                            else
                                rd_tag1_valid_r <= 1'b0;
                            prefetch_pending_r <= 1'b0;
                            bus_state_r <= B_RD_ISSUE;
                        end
                    end
                end

                B_RD_ISSUE: begin
                    if (!avm_waitrequest_i) begin
                        bus_rd_recv_count_r <= 4'd0;
                        bus_state_r <= B_RD_WAIT;
                    end
                end

                B_RD_WAIT: begin
                    if (avm_readdatavalid_q) begin
                        if (bus_rd_uncached_r) begin
                            // Uncached transactions are always one beat.
                            rd_rsp_data_r <= select_lane64(avm_readdata_q,
                                                          bus_rd_addr_r[4:3]);
                            rd_rsp_valid_r <= 1'b1;
                            demand_pending_r <= 1'b0;
                            bus_state_r <= B_IDLE;
                        end else if (bus_rd_recv_count_r == RD_BURST_BEATS-1) begin
                            if (!bus_rd_fill_bank_r) begin
                                rd_tag0_base_r  <= bus_rd_addr_r[31:8];
                                rd_tag0_valid_r <= 1'b1;
                            end else begin
                                rd_tag1_base_r  <= bus_rd_addr_r[31:8];
                                rd_tag1_valid_r <= 1'b1;
                            end

                            if (!bus_rd_prefetch_r) begin
                                // Demand line is complete.  Start the local RAM
                                // read pipeline for the originally requested word.
                                rd_ram_rd_addr_r <= {bus_rd_fill_bank_r,
                                                     demand_addr_r[7:5]};
                                rd_lookup_lane_d1_r <= demand_addr_r[4:3];
                                rd_lookup_d1_r <= 1'b1;
                                rd_last_bank_r <= bus_rd_fill_bank_r;
                                demand_pending_r <= 1'b0;

                                if (demand_addr_r[7] &&
                                    (demand_addr_r[31:8] < AI_DDR_END[31:8]-1'b1)) begin
                                    prefetch_pending_r <= 1'b1;
                                    prefetch_line_r <= demand_addr_r[31:8] + 1'b1;
                                    prefetch_fill_bank_r <= ~bus_rd_fill_bank_r;
                                end
                            end

                            bus_rd_recv_count_r <= 4'd0;
                            bus_state_r <= B_IDLE;
                        end else begin
                            bus_rd_recv_count_r <= bus_rd_recv_count_r + 1'b1;
                        end
                    end
                end

                B_WR_ISSUE: begin
                    if (!avm_waitrequest_i) begin
                        if (!bus_wr_bank_r) begin
                            wr0_valid_r <= 1'b0;
                            wr0_be_r    <= 32'd0;
                            wr0_data_r  <= 256'd0;
                        end else begin
                            wr1_valid_r <= 1'b0;
                            wr1_be_r    <= 32'd0;
                            wr1_data_r  <= 256'd0;
                        end
                        wr_idle_count_r <= 10'd0;
                        bus_state_r <= B_IDLE;
                    end
                end

                default: bus_state_r <= B_IDLE;
            endcase
        end
    end

endmodule
