// V6.0.5: synchronous 48-bit line-pair RAM, bit-exact 2x2 RNE scaler.
// Camera pixel samples are RGB565->YCbCr24, one input sample per pixel_valid_i.
// Even source row: assemble {even_col, odd_col} into 48-bit RAM entry.
// Odd source row: read that entry at even column; compute output at odd column.
// RAM never needs asynchronous read, so Quartus can infer Cyclone V M10K.
module area_scaler_2x2 (
    input logic clk_i, rstn_i, start_i, pixel_valid_i,
    input logic [23:0] pixel_ycbcr_i,
    output logic pixel_valid_o,
    output logic [23:0] pixel_ycbcr_o,
    output logic pixel_last_o
);
    localparam integer INPUT_WIDTH=640;
    localparam integer PAIR_COUNT=INPUT_WIDTH/2;
    logic [9:0] x_r;
    logic [8:0] y_r;
    (* ramstyle = "M10K" *) logic [47:0] top_pairs [0:PAIR_COUNT-1];
    logic [47:0] top_pair_read_q;
    logic [23:0] top_even_q;
    logic [23:0] bottom_even_q;
    logic [9:0] sum_y_c, sum_cb_c, sum_cr_c;

    function automatic [7:0] rne_div4(input logic [9:0] value);
        logic [7:0] q;
        logic [1:0] rem;
        begin
            q = value[9:2]; rem = value[1:0];
            rne_div4 = q + ((rem > 2) || ((rem == 2) && q[0]));
        end
    endfunction

    always_comb begin
        sum_y_c = {2'b00,top_pair_read_q[47:40]} + {2'b00,top_pair_read_q[23:16]} +
                  {2'b00,bottom_even_q[23:16]} + {2'b00,pixel_ycbcr_i[23:16]};
        sum_cb_c = {2'b00,top_pair_read_q[39:32]} + {2'b00,top_pair_read_q[15:8]} +
                   {2'b00,bottom_even_q[15:8]} + {2'b00,pixel_ycbcr_i[15:8]};
        sum_cr_c = {2'b00,top_pair_read_q[31:24]} + {2'b00,top_pair_read_q[7:0]} +
                   {2'b00,bottom_even_q[7:0]} + {2'b00,pixel_ycbcr_i[7:0]};
    end

    // MEMORY READ/WRITE SEPARATE FROM RESETTABLE CONTROL REGISTERS.
    // TOP pair read is registered and settles before the next accepted odd-column pixel.
    always_ff @(posedge clk_i) begin
        if (rstn_i && !start_i && pixel_valid_i) begin
            if (!y_r[0] && x_r[0])
                top_pairs[x_r[9:1]] <= {top_even_q,pixel_ycbcr_i};
            if (y_r[0] && !x_r[0])
                top_pair_read_q <= top_pairs[x_r[9:1]];
        end
    end

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            x_r <= 0; y_r <= 0;
            top_even_q <= 0; bottom_even_q <= 0;
            pixel_valid_o <= 0; pixel_ycbcr_o <= 0; pixel_last_o <= 0;
        end else if (start_i) begin
            x_r <= 0; y_r <= 0;
            top_even_q <= 0; bottom_even_q <= 0;
            pixel_valid_o <= 0; pixel_last_o <= 0;
        end else begin
            pixel_valid_o <= 0;
            pixel_last_o <= 0;
            if (pixel_valid_i) begin
                if (!y_r[0] && !x_r[0]) begin
                    top_even_q <= pixel_ycbcr_i;
                end else if (y_r[0] && !x_r[0]) begin
                    bottom_even_q <= pixel_ycbcr_i;
                end else if (y_r[0] && x_r[0]) begin
                    pixel_ycbcr_o <= {rne_div4(sum_y_c), rne_div4(sum_cb_c), rne_div4(sum_cr_c)};
                    pixel_valid_o <= 1'b1;
                    if (x_r == 639 && y_r == 479) pixel_last_o <= 1'b1;
                end
                if (x_r == 639) begin
                    x_r <= 0;
                    if (y_r == 479) y_r <= 0;
                    else y_r <= y_r + 1'b1;
                end else x_r <= x_r + 1'b1;
            end
        end
    end
endmodule
