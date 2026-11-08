module network_schedule_rom (
    input  logic [6:0] pc_i,
    output handseg_config_pkg::network_cmd_t cmd_o
);

    import handseg_config_pkg::*;

    localparam integer COMMAND_COUNT = 82;

    always_comb begin
        cmd_o = '0;
        case (pc_i)
            7'd0: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd1: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd1;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd2: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd2;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd3: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd3;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd4: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd4;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd5: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd5;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd6: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd6;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd7: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd20480;
            end
            7'd8: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd46;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_SKIP80;
                cmd_o.word_count = 17'd0;
            end
            7'd9: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd7;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd10: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd8;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd11: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd9;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd12: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd10;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd13: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd11;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd14: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd12;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd15: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd1;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_B;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd7680;
            end
            7'd16: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd13;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd17: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd14;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd18: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd15;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd19: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd2;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_B;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd7680;
            end
            7'd20: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd47;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_SKIP40;
                cmd_o.word_count = 17'd0;
            end
            7'd21: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd16;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd22: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd17;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd23: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd18;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd24: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd19;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd25: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd20;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd26: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd21;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd27: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd3;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd3200;
            end
            7'd28: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd22;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd29: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd23;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd30: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd24;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd31: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd4;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd3200;
            end
            7'd32: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd48;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_SKIP20;
                cmd_o.word_count = 17'd0;
            end
            7'd33: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd25;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd34: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd26;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd35: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd27;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd36: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd28;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd37: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd29;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd38: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd30;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd39: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd5;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_B;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd1280;
            end
            7'd40: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd31;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd41: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd32;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd42: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd33;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd43: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd6;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_B;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd1280;
            end
            7'd44: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd34;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd45: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd35;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd46: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd36;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd47: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd7;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_B;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd1280;
            end
            7'd48: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd37;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd49: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd38;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd50: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd39;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            7'd51: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd40;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd52: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd41;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd53: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd42;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd54: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd8;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd1600;
            end
            7'd55: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd43;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd56: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd44;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd57: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd45;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd58: begin
                cmd_o.op = CMD_RESIDUAL;
                cmd_o.id = 7'd9;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd1600;
            end
            7'd59: begin
                cmd_o.op = CMD_GAP;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd60: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd63;
                cmd_o.src0_bank = BANK_AUX;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd61: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd64;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd62: begin
                cmd_o.op = CMD_PRESENCE;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_AUX;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd63: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd49;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd64: begin
                cmd_o.op = CMD_CONCAT;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_SKIP20;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd65: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd50;
                cmd_o.src0_bank = BANK_AUX;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd66: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd51;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd67: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd52;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd68: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd53;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd69: begin
                cmd_o.op = CMD_CONCAT;
                cmd_o.id = 7'd1;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_SKIP40;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd70: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd54;
                cmd_o.src0_bank = BANK_AUX;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd71: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd55;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd72: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd56;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd73: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd57;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd74: begin
                cmd_o.op = CMD_CONCAT;
                cmd_o.id = 7'd2;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_SKIP80;
                cmd_o.dst_bank = BANK_AUX;
                cmd_o.word_count = 17'd0;
            end
            7'd75: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd58;
                cmd_o.src0_bank = BANK_AUX;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd76: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd59;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd77: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd60;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_TEMP;
                cmd_o.word_count = 17'd0;
            end
            7'd78: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd61;
                cmd_o.src0_bank = BANK_TEMP;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_B;
                cmd_o.word_count = 17'd0;
            end
            7'd79: begin
                cmd_o.op = CMD_CONV;
                cmd_o.id = 7'd62;
                cmd_o.src0_bank = BANK_B;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_MASK;
                cmd_o.word_count = 17'd0;
            end
            7'd80: begin
                cmd_o.op = CMD_ROI;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_MASK;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_MASK;
                cmd_o.word_count = 17'd0;
            end
            7'd81: begin
                cmd_o.op = CMD_DONE;
                cmd_o.id = 7'd0;
                cmd_o.src0_bank = BANK_A;
                cmd_o.src1_bank = BANK_A;
                cmd_o.dst_bank = BANK_A;
                cmd_o.word_count = 17'd0;
            end
            default: begin cmd_o.op = CMD_DONE; end
        endcase
    end

endmodule
