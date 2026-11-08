module roi_overlay_rgb565 #(
    parameter integer BORDER_THICKNESS = 3,
    parameter logic [15:0] BORDER_COLOR = 16'hFFE0
)(
    input  logic [15:0] pixel_i,
    input  logic [9:0]  pixel_x_i,
    input  logic [8:0]  pixel_y_i,

    input  logic        roi_valid_i,
    input  logic [9:0]  roi_xmin_i,
    input  logic [8:0]  roi_ymin_i,
    input  logic [9:0]  roi_xmax_i,
    input  logic [8:0]  roi_ymax_i,

    output logic [15:0] pixel_o
);

    logic inside_x_c;
    logic inside_y_c;

    logic top_edge_c;
    logic bottom_edge_c;
    logic left_edge_c;
    logic right_edge_c;

    logic border_c;

    always_comb begin
        inside_x_c =
            (pixel_x_i >= roi_xmin_i)
            &&
            (pixel_x_i <= roi_xmax_i);

        inside_y_c =
            (pixel_y_i >= roi_ymin_i)
            &&
            (pixel_y_i <= roi_ymax_i);

        top_edge_c =
            inside_x_c
            &&
            (pixel_y_i >= roi_ymin_i)
            &&
            ((pixel_y_i - roi_ymin_i) < BORDER_THICKNESS);

        bottom_edge_c =
            inside_x_c
            &&
            (pixel_y_i <= roi_ymax_i)
            &&
            ((roi_ymax_i - pixel_y_i) < BORDER_THICKNESS);

        left_edge_c =
            inside_y_c
            &&
            (pixel_x_i >= roi_xmin_i)
            &&
            ((pixel_x_i - roi_xmin_i) < BORDER_THICKNESS);

        right_edge_c =
            inside_y_c
            &&
            (pixel_x_i <= roi_xmax_i)
            &&
            ((roi_xmax_i - pixel_x_i) < BORDER_THICKNESS);

        border_c =
            roi_valid_i
            &&
            (
                top_edge_c
                || bottom_edge_c
                || left_edge_c
                || right_edge_c
            );

        if (border_c) begin
            pixel_o = BORDER_COLOR;
        end
        else begin
            pixel_o = pixel_i;
        end
    end

endmodule
