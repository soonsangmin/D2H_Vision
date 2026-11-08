package handseg_config_pkg;

    localparam integer HANDSEG_LAYER_COUNT = 65;
    localparam integer HANDSEG_RESIDUAL_COUNT = 10;
    localparam integer HANDSEG_CONCAT_COUNT = 3;

    localparam logic [1:0] LAYER_STANDARD = 2'd0;
    localparam logic [1:0] LAYER_POINTWISE = 2'd1;
    localparam logic [1:0] LAYER_DEPTHWISE = 2'd2;
    localparam logic [1:0] LAYER_FC = 2'd3;

    localparam logic [2:0] BANK_A      = 3'd0;
    localparam logic [2:0] BANK_B      = 3'd1;
    localparam logic [2:0] BANK_TEMP   = 3'd2;
    localparam logic [2:0] BANK_SKIP80 = 3'd3;
    localparam logic [2:0] BANK_SKIP40 = 3'd4;
    localparam logic [2:0] BANK_SKIP20 = 3'd5;
    localparam logic [2:0] BANK_AUX    = 3'd6;
    localparam logic [2:0] BANK_MASK   = 3'd7;

    typedef struct packed {
        logic [1:0]  kind;
        logic [9:0]  cin;
        logic [9:0]  cout;
        logic [8:0]  hin;
        logic [8:0]  win;
        logic [8:0]  hout;
        logic [8:0]  wout;
        logic [1:0]  kernel_h;
        logic [1:0]  kernel_w;
        logic [1:0]  stride;
        logic [1:0]  padding;
        logic [5:0]  in_groups8;
        logic [5:0]  out_groups8;
        logic [9:0]  mac_steps;
        logic [16:0] weight_base;
        logic [10:0] qparam_base;
        logic [7:0]  input_zero_point;
        logic [7:0]  output_zero_point;
        logic [7:0]  last_group_lane_mask;
    } layer_cfg_t;

    typedef struct packed {
        logic [31:0] main_multiplier;
        logic [31:0] shortcut_multiplier;
        logic [7:0]  main_zero_point;
        logic [7:0]  shortcut_zero_point;
        logic [7:0]  output_zero_point;
        logic [7:0]  shared_right_shift;
    } residual_cfg_t;

    typedef struct packed {
        logic [8:0] out_width;
        logic [8:0] out_height;
        logic [5:0] feature_groups;
        logic [5:0] skip_groups;
        logic [31:0] feature_multiplier;
        logic [7:0] feature_shift;
        logic [7:0] feature_zero_point;
        logic [31:0] skip_multiplier;
        logic [7:0] skip_shift;
        logic [7:0] skip_zero_point;
        logic [7:0] concat_zero_point;
    } concat_cfg_t;

    localparam logic [3:0] CMD_CONV     = 4'd0;
    localparam logic [3:0] CMD_RESIDUAL = 4'd1;
    localparam logic [3:0] CMD_CONCAT   = 4'd2;
    localparam logic [3:0] CMD_GAP      = 4'd3;
    localparam logic [3:0] CMD_PRESENCE = 4'd4;
    localparam logic [3:0] CMD_ROI      = 4'd5;
    localparam logic [3:0] CMD_DONE     = 4'd15;

    typedef struct packed {
        logic [3:0]  op;
        logic [6:0]  id;
        logic [2:0]  src0_bank;
        logic [2:0]  src1_bank;
        logic [2:0]  dst_bank;
        logic [16:0] word_count;
    } network_cmd_t;

endpackage
