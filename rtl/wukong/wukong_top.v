`default_nettype none

module wukong_top (
    input  wire       clk_50mhz,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output wire       sd_cs_n,
    output wire       sd_sck,
    output wire       sd_mosi,
    input  wire       sd_miso,
    output wire       uart_tx,
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

    wire hsync;
    wire vsync;
    wire video_enable;
    wire [7:0] red;
    wire [7:0] green;
    wire [7:0] blue;
    wire [5:0] audio_dac;
    wire narrow_video_mode;

    wukong_clocking clocking_i (
        .clk_50mhz    (clk_50mhz),
        .pixel_clk    (pixel_clk),
        .serial_clk   (serial_clk),
        .locked       (clocks_locked),
        .video_reset  (video_reset)
    );

`ifdef HDMI_LIBRARY_TEST
    wire [9:0] library_x;
    wire [9:0] library_y;
    wire [9:0] library_frame_width;
    wire [9:0] library_frame_height;
    wire [9:0] library_screen_width;
    wire [9:0] library_screen_height;
    wire [2:0] library_tmds;
    wire library_tmds_clock;
    wire library_active = (library_x < library_screen_width) &&
                          (library_y < library_screen_height);
    wire [7:0] library_red;
    wire [7:0] library_green;
    wire [7:0] library_blue;
    wire [15:0] hdmi_audio_words [1:0];
    reg [8:0] hdmi_audio_divider;
    reg hdmi_audio_clk_unbuffered;
    wire hdmi_audio_clk;
    wire signed [6:0] centered_audio =
        $signed({1'b0, audio_dac}) - 7'sd32;
    wire signed [15:0] scaled_audio = centered_audio <<< 8;
    wire [23:0] library_rgb_direct;
    reg [23:0] narrow_rgb_delay [0:63];
    integer narrow_delay_index;
    wire [23:0] library_rgb = narrow_video_mode
        ? narrow_rgb_delay[63] : library_rgb_direct;

`ifdef HDMI_LIBRARY_AUDIO
`ifdef HDMI_LIBRARY_COCO
    assign hdmi_audio_words[0] = scaled_audio;
    assign hdmi_audio_words[1] = scaled_audio;
`else
    // Exercise normal HDMI audio packet transmission without generating a
    // sound test. The library pattern carries two channels of digital silence.
    assign hdmi_audio_words[0] = 16'd0;
    assign hdmi_audio_words[1] = 16'd0;
`endif

    // Divide 25.2 MHz by 525 using alternating 262- and 263-cycle half
    // periods. The BUFG puts the resulting 48 kHz clock on dedicated clock
    // routing; wukong_audio.xdc declares its relationship to pixel_clk.
    always @(posedge pixel_clk) begin
        if (video_reset) begin
            hdmi_audio_divider <= 9'd0;
            hdmi_audio_clk_unbuffered <= 1'b0;
        end else if ((!hdmi_audio_clk_unbuffered &&
                      hdmi_audio_divider == 9'd261) ||
                     (hdmi_audio_clk_unbuffered &&
                      hdmi_audio_divider == 9'd262)) begin
            hdmi_audio_divider <= 9'd0;
            hdmi_audio_clk_unbuffered <= !hdmi_audio_clk_unbuffered;
        end else begin
            hdmi_audio_divider <= hdmi_audio_divider + 1'b1;
        end
    end

    BUFG hdmi_audio_bufg_i (
        .I(hdmi_audio_clk_unbuffered),
        .O(hdmi_audio_clk)
    );

`else
    assign hdmi_audio_words[0] = 16'd0;
    assign hdmi_audio_words[1] = 16'd0;
    always @* begin
        hdmi_audio_divider = 9'd0;
        hdmi_audio_clk_unbuffered = 1'b0;
    end
    assign hdmi_audio_clk = 1'b0;
`endif

`ifdef HDMI_LIBRARY_COCO
    // The GIME exposes a 656-pixel-wide visible region and wraps its 486
    // visible scanlines across the 800x525 frame boundary. Start the HDMI
    // Resync the GIME 19 clocks before horizontal wrap so all 640 source
    // pixels reach HDMI x=0..639. Border-transition artifacts must be fixed
    // in the GIME path rather than hidden by clipping valid source pixels.
    wire library_frame_start = (library_x == 10'd781) &&
                               (library_y == 10'd18);
    coco3_boot_system source_i (
        .pixel_clk(pixel_clk), .reset(video_reset),
        .raster_resync(library_frame_start), .hsync(hsync),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .vsync(vsync), .video_enable(video_enable),
        .red(library_red), .green(library_green), .blue(library_blue),
        .audio_dac(audio_dac), .narrow_video_mode(narrow_video_mode),
        .uart_debug_tx(uart_tx)
    );
    // The post-processing pipeline can retain non-black RGB values while the
    // GIME is blanked. The previous encoder honored video_enable; preserve
    // that behavior before handing pixels to the library-owned HDMI raster.
    assign library_rgb_direct = video_enable
        ? {library_red, library_green, library_blue} : 24'd0;

    always @(posedge pixel_clk) begin
        if (video_reset || library_frame_start) begin
            for (narrow_delay_index = 0; narrow_delay_index < 64;
                 narrow_delay_index = narrow_delay_index + 1)
                narrow_rgb_delay[narrow_delay_index] <= 24'd0;
        end else begin
            narrow_rgb_delay[0] <= library_rgb_direct;
            for (narrow_delay_index = 1; narrow_delay_index < 64;
                 narrow_delay_index = narrow_delay_index + 1)
                narrow_rgb_delay[narrow_delay_index] <=
                    narrow_rgb_delay[narrow_delay_index - 1];
        end
    end
`else
    assign uart_tx = 1'b1;
    assign sd_cs_n = 1'b1;
    assign sd_sck = 1'b0;
    assign sd_mosi = 1'b1;
    assign audio_dac = 6'd32;
    test_pattern library_pattern_i (
        .x(library_x), .y(library_y), .video_enable(library_active),
        .red(library_red), .green(library_green), .blue(library_blue)
    );
    assign library_rgb_direct = {library_red, library_green, library_blue};
    assign narrow_video_mode = 1'b0;
`endif

    hdmi #(
        .VIDEO_ID_CODE(1),
`ifdef HDMI_LIBRARY_AUDIO
        .DVI_OUTPUT(1'b0),
`else
        .DVI_OUTPUT(1'b1),
`endif
        .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16),
`ifdef HDMI_LIBRARY_COCO
        // Match the hdl-util 640x480 example: its raster counters start at
        // the origin. GIME-to-HDMI alignment is handled independently by
        // library_frame_start above.
        .START_X(0), .START_Y(0)
`else
        .START_X(0), .START_Y(0)
`endif
    ) library_hdmi_i (
        .clk_pixel_x5(serial_clk), .clk_pixel(pixel_clk),
        .clk_audio(hdmi_audio_clk), .reset(video_reset),
        .rgb(library_rgb),
        .audio_sample_word(hdmi_audio_words),
        .tmds(library_tmds), .tmds_clock(library_tmds_clock),
        .cx(library_x), .cy(library_y),
        .frame_width(library_frame_width), .frame_height(library_frame_height),
        .screen_width(library_screen_width), .screen_height(library_screen_height)
    );

    assign hdmi_serial = {library_tmds_clock, library_tmds};
`else
    assign uart_tx = 1'b1;
    assign audio_dac = 6'd32;
    assign narrow_video_mode = 1'b0;
    assign sd_cs_n = 1'b1;
    assign sd_sck = 1'b0;
    assign sd_mosi = 1'b1;
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
`endif // HDMI_LIBRARY_TEST

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
