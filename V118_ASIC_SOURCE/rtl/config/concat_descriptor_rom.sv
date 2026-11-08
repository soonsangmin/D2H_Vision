module concat_descriptor_rom (
    input  logic [1:0] concat_id_i,
    output handseg_config_pkg::concat_cfg_t cfg_o
);

    import handseg_config_pkg::*;

    always_comb begin
        cfg_o = '0;
        case (concat_id_i)
            2'd0: begin
                cfg_o.out_width = 9'd20;
                cfg_o.out_height = 9'd16;
                cfg_o.feature_groups = 6'd8;
                cfg_o.skip_groups = 6'd1;
                cfg_o.feature_multiplier = 32'd2123261521;
                cfg_o.feature_shift = 8'd31;
                cfg_o.feature_zero_point = 8'd0;
                cfg_o.skip_multiplier = 32'd1073741824;
                cfg_o.skip_shift = 8'd30;
                cfg_o.skip_zero_point = 8'd0;
                cfg_o.concat_zero_point = 8'd0;
            end
            2'd1: begin
                cfg_o.out_width = 9'd40;
                cfg_o.out_height = 9'd32;
                cfg_o.feature_groups = 6'd8;
                cfg_o.skip_groups = 6'd1;
                cfg_o.feature_multiplier = 32'd1073741824;
                cfg_o.feature_shift = 8'd30;
                cfg_o.feature_zero_point = 8'd0;
                cfg_o.skip_multiplier = 32'd1073741824;
                cfg_o.skip_shift = 8'd30;
                cfg_o.skip_zero_point = 8'd0;
                cfg_o.concat_zero_point = 8'd0;
            end
            2'd2: begin
                cfg_o.out_width = 9'd80;
                cfg_o.out_height = 9'd64;
                cfg_o.feature_groups = 6'd8;
                cfg_o.skip_groups = 6'd1;
                cfg_o.feature_multiplier = 32'd1073741824;
                cfg_o.feature_shift = 8'd30;
                cfg_o.feature_zero_point = 8'd0;
                cfg_o.skip_multiplier = 32'd2141734929;
                cfg_o.skip_shift = 8'd31;
                cfg_o.skip_zero_point = 8'd0;
                cfg_o.concat_zero_point = 8'd0;
            end
            default: cfg_o = '0;
        endcase
    end

endmodule
