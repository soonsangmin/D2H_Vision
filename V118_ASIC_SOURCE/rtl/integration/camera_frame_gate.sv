module camera_frame_gate #(
    parameter integer XRES = 640,
    parameter integer YRES = 480
)(
    input  logic        cam_pclk_i,
    input  logic        rstn_i,

    // ============================================================
    // CAMERA FRAME MARKER
    //
    // Connect directly from:
    //
    //     camera_module.cam_frame_rst_o
    //
    // Current camera_ctrl:
    //
    //     cam_frame_rst_o = cam_vsync_i
    //
    // Therefore this module detects the rising edge internally.
    // ============================================================
    input  logic        cam_frame_rst_i,

    // New captures are ignored until the AI parameter image is ready in DDR.
    input  logic        enable_i,

    // ============================================================
    // CAMERA PIXEL STREAM
    //
    // RGB565
    // ============================================================
    input  logic [15:0] pixel_data_i,
    input  logic        pixel_valid_i,

    // ============================================================
    // RELEASE
    //
    // IMPORTANT:
    // release_i must already be synchronized into cam_pclk_i
    // domain.
    //
    // Later this will come from ROI_DONE through a CDC synchronizer.
    // ============================================================
    input  logic        release_i,

    // ============================================================
    // ACCEPTED PIXEL STREAM
    // ============================================================
    output logic [15:0] pixel_data_o,
    output logic        pixel_valid_o,

    // Pulse for one cam_pclk cycle when a new frame is accepted.
    output logic        frame_start_o,

    // Pulse for one cam_pclk cycle after the final accepted pixel.
    output logic        frame_done_o,

    // 1 while currently capturing pixels of accepted frame.
    output logic        capture_active_o,

    // 1 from accepted VSYNC until release_i.
    //
    // While locked, all following camera frames are ignored.
    output logic        frame_locked_o
);


    // ============================================================
    // PARAMETERS
    // ============================================================

    localparam integer FRAME_PIXELS =
        XRES * YRES;

    localparam integer COUNT_WIDTH =
        $clog2(FRAME_PIXELS);


    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================

    logic cam_frame_rst_d;

    logic capture_active_r;
    logic frame_locked_r;

    logic [COUNT_WIDTH-1:0] pixel_count_r;


    // ============================================================
    // VSYNC RISING EDGE
    // ============================================================

    logic frame_rise_c;

    assign frame_rise_c =
        cam_frame_rst_i
        &
        ~cam_frame_rst_d;


    // ============================================================
    // OUTPUTS
    // ============================================================

    assign pixel_data_o =
        pixel_data_i;


    // Pixel is forwarded only while processing the accepted frame.
    assign pixel_valid_o =
        capture_active_r
        &
        pixel_valid_i;


    assign capture_active_o =
        capture_active_r;


    assign frame_locked_o =
        frame_locked_r;


    // ============================================================
    // MAIN CONTROL
    // ============================================================

    always_ff @(posedge cam_pclk_i or negedge rstn_i) begin

        if (!rstn_i) begin

            cam_frame_rst_d <=
                1'b0;

            capture_active_r <=
                1'b0;

            frame_locked_r <=
                1'b0;

            pixel_count_r <=
                '0;

            frame_start_o <=
                1'b0;

            frame_done_o <=
                1'b0;

        end

        else begin

            // ----------------------------------------------------
            // Edge detector register
            // ----------------------------------------------------

            cam_frame_rst_d <=
                cam_frame_rst_i;


            // ----------------------------------------------------
            // Default pulses
            // ----------------------------------------------------

            frame_start_o <=
                1'b0;

            frame_done_o <=
                1'b0;


            // ====================================================
            // RELEASE PREVIOUS FRAME
            // ====================================================
            //
            // ROI has been found.
            //
            // IMPORTANT:
            // This only unlocks the system.
            //
            // It does NOT start reading pixels immediately.
            //
            // A new frame is accepted only at the NEXT VSYNC.
            // ====================================================

            if (release_i) begin

                frame_locked_r <=
                    1'b0;

            end


            // ====================================================
            // ACCEPT NEW FRAME
            // ====================================================

            if (
                frame_rise_c
                &&
                enable_i
                &&
                !frame_locked_r
            ) begin

                capture_active_r <=
                    1'b1;

                frame_locked_r <=
                    1'b1;

                pixel_count_r <=
                    '0;

                frame_start_o <=
                    1'b1;

            end


            // ====================================================
            // COUNT ACCEPTED RGB565 PIXELS
            // ====================================================

            if (
                capture_active_r
                &&
                pixel_valid_i
            ) begin

                // ------------------------------------------------
                // Final pixel of 640x480 frame
                // ------------------------------------------------

                if (
                    pixel_count_r
                    ==
                    FRAME_PIXELS - 1
                ) begin

                    capture_active_r <=
                        1'b0;

                    pixel_count_r <=
                        '0;

                    frame_done_o <=
                        1'b1;

                end

                else begin

                    pixel_count_r <=
                        pixel_count_r
                        +
                        1'b1;

                end

            end

        end

    end


endmodule