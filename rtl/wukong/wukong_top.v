`default_nettype none

module wukong_top (
    input  wire       clk_50mhz,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n
);
    wire pixel_clk;
    wire serial_clk;
    wire clocks_locked;
    wire video_reset;

    wire [9:0] tmds_red;
    wire [9:0] tmds_green;
    wire [9:0] tmds_blue;
    wire [9:0] tmds_clock = 10'b1111100000;
    wire [3:0] tmds_serial;

    wire [9:0] x;
    wire [9:0] y;
    wire hsync;
    wire vsync;
    wire video_enable;
    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;

    wukong_clocking clocking_i (
        .clk_50mhz    (clk_50mhz),
        .pixel_clk    (pixel_clk),
        .serial_clk   (serial_clk),
        .locked       (clocks_locked),
        .video_reset  (video_reset)
    );

`ifdef COCO2_BOOT
    coco2_boot_system source_i (
        .pixel_clk(pixel_clk), .reset(video_reset), .hsync(hsync),
        .vsync(vsync), .video_enable(video_enable), .red(red), .green(green), .blue(blue)
    );
`elsif COCO3_BOOT
    coco3_boot_system source_i (
        .pixel_clk(pixel_clk), .reset(video_reset), .hsync(hsync),
        .vsync(vsync), .video_enable(video_enable),
        .red(red), .green(green), .blue(blue)
    );
`elsif CPU_DIAGNOSTIC
    coco3_diagnostic_system source_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_enable (video_enable),
        .red          (red),
        .green        (green),
        .blue         (blue)
    );
`elsif COCO_VIDEO
    coco_video_source source_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_enable (video_enable),
        .red          (red),
        .green        (green),
        .blue         (blue)
    );
`else
    video_timing timing_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .x            (x),
        .y            (y),
        .hsync        (hsync),
        .vsync        (vsync),
        .video_enable (video_enable)
    );

    test_pattern pattern_i (
        .x            (x),
        .y            (y),
        .video_enable (video_enable),
        .red          (red),
        .green        (green),
        .blue         (blue)
    );
`endif

    tmds_encoder encode_blue_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .video_data   (blue),
        .control_data ({vsync, hsync}),
        .data_enable  (video_enable),
        .tmds_data    (tmds_blue)
    );

    tmds_encoder encode_green_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .video_data   (green),
        .control_data (2'b00),
        .data_enable  (video_enable),
        .tmds_data    (tmds_green)
    );

    tmds_encoder encode_red_i (
        .pixel_clk    (pixel_clk),
        .reset        (video_reset),
        .video_data   (red),
        .control_data (2'b00),
        .data_enable  (video_enable),
        .tmds_data    (tmds_red)
    );

    tmds_serializer serialize_blue_i (
        .pixel_clk  (pixel_clk), .serial_clk(serial_clk),
        .reset      (video_reset), .parallel_data(tmds_blue),
        .serial_data(tmds_serial[0])
    );
    tmds_serializer serialize_green_i (
        .pixel_clk  (pixel_clk), .serial_clk(serial_clk),
        .reset      (video_reset), .parallel_data(tmds_green),
        .serial_data(tmds_serial[1])
    );
    tmds_serializer serialize_red_i (
        .pixel_clk  (pixel_clk), .serial_clk(serial_clk),
        .reset      (video_reset), .parallel_data(tmds_red),
        .serial_data(tmds_serial[2])
    );
    tmds_serializer serialize_clock_i (
        .pixel_clk  (pixel_clk), .serial_clk(serial_clk),
        .reset      (video_reset), .parallel_data(tmds_clock),
        .serial_data(tmds_serial[3])
    );

    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data0_obuf_i
        (.I(tmds_serial[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data1_obuf_i
        (.I(tmds_serial[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data2_obuf_i
        (.I(tmds_serial[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) clock_obuf_i
        (.I(tmds_serial[3]), .O(hdmi_clk_p), .OB(hdmi_clk_n));

    wire _unused = clocks_locked;
endmodule

`default_nettype wire
