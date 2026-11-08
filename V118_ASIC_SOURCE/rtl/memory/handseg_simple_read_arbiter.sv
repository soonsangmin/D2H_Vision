module handseg_simple_read_arbiter (
    input  logic        clk_i,
    input  logic        rstn_i,

    input  logic        c0_req_valid_i,
    output logic        c0_req_ready_o,
    input  logic [31:0] c0_req_addr_i,
    output logic        c0_rsp_valid_o,
    input  logic        c0_rsp_ready_i,
    output logic [63:0] c0_rsp_data_o,

    input  logic        c1_req_valid_i,
    output logic        c1_req_ready_o,
    input  logic [31:0] c1_req_addr_i,
    output logic        c1_rsp_valid_o,
    input  logic        c1_rsp_ready_i,
    output logic [63:0] c1_rsp_data_o,

    output logic        m_req_valid_o,
    input  logic        m_req_ready_i,
    output logic [31:0] m_req_addr_o,
    input  logic        m_rsp_valid_i,
    output logic        m_rsp_ready_o,
    input  logic [63:0] m_rsp_data_i
);

    typedef enum logic {S_IDLE, S_WAIT} state_t;
    state_t state_r;
    logic owner_r;
    logic rr_r;
    logic choose1_c;

    always_comb begin
        if (c0_req_valid_i && c1_req_valid_i)
            choose1_c = rr_r;
        else
            choose1_c = c1_req_valid_i;

        m_req_valid_o = 1'b0;
        m_req_addr_o  = 32'd0;
        c0_req_ready_o = 1'b0;
        c1_req_ready_o = 1'b0;

        c0_rsp_valid_o = 1'b0;
        c1_rsp_valid_o = 1'b0;
        c0_rsp_data_o  = m_rsp_data_i;
        c1_rsp_data_o  = m_rsp_data_i;
        m_rsp_ready_o  = 1'b0;

        if (state_r == S_IDLE) begin
            if (c0_req_valid_i || c1_req_valid_i) begin
                m_req_valid_o = 1'b1;
                if (choose1_c) begin
                    m_req_addr_o   = c1_req_addr_i;
                    c1_req_ready_o = m_req_ready_i;
                end
                else begin
                    m_req_addr_o   = c0_req_addr_i;
                    c0_req_ready_o = m_req_ready_i;
                end
            end
        end
        else begin
            if (owner_r) begin
                c1_rsp_valid_o = m_rsp_valid_i;
                c1_rsp_data_o  = m_rsp_data_i;
                m_rsp_ready_o  = c1_rsp_ready_i;
            end
            else begin
                c0_rsp_valid_o = m_rsp_valid_i;
                c0_rsp_data_o  = m_rsp_data_i;
                m_rsp_ready_o  = c0_rsp_ready_i;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            state_r <= S_IDLE;
            owner_r <= 1'b0;
            rr_r    <= 1'b0;
        end
        else begin
            if (state_r == S_IDLE) begin
                if (m_req_valid_o && m_req_ready_i) begin
                    owner_r <= choose1_c;
                    state_r <= S_WAIT;
                end
            end
            else if (m_rsp_valid_i && m_rsp_ready_o) begin
                rr_r    <= ~owner_r;
                state_r <= S_IDLE;
            end
        end
    end

endmodule
