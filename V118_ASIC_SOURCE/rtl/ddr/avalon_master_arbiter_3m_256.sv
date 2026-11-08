module avalon_master_arbiter_3m_256 (
    input  logic         clk_i,
    input  logic         rstn_i,

    // Master 0: camera framebuffer writer (highest realtime priority).
    input  logic         m0_read_i,
    input  logic         m0_write_i,
    input  logic [255:0] m0_writedata_i,
    input  logic [31:0]  m0_address_i,
    input  logic [31:0]  m0_byteenable_i,
    input  logic [10:0]  m0_burstcount_i,
    output logic [255:0] m0_readdata_o,
    output logic         m0_readdatavalid_o,
    output logic         m0_waitrequest_o,

    // Master 1: HDMI framebuffer reader (second realtime priority).
    input  logic         m1_read_i,
    input  logic         m1_write_i,
    input  logic [255:0] m1_writedata_i,
    input  logic [31:0]  m1_address_i,
    input  logic [31:0]  m1_byteenable_i,
    input  logic [10:0]  m1_burstcount_i,
    output logic [255:0] m1_readdata_o,
    output logic         m1_readdatavalid_o,
    output logic         m1_waitrequest_o,

    // Master 2: HandSeg AI background traffic.
    input  logic         m2_read_i,
    input  logic         m2_write_i,
    input  logic [255:0] m2_writedata_i,
    input  logic [31:0]  m2_address_i,
    input  logic [31:0]  m2_byteenable_i,
    input  logic [10:0]  m2_burstcount_i,
    output logic [255:0] m2_readdata_o,
    output logic         m2_readdatavalid_o,
    output logic         m2_waitrequest_o,

    // Single Qsys/HPS SDRAM Avalon-MM master port.
    output logic         s_read_o,
    output logic         s_write_o,
    output logic [255:0] s_writedata_o,
    output logic [31:0]  s_address_o,
    output logic [31:0]  s_byteenable_o,
    output logic [10:0]  s_burstcount_o,
    input  logic [255:0] s_readdata_i,
    input  logic         s_readdatavalid_i,
    input  logic         s_waitrequest_i
);

    // V4.6.2 VIDEO-SAFE policy:
    //   camera writer > HDMI reader > AI
    //
    // The camera source cannot be backpressured and the HDMI sink cannot stop
    // consuming pixels, therefore both realtime paths must be admitted before
    // background AI traffic. Once a burst is accepted it is allowed to finish;
    // no Avalon transaction is cut mid-burst.

    typedef enum logic [1:0] {
        A_IDLE,
        A_READ_RSP,
        A_WRITE_BURST
    } astate_t;

    astate_t state_r;
    logic [1:0] owner_r;          // 0=camera write, 1=HDMI read, 2=AI
    logic [10:0] beats_left_r;

    logic have0_c, have1_c, have2_c;
    logic grant0_c, grant1_c, grant2_c;

    assign have0_c = m0_read_i | m0_write_i;
    assign have1_c = m1_read_i | m1_write_i;
    assign have2_c = m2_read_i | m2_write_i;

    assign grant0_c = have0_c;
    assign grant1_c = (~have0_c) & have1_c;
    assign grant2_c = (~have0_c) & (~have1_c) & have2_c;

    always_comb begin
        s_read_o       = 1'b0;
        s_write_o      = 1'b0;
        s_writedata_o  = 256'd0;
        s_address_o    = 32'd0;
        s_byteenable_o = 32'd0;
        s_burstcount_o = 11'd1;

        m0_readdata_o      = s_readdata_i;
        m1_readdata_o      = s_readdata_i;
        m2_readdata_o      = s_readdata_i;
        m0_readdatavalid_o = 1'b0;
        m1_readdatavalid_o = 1'b0;
        m2_readdatavalid_o = 1'b0;

        m0_waitrequest_o = 1'b1;
        m1_waitrequest_o = 1'b1;
        m2_waitrequest_o = 1'b1;

        case (state_r)
            A_IDLE: begin
                if (grant0_c) begin
                    s_read_o         = m0_read_i;
                    s_write_o        = m0_write_i;
                    s_writedata_o    = m0_writedata_i;
                    s_address_o      = m0_address_i;
                    s_byteenable_o   = m0_byteenable_i;
                    s_burstcount_o   = (m0_burstcount_i == 0) ? 11'd1
                                                             : m0_burstcount_i;
                    m0_waitrequest_o = s_waitrequest_i;
                end else if (grant1_c) begin
                    s_read_o         = m1_read_i;
                    s_write_o        = m1_write_i;
                    s_writedata_o    = m1_writedata_i;
                    s_address_o      = m1_address_i;
                    s_byteenable_o   = m1_byteenable_i;
                    s_burstcount_o   = (m1_burstcount_i == 0) ? 11'd1
                                                             : m1_burstcount_i;
                    m1_waitrequest_o = s_waitrequest_i;
                end else if (grant2_c) begin
                    s_read_o         = m2_read_i;
                    s_write_o        = m2_write_i;
                    s_writedata_o    = m2_writedata_i;
                    s_address_o      = m2_address_i;
                    s_byteenable_o   = m2_byteenable_i;
                    s_burstcount_o   = (m2_burstcount_i == 0) ? 11'd1
                                                             : m2_burstcount_i;
                    m2_waitrequest_o = s_waitrequest_i;
                end
            end

            A_READ_RSP: begin
                case (owner_r)
                    2'd0: begin
                        m0_readdatavalid_o = s_readdatavalid_i;
                        m0_readdata_o      = s_readdata_i;
                    end
                    2'd1: begin
                        m1_readdatavalid_o = s_readdatavalid_i;
                        m1_readdata_o      = s_readdata_i;
                    end
                    default: begin
                        m2_readdatavalid_o = s_readdatavalid_i;
                        m2_readdata_o      = s_readdata_i;
                    end
                endcase
            end

            A_WRITE_BURST: begin
                case (owner_r)
                    2'd0: begin
                        s_write_o         = m0_write_i;
                        s_writedata_o     = m0_writedata_i;
                        s_address_o       = m0_address_i;
                        s_byteenable_o    = m0_byteenable_i;
                        s_burstcount_o    = (m0_burstcount_i == 0) ? 11'd1
                                                                 : m0_burstcount_i;
                        m0_waitrequest_o  = s_waitrequest_i;
                    end
                    2'd1: begin
                        s_write_o         = m1_write_i;
                        s_writedata_o     = m1_writedata_i;
                        s_address_o       = m1_address_i;
                        s_byteenable_o    = m1_byteenable_i;
                        s_burstcount_o    = (m1_burstcount_i == 0) ? 11'd1
                                                                 : m1_burstcount_i;
                        m1_waitrequest_o  = s_waitrequest_i;
                    end
                    default: begin
                        s_write_o         = m2_write_i;
                        s_writedata_o     = m2_writedata_i;
                        s_address_o       = m2_address_i;
                        s_byteenable_o    = m2_byteenable_i;
                        s_burstcount_o    = (m2_burstcount_i == 0) ? 11'd1
                                                                 : m2_burstcount_i;
                        m2_waitrequest_o  = s_waitrequest_i;
                    end
                endcase
            end

            default: begin end
        endcase
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r      <= A_IDLE;
            owner_r      <= 2'd0;
            beats_left_r <= 11'd0;
        end else begin
            case (state_r)
                A_IDLE: begin
                    if ((grant0_c || grant1_c || grant2_c) &&
                        (s_read_o || s_write_o) && !s_waitrequest_i) begin

                        if (grant0_c)
                            owner_r <= 2'd0;
                        else if (grant1_c)
                            owner_r <= 2'd1;
                        else
                            owner_r <= 2'd2;

                        if (s_read_o) begin
                            beats_left_r <= s_burstcount_o;
                            state_r      <= A_READ_RSP;
                        end else if (s_burstcount_o > 1) begin
                            beats_left_r <= s_burstcount_o - 1'b1;
                            state_r      <= A_WRITE_BURST;
                        end else begin
                            beats_left_r <= 11'd0;
                            state_r      <= A_IDLE;
                        end
                    end
                end

                A_READ_RSP: begin
                    if (s_readdatavalid_i) begin
                        if (beats_left_r <= 1) begin
                            beats_left_r <= 11'd0;
                            state_r      <= A_IDLE;
                        end else begin
                            beats_left_r <= beats_left_r - 1'b1;
                        end
                    end
                end

                A_WRITE_BURST: begin
                    if (s_write_o && !s_waitrequest_i) begin
                        if (beats_left_r <= 1) begin
                            beats_left_r <= 11'd0;
                            state_r      <= A_IDLE;
                        end else begin
                            beats_left_r <= beats_left_r - 1'b1;
                        end
                    end
                end

                default: begin
                    state_r      <= A_IDLE;
                    owner_r      <= 2'd0;
                    beats_left_r <= 11'd0;
                end
            endcase
        end
    end

endmodule
