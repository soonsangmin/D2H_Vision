module parameter_store_v141 #(
    parameter WEIGHT_FILE = "params/weights_packed64.hex",
    parameter MULT_FILE   = "params/multiplier_group256.hex",
    parameter BIAS_FILE   = "params/bias_group512.hex",
    parameter SHIFT_FILE  = "params/shift_group64.hex",
    parameter ZP_FILE     = "params/zero_point_group64.hex",
    parameter RELU_FILE   = "params/relu_mask_group8.hex"
)(
    input  logic clk_i,
    input  logic rstn_i,

    input  logic        weight_req_valid_i,
    output logic        weight_req_ready_o,
    input  logic [16:0] weight_req_addr_i,
    output logic        weight_rsp_valid_o,
    input  logic        weight_rsp_ready_i,
    output logic [63:0] weight_rsp_data_o,

    input  logic        qparam_req_valid_i,
    output logic        qparam_req_ready_o,
    input  logic [10:0] qparam_req_addr_i,
    output logic        qparam_rsp_valid_o,
    input  logic        qparam_rsp_ready_i,
    output logic [255:0] multiplier_vec_o,
    output logic [511:0] bias_postscale_vec_o,
    output logic [63:0]  right_shift_vec_o,
    output logic [63:0]  zero_point_vec_o,
    output logic [7:0]   relu_en_vec_o
);
    localparam integer WEIGHT_WORDS = 122478;
    localparam integer QPARAM_GROUPS = 1261;

    logic [63:0]  weight_mem [0:WEIGHT_WORDS-1];
    logic [255:0] mult_mem   [0:QPARAM_GROUPS-1];
    logic [511:0] bias_mem   [0:QPARAM_GROUPS-1];
    logic [63:0]  shift_mem  [0:QPARAM_GROUPS-1];
    logic [63:0]  zp_mem     [0:QPARAM_GROUPS-1];
    logic [7:0]   relu_mem   [0:QPARAM_GROUPS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weight_mem);
        $readmemh(MULT_FILE,   mult_mem);
        $readmemh(BIAS_FILE,   bias_mem);
        $readmemh(SHIFT_FILE,  shift_mem);
        $readmemh(ZP_FILE,     zp_mem);
        $readmemh(RELU_FILE,   relu_mem);
    end

    logic weight_valid_r, qparam_valid_r;
    assign weight_rsp_valid_o = weight_valid_r;
    assign qparam_rsp_valid_o = qparam_valid_r;
    assign weight_req_ready_o = ~weight_valid_r | weight_rsp_ready_i;
    assign qparam_req_ready_o = ~qparam_valid_r | qparam_rsp_ready_i;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            weight_valid_r <= 1'b0;
            qparam_valid_r <= 1'b0;
        end else begin
            if (weight_req_ready_o) begin
                weight_valid_r <= weight_req_valid_i;
                if (weight_req_valid_i)
                    weight_rsp_data_o <= weight_mem[weight_req_addr_i];
            end
            if (qparam_req_ready_o) begin
                qparam_valid_r <= qparam_req_valid_i;
                if (qparam_req_valid_i) begin
                    multiplier_vec_o    <= mult_mem[qparam_req_addr_i];
                    bias_postscale_vec_o <= bias_mem[qparam_req_addr_i];
                    right_shift_vec_o    <= shift_mem[qparam_req_addr_i];
                    zero_point_vec_o     <= zp_mem[qparam_req_addr_i];
                    relu_en_vec_o        <= relu_mem[qparam_req_addr_i];
                end
            end
        end
    end
endmodule
