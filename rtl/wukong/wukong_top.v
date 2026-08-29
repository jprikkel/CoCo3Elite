`default_nettype none

module wukong_top (
    input  wire       clk_50mhz,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output wire       sd_cs_n,
    output wire       sd_sck,
    output wire       sd_mosi,
    input  wire       sd_miso,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n
);
    wire pixel_clk;
    wire serial_clk;
    wire clocks_locked;
    wire video_reset;

    wire [9:0] hdmi_blue_symbol;
    wire [9:0] hdmi_green_symbol;
    wire [9:0] hdmi_red_symbol;
    wire [9:0] hdmi_clock_symbol = 10'b1111100000;
    wire [3:0] hdmi_serial;

    wire [9:0] x;
    wire [9:0] y;
    wire hsync;
    wire vsync;
    wire video_enable;
    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;
    wire [5:0] audio_dac;

    wukong_clocking clocking_i (
        .clk_50mhz    (clk_50mhz),
        .pixel_clk    (pixel_clk),
        .serial_clk   (serial_clk),
        .locked       (clocks_locked),
        .video_reset  (video_reset)
    );

`ifdef COCO3_BOOT
    coco3_boot_system source_i (
        .pixel_clk(pixel_clk), .reset(video_reset), .hsync(hsync),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .vsync(vsync), .video_enable(video_enable),
        .red(red), .green(green), .blue(blue), .audio_dac(audio_dac)
    );
`elsif CPU_DIAGNOSTIC
    assign audio_dac = 6'd32;
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
    assign audio_dac = 6'd32;
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
    assign audio_dac = 6'd32;
    assign sd_cs_n = 1'b1;
    assign sd_sck = 1'b0;
    assign sd_mosi = 1'b1;
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

`ifdef HDMI_AUDIO
    wukong_hdmi_tx hdmi_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(video_reset),
        .hsync(hsync), .vsync(vsync), .video_enable(video_enable),
        .red(red), .green(green), .blue(blue), .audio_dac(audio_dac),
        .tmds_serial(hdmi_serial)
    );
`else
    tmds_channel #(.CN(0)) hdmi_blue_i (
        .clk_pixel(pixel_clk), .video_data(blue),
        .data_island_data(4'h0), .control_data({vsync, hsync}),
        .mode(video_enable ? 3'd1 : 3'd0), .tmds(hdmi_blue_symbol));
    tmds_channel #(.CN(1)) hdmi_green_i (
        .clk_pixel(pixel_clk), .video_data(green),
        .data_island_data(4'h0), .control_data(2'b00),
        .mode(video_enable ? 3'd1 : 3'd0), .tmds(hdmi_green_symbol));
    tmds_channel #(.CN(2)) hdmi_red_i (
        .clk_pixel(pixel_clk), .video_data(red),
        .data_island_data(4'h0), .control_data(2'b00),
        .mode(video_enable ? 3'd1 : 3'd0), .tmds(hdmi_red_symbol));

    tmds_serializer serialize_blue_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(video_reset),
        .parallel_data(hdmi_blue_symbol), .serial_data(hdmi_serial[0]));
    tmds_serializer serialize_green_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(video_reset),
        .parallel_data(hdmi_green_symbol), .serial_data(hdmi_serial[1]));
    tmds_serializer serialize_red_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(video_reset),
        .parallel_data(hdmi_red_symbol), .serial_data(hdmi_serial[2]));
    tmds_serializer serialize_clock_i (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(video_reset),
        .parallel_data(hdmi_clock_symbol), .serial_data(hdmi_serial[3]));
`endif

    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data0_obuf_i
        (.I(hdmi_serial[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data1_obuf_i
        (.I(hdmi_serial[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) data2_obuf_i
        (.I(hdmi_serial[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS #(.IOSTANDARD("TMDS_33"), .SLEW("FAST")) clock_obuf_i
        (.I(hdmi_serial[3]), .O(hdmi_clk_p), .OB(hdmi_clk_n));

    wire _unused = clocks_locked;
endmodule

`default_nettype wire
