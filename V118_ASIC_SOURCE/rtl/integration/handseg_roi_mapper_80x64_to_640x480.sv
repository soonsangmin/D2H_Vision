module handseg_roi_mapper_80x64_to_640x480 (
    input  logic       roi_valid_i,
    input  logic [6:0] xmin_cell_i,
    input  logic [5:0] ymin_cell_i,
    input  logic [6:0] xmax_cell_i,
    input  logic [5:0] ymax_cell_i,

    output logic       roi_valid_o,
    output logic [9:0] xmin_o,
    output logic [8:0] ymin_o,
    output logic [9:0] xmax_o,
    output logic [8:0] ymax_o
);

    // Mask grid is 80x64.
    // Each mask cell covers 4x4 pixels in the 320x256 model input.
    // 320x240 image came from 640x480 by AREA2x2, and 8 model rows
    // were padded at the top. Therefore one mask cell maps to 8x8
    // camera pixels and the vertical origin is shifted by 16 pixels.

    integer x0_i;
    integer y0_i;
    integer x1_i;
    integer y1_i;

    always_comb begin
        x0_i = xmin_cell_i << 3;
        x1_i = ((xmax_cell_i + 1) << 3) - 1;

        y0_i = (ymin_cell_i << 3) - 16;
        y1_i = ((ymax_cell_i + 1) << 3) - 17;

        if (x0_i < 0)   x0_i = 0;
        if (x0_i > 639) x0_i = 639;
        if (x1_i < 0)   x1_i = 0;
        if (x1_i > 639) x1_i = 639;

        if (y0_i < 0)   y0_i = 0;
        if (y0_i > 479) y0_i = 479;
        if (y1_i < 0)   y1_i = 0;
        if (y1_i > 479) y1_i = 479;

        xmin_o = x0_i[9:0];
        xmax_o = x1_i[9:0];
        ymin_o = y0_i[8:0];
        ymax_o = y1_i[8:0];

        roi_valid_o = roi_valid_i &&
                      (xmin_cell_i <= xmax_cell_i) &&
                      (ymin_cell_i <= ymax_cell_i);
    end

endmodule
