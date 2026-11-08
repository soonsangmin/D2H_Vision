module residual_descriptor_rom (
    input  logic [3:0] residual_id_i,
    output handseg_config_pkg::residual_cfg_t cfg_o
);

    import handseg_config_pkg::*;

    always_comb begin
        cfg_o = '0;
        case (residual_id_i)
            4'd0: begin
                cfg_o.main_multiplier = 32'd1491341889;
                cfg_o.shortcut_multiplier = 32'd1632895003;
                cfg_o.main_zero_point = 8'd132;
                cfg_o.shortcut_zero_point = 8'd131;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd1: begin
                cfg_o.main_multiplier = 32'd1380389161;
                cfg_o.shortcut_multiplier = 32'd1641085558;
                cfg_o.main_zero_point = 8'd128;
                cfg_o.shortcut_zero_point = 8'd135;
                cfg_o.output_zero_point = 8'd122;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd2: begin
                cfg_o.main_multiplier = 32'd1193395047;
                cfg_o.shortcut_multiplier = 32'd1544416180;
                cfg_o.main_zero_point = 8'd126;
                cfg_o.shortcut_zero_point = 8'd122;
                cfg_o.output_zero_point = 8'd120;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd3: begin
                cfg_o.main_multiplier = 32'd1409862850;
                cfg_o.shortcut_multiplier = 32'd1483863536;
                cfg_o.main_zero_point = 8'd133;
                cfg_o.shortcut_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd128;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd4: begin
                cfg_o.main_multiplier = 32'd1238102639;
                cfg_o.shortcut_multiplier = 32'd1587754134;
                cfg_o.main_zero_point = 8'd125;
                cfg_o.shortcut_zero_point = 8'd128;
                cfg_o.output_zero_point = 8'd125;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd5: begin
                cfg_o.main_multiplier = 32'd1535614194;
                cfg_o.shortcut_multiplier = 32'd1570138290;
                cfg_o.main_zero_point = 8'd130;
                cfg_o.shortcut_zero_point = 8'd125;
                cfg_o.output_zero_point = 8'd127;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd6: begin
                cfg_o.main_multiplier = 32'd1170813990;
                cfg_o.shortcut_multiplier = 32'd1647925109;
                cfg_o.main_zero_point = 8'd126;
                cfg_o.shortcut_zero_point = 8'd127;
                cfg_o.output_zero_point = 8'd127;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd7: begin
                cfg_o.main_multiplier = 32'd987382269;
                cfg_o.shortcut_multiplier = 32'd1783334074;
                cfg_o.main_zero_point = 8'd125;
                cfg_o.shortcut_zero_point = 8'd127;
                cfg_o.output_zero_point = 8'd128;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd8: begin
                cfg_o.main_multiplier = 32'd1528413564;
                cfg_o.shortcut_multiplier = 32'd1523092289;
                cfg_o.main_zero_point = 8'd125;
                cfg_o.shortcut_zero_point = 8'd129;
                cfg_o.output_zero_point = 8'd131;
                cfg_o.shared_right_shift = 8'd31;
            end
            4'd9: begin
                cfg_o.main_multiplier = 32'd1363567316;
                cfg_o.shortcut_multiplier = 32'd1668432068;
                cfg_o.main_zero_point = 8'd136;
                cfg_o.shortcut_zero_point = 8'd131;
                cfg_o.output_zero_point = 8'd133;
                cfg_o.shared_right_shift = 8'd31;
            end
            default: cfg_o = '0;
        endcase
    end

endmodule
