module layer_descriptor_rom (
    input  logic [6:0] layer_id_i,
    output handseg_config_pkg::layer_cfg_t cfg_o
);

    import handseg_config_pkg::*;

    always_comb begin
        cfg_o = '0;
        case (layer_id_i)
            7'd0: begin
                cfg_o.kind = LAYER_STANDARD;
                cfg_o.cin = 10'd3;
                cfg_o.cout = 10'd24;
                cfg_o.hin = 9'd256;
                cfg_o.win = 9'd320;
                cfg_o.hout = 9'd128;
                cfg_o.wout = 9'd160;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd2;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd1;
                cfg_o.out_groups8 = 6'd3;
                cfg_o.mac_steps = 10'd27;
                cfg_o.weight_base = 17'd0;
                cfg_o.qparam_base = 11'd0;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd1: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd24;
                cfg_o.cout = 10'd48;
                cfg_o.hin = 9'd128;
                cfg_o.win = 9'd160;
                cfg_o.hout = 9'd128;
                cfg_o.wout = 9'd160;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd3;
                cfg_o.out_groups8 = 6'd6;
                cfg_o.mac_steps = 10'd24;
                cfg_o.weight_base = 17'd81;
                cfg_o.qparam_base = 11'd3;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd2: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd48;
                cfg_o.hin = 9'd128;
                cfg_o.win = 9'd160;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd2;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd6;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd225;
                cfg_o.qparam_base = 11'd9;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd3: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd32;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd4;
                cfg_o.mac_steps = 10'd48;
                cfg_o.weight_base = 17'd279;
                cfg_o.qparam_base = 11'd15;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd131;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd4: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd32;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd4;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd32;
                cfg_o.weight_base = 17'd471;
                cfg_o.qparam_base = 11'd19;
                cfg_o.input_zero_point = 8'd131;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd5: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd727;
                cfg_o.qparam_base = 11'd27;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd6: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd32;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd4;
                cfg_o.mac_steps = 10'd64;
                cfg_o.weight_base = 17'd799;
                cfg_o.qparam_base = 11'd35;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd132;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd7: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd32;
                cfg_o.cout = 10'd96;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd4;
                cfg_o.out_groups8 = 6'd12;
                cfg_o.mac_steps = 10'd32;
                cfg_o.weight_base = 17'd1055;
                cfg_o.qparam_base = 11'd39;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd8: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd96;
                cfg_o.cout = 10'd96;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd2;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd12;
                cfg_o.out_groups8 = 6'd12;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd1439;
                cfg_o.qparam_base = 11'd51;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd9: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd96;
                cfg_o.cout = 10'd48;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd12;
                cfg_o.out_groups8 = 6'd6;
                cfg_o.mac_steps = 10'd96;
                cfg_o.weight_base = 17'd1547;
                cfg_o.qparam_base = 11'd63;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd135;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd10: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd48;
                cfg_o.weight_base = 17'd2123;
                cfg_o.qparam_base = 11'd69;
                cfg_o.input_zero_point = 8'd135;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd11: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd2987;
                cfg_o.qparam_base = 11'd87;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd12: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd48;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd6;
                cfg_o.mac_steps = 10'd144;
                cfg_o.weight_base = 17'd3149;
                cfg_o.qparam_base = 11'd105;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd128;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd13: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd48;
                cfg_o.weight_base = 17'd4013;
                cfg_o.qparam_base = 11'd111;
                cfg_o.input_zero_point = 8'd122;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd14: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd4877;
                cfg_o.qparam_base = 11'd129;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd15: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd48;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd6;
                cfg_o.mac_steps = 10'd144;
                cfg_o.weight_base = 17'd5039;
                cfg_o.qparam_base = 11'd147;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd126;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd16: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd48;
                cfg_o.weight_base = 17'd5903;
                cfg_o.qparam_base = 11'd153;
                cfg_o.input_zero_point = 8'd120;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd17: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd144;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd2;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd18;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd6767;
                cfg_o.qparam_base = 11'd171;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd18: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd144;
                cfg_o.cout = 10'd80;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd18;
                cfg_o.out_groups8 = 6'd10;
                cfg_o.mac_steps = 10'd144;
                cfg_o.weight_base = 17'd6929;
                cfg_o.qparam_base = 11'd189;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd19: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd80;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd10;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd80;
                cfg_o.weight_base = 17'd8369;
                cfg_o.qparam_base = 11'd199;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd20: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd10769;
                cfg_o.qparam_base = 11'd229;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd21: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd80;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd10;
                cfg_o.mac_steps = 10'd240;
                cfg_o.weight_base = 17'd11039;
                cfg_o.qparam_base = 11'd259;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd133;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd22: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd80;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd10;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd80;
                cfg_o.weight_base = 17'd13439;
                cfg_o.qparam_base = 11'd269;
                cfg_o.input_zero_point = 8'd128;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd23: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd15839;
                cfg_o.qparam_base = 11'd299;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd24: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd80;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd10;
                cfg_o.mac_steps = 10'd240;
                cfg_o.weight_base = 17'd16109;
                cfg_o.qparam_base = 11'd329;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd25: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd80;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd10;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd80;
                cfg_o.weight_base = 17'd18509;
                cfg_o.qparam_base = 11'd339;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd26: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd240;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd2;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd30;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd20909;
                cfg_o.qparam_base = 11'd369;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd27: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd240;
                cfg_o.cout = 10'd128;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd30;
                cfg_o.out_groups8 = 6'd16;
                cfg_o.mac_steps = 10'd240;
                cfg_o.weight_base = 17'd21179;
                cfg_o.qparam_base = 11'd399;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd28: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd128;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd16;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd128;
                cfg_o.weight_base = 17'd25019;
                cfg_o.qparam_base = 11'd415;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd29: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd31163;
                cfg_o.qparam_base = 11'd463;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd30: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd128;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd16;
                cfg_o.mac_steps = 10'd384;
                cfg_o.weight_base = 17'd31595;
                cfg_o.qparam_base = 11'd511;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd130;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd31: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd128;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd16;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd128;
                cfg_o.weight_base = 17'd37739;
                cfg_o.qparam_base = 11'd527;
                cfg_o.input_zero_point = 8'd127;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd32: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd43883;
                cfg_o.qparam_base = 11'd575;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd33: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd128;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd16;
                cfg_o.mac_steps = 10'd384;
                cfg_o.weight_base = 17'd44315;
                cfg_o.qparam_base = 11'd623;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd126;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd34: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd128;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd16;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd128;
                cfg_o.weight_base = 17'd50459;
                cfg_o.qparam_base = 11'd639;
                cfg_o.input_zero_point = 8'd127;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd35: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd56603;
                cfg_o.qparam_base = 11'd687;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd36: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd128;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd16;
                cfg_o.mac_steps = 10'd384;
                cfg_o.weight_base = 17'd57035;
                cfg_o.qparam_base = 11'd735;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd37: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd128;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd16;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd128;
                cfg_o.weight_base = 17'd63179;
                cfg_o.qparam_base = 11'd751;
                cfg_o.input_zero_point = 8'd128;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd38: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd384;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd48;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd69323;
                cfg_o.qparam_base = 11'd799;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd39: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd384;
                cfg_o.cout = 10'd160;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd48;
                cfg_o.out_groups8 = 6'd20;
                cfg_o.mac_steps = 10'd384;
                cfg_o.weight_base = 17'd69755;
                cfg_o.qparam_base = 11'd847;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd129;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd40: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd160;
                cfg_o.cout = 10'd480;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd20;
                cfg_o.out_groups8 = 6'd60;
                cfg_o.mac_steps = 10'd160;
                cfg_o.weight_base = 17'd77435;
                cfg_o.qparam_base = 11'd867;
                cfg_o.input_zero_point = 8'd129;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd41: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd480;
                cfg_o.cout = 10'd480;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd60;
                cfg_o.out_groups8 = 6'd60;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd87035;
                cfg_o.qparam_base = 11'd927;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd42: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd480;
                cfg_o.cout = 10'd160;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd60;
                cfg_o.out_groups8 = 6'd20;
                cfg_o.mac_steps = 10'd480;
                cfg_o.weight_base = 17'd87575;
                cfg_o.qparam_base = 11'd987;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd43: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd160;
                cfg_o.cout = 10'd480;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd20;
                cfg_o.out_groups8 = 6'd60;
                cfg_o.mac_steps = 10'd160;
                cfg_o.weight_base = 17'd97175;
                cfg_o.qparam_base = 11'd1007;
                cfg_o.input_zero_point = 8'd131;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd44: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd480;
                cfg_o.cout = 10'd480;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd60;
                cfg_o.out_groups8 = 6'd60;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd106775;
                cfg_o.qparam_base = 11'd1067;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd45: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd480;
                cfg_o.cout = 10'd160;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd60;
                cfg_o.out_groups8 = 6'd20;
                cfg_o.mac_steps = 10'd480;
                cfg_o.weight_base = 17'd107315;
                cfg_o.qparam_base = 11'd1127;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd136;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd46: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd32;
                cfg_o.cout = 10'd8;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd4;
                cfg_o.out_groups8 = 6'd1;
                cfg_o.mac_steps = 10'd32;
                cfg_o.weight_base = 17'd116915;
                cfg_o.qparam_base = 11'd1147;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd47: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd48;
                cfg_o.cout = 10'd8;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd6;
                cfg_o.out_groups8 = 6'd1;
                cfg_o.mac_steps = 10'd48;
                cfg_o.weight_base = 17'd116947;
                cfg_o.qparam_base = 11'd1148;
                cfg_o.input_zero_point = 8'd120;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd48: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd80;
                cfg_o.cout = 10'd8;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd10;
                cfg_o.out_groups8 = 6'd1;
                cfg_o.mac_steps = 10'd80;
                cfg_o.weight_base = 17'd116995;
                cfg_o.qparam_base = 11'd1149;
                cfg_o.input_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd49: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd160;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd8;
                cfg_o.win = 9'd10;
                cfg_o.hout = 9'd8;
                cfg_o.wout = 9'd10;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd20;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd160;
                cfg_o.weight_base = 17'd117075;
                cfg_o.qparam_base = 11'd1150;
                cfg_o.input_zero_point = 8'd133;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd50: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd72;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd9;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd118355;
                cfg_o.qparam_base = 11'd1158;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd51: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd72;
                cfg_o.weight_base = 17'd118436;
                cfg_o.qparam_base = 11'd1167;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd52: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd119012;
                cfg_o.qparam_base = 11'd1175;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd53: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd16;
                cfg_o.win = 9'd20;
                cfg_o.hout = 9'd16;
                cfg_o.wout = 9'd20;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd64;
                cfg_o.weight_base = 17'd119084;
                cfg_o.qparam_base = 11'd1183;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd54: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd72;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd9;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd119596;
                cfg_o.qparam_base = 11'd1191;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd55: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd72;
                cfg_o.weight_base = 17'd119677;
                cfg_o.qparam_base = 11'd1200;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd56: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd120253;
                cfg_o.qparam_base = 11'd1208;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd57: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd32;
                cfg_o.win = 9'd40;
                cfg_o.hout = 9'd32;
                cfg_o.wout = 9'd40;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd64;
                cfg_o.weight_base = 17'd120325;
                cfg_o.qparam_base = 11'd1216;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd58: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd72;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd9;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd120837;
                cfg_o.qparam_base = 11'd1224;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd59: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd72;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd9;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd72;
                cfg_o.weight_base = 17'd120918;
                cfg_o.qparam_base = 11'd1233;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd60: begin
                cfg_o.kind = LAYER_DEPTHWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd3;
                cfg_o.kernel_w = 2'd3;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd1;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd9;
                cfg_o.weight_base = 17'd121494;
                cfg_o.qparam_base = 11'd1241;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd61: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd64;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd8;
                cfg_o.mac_steps = 10'd64;
                cfg_o.weight_base = 17'd121566;
                cfg_o.qparam_base = 11'd1249;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd62: begin
                cfg_o.kind = LAYER_POINTWISE;
                cfg_o.cin = 10'd64;
                cfg_o.cout = 10'd1;
                cfg_o.hin = 9'd64;
                cfg_o.win = 9'd80;
                cfg_o.hout = 9'd64;
                cfg_o.wout = 9'd80;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd8;
                cfg_o.out_groups8 = 6'd1;
                cfg_o.mac_steps = 10'd64;
                cfg_o.weight_base = 17'd122078;
                cfg_o.qparam_base = 11'd1257;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd122;
                cfg_o.last_group_lane_mask = 8'h01;
            end
            7'd63: begin
                cfg_o.kind = LAYER_FC;
                cfg_o.cin = 10'd160;
                cfg_o.cout = 10'd16;
                cfg_o.hin = 9'd1;
                cfg_o.win = 9'd1;
                cfg_o.hout = 9'd1;
                cfg_o.wout = 9'd1;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd20;
                cfg_o.out_groups8 = 6'd2;
                cfg_o.mac_steps = 10'd160;
                cfg_o.weight_base = 17'd122142;
                cfg_o.qparam_base = 11'd1258;
                cfg_o.input_zero_point = 8'd128;
                cfg_o.output_zero_point = 8'd0;
                cfg_o.last_group_lane_mask = 8'hFF;
            end
            7'd64: begin
                cfg_o.kind = LAYER_FC;
                cfg_o.cin = 10'd16;
                cfg_o.cout = 10'd1;
                cfg_o.hin = 9'd1;
                cfg_o.win = 9'd1;
                cfg_o.hout = 9'd1;
                cfg_o.wout = 9'd1;
                cfg_o.kernel_h = 2'd1;
                cfg_o.kernel_w = 2'd1;
                cfg_o.stride = 2'd1;
                cfg_o.padding = 2'd0;
                cfg_o.in_groups8 = 6'd2;
                cfg_o.out_groups8 = 6'd1;
                cfg_o.mac_steps = 10'd16;
                cfg_o.weight_base = 17'd122462;
                cfg_o.qparam_base = 11'd1260;
                cfg_o.input_zero_point = 8'd0;
                cfg_o.output_zero_point = 8'd71;
                cfg_o.last_group_lane_mask = 8'h01;
            end
            default: cfg_o = '0;
        endcase
    end

endmodule
