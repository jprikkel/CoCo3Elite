`default_nettype none

module wukong_top (
    input  wire       clk_50mhz,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    input  wire       joystick_up_n,
    input  wire       joystick_down_n,
    input  wire       joystick_left_n,
    input  wire       joystick_right_n,
    input  wire       joystick_button1_n,
    input  wire       joystick_button2_n,
    output wire       sd_cs_n,
    output wire       sd_sck,
    output wire       sd_mosi,
    input  wire       sd_miso,
`ifdef WUKONG_PHYSICAL_FLOPPY
    output wire       floppy_select_n,
    output wire       floppy_motor_enable_n,
    output wire       floppy_direction,
    output wire       floppy_step_n,
    output wire       floppy_side_select,
    input  wire       floppy_read_data_n,
    input  wire       floppy_track_zero_n,
    input  wire       floppy_index_n,
`endif
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire       sdram_clk,
    output wire       sdram_cke,
    output wire       sdram_cs_n,
    output wire       sdram_ras_n,
    output wire       sdram_cas_n,
    output wire       sdram_we_n,
    output wire [1:0] sdram_dqm,
    output wire [12:0] sdram_address,
    output wire [1:0] sdram_bank,
    inout  wire [15:0] sdram_data,
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n
);
    wire pixel_clk;
    wire serial_clk;
    wire memory_clk;
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
    wire [6:0] audio_dac;
    wire narrow_video_mode;
    wire menu_active;
    wire physical_joystick_up;
    wire physical_joystick_down;
    wire physical_joystick_left;
    wire physical_joystick_right;
    wire physical_joystick_button1;
    wire physical_joystick_button2;
    wire physical_floppy_present;
    wire [2:0] physical_floppy_status;
    wire [31:0] physical_floppy_index_count;
    wire [31:0] physical_floppy_read_transition_count;
    wire physical_floppy_motor_request;
    wire physical_floppy_direction_request;
    wire physical_floppy_side_select_request;
    wire physical_floppy_step_request_toggle;
    wire physical_floppy_home_request_toggle;
    wire physical_floppy_abort_request_toggle;
    wire physical_floppy_capture_request_toggle;
    wire [15:0] physical_floppy_capture_skip_count;
    wire [15:0] physical_floppy_capture_sample_address;
    wire physical_floppy_motor_active;
    wire physical_floppy_home_active;
    wire physical_floppy_home_done_toggle;
    wire physical_floppy_home_success;
    wire [7:0] physical_floppy_home_step_count;
    wire physical_floppy_capture_busy;
    wire physical_floppy_capture_done_toggle;
    wire physical_floppy_capture_success;
    wire physical_floppy_capture_truncated;
    wire physical_floppy_capture_direction;
    wire physical_floppy_capture_side;
    wire [15:0] physical_floppy_capture_flux_count;
    wire [23:0] physical_floppy_capture_revolution_cycles;
    wire [15:0] physical_floppy_capture_min_interval;
    wire [15:0] physical_floppy_capture_max_interval;
    wire [31:0] physical_floppy_capture_hash;
    wire [15:0] physical_floppy_capture_sample_count;
    wire [15:0] physical_floppy_capture_sample_data;
    wire physical_floppy_decode_request_toggle;
    wire [12:0] physical_floppy_decode_cache_address;
    wire physical_floppy_decode_busy;
    wire physical_floppy_decode_done_toggle;
    wire physical_floppy_decode_success;
    wire [7:0] physical_floppy_decode_track;
    wire physical_floppy_decode_side;
    wire [17:0] physical_floppy_decode_sector_valid;
    wire [7:0] physical_floppy_decode_id_crc_errors;
    wire [7:0] physical_floppy_decode_data_crc_errors;
    wire [7:0] physical_floppy_decode_cache_data;

    wukong_clocking clocking_i (
        .clk_50mhz    (clk_50mhz),
        .pixel_clk    (pixel_clk),
        .serial_clk   (serial_clk),
        .memory_clk   (memory_clk),
        .locked       (clocks_locked),
        .video_reset  (video_reset)
    );

    pmod_atari_joystick physical_joystick_i (
        .clock(pixel_clk), .reset(video_reset),
        .up_n(joystick_up_n), .down_n(joystick_down_n),
        .left_n(joystick_left_n), .right_n(joystick_right_n),
        .button1_n(joystick_button1_n),
        .button2_n(joystick_button2_n),
        .up(physical_joystick_up), .down(physical_joystick_down),
        .left(physical_joystick_left), .right(physical_joystick_right),
        .button1(physical_joystick_button1),
        .button2(physical_joystick_button2)
    );

`ifdef WUKONG_PHYSICAL_FLOPPY
    assign physical_floppy_present = 1'b1;
    pmod_floppy_read_only physical_floppy_i (
        .clock(pixel_clk), .reset(video_reset),
        .motor_request(physical_floppy_motor_request),
        .direction_request(physical_floppy_direction_request),
        .side_select_request(physical_floppy_side_select_request),
        .step_request_toggle(physical_floppy_step_request_toggle),
        .home_request_toggle(physical_floppy_home_request_toggle),
        .abort_request_toggle(physical_floppy_abort_request_toggle),
        .capture_request_toggle(physical_floppy_capture_request_toggle),
        .capture_skip_count(physical_floppy_capture_skip_count),
        .capture_sample_address(physical_floppy_capture_sample_address),
        .decode_request_toggle(physical_floppy_decode_request_toggle),
        .decode_cache_address(physical_floppy_decode_cache_address),
        .read_data_n(floppy_read_data_n),
        .track_zero_n(floppy_track_zero_n), .index_n(floppy_index_n),
        .drive_select_n(floppy_select_n),
        .motor_enable_n(floppy_motor_enable_n),
        .direction(floppy_direction), .step_n(floppy_step_n),
        .side_select(floppy_side_select),
        .motor_active(physical_floppy_motor_active),
        .home_active(physical_floppy_home_active),
        .home_done_toggle(physical_floppy_home_done_toggle),
        .home_success(physical_floppy_home_success),
        .home_step_count(physical_floppy_home_step_count),
        .input_status(physical_floppy_status),
        .index_pulse_count(physical_floppy_index_count),
        .read_transition_count(physical_floppy_read_transition_count),
        .capture_busy(physical_floppy_capture_busy),
        .capture_done_toggle(physical_floppy_capture_done_toggle),
        .capture_success(physical_floppy_capture_success),
        .capture_truncated(physical_floppy_capture_truncated),
        .capture_direction(physical_floppy_capture_direction),
        .capture_side(physical_floppy_capture_side),
        .capture_flux_count(physical_floppy_capture_flux_count),
        .capture_revolution_cycles(
            physical_floppy_capture_revolution_cycles),
        .capture_min_interval(physical_floppy_capture_min_interval),
        .capture_max_interval(physical_floppy_capture_max_interval),
        .capture_hash(physical_floppy_capture_hash),
        .capture_sample_count(physical_floppy_capture_sample_count),
        .capture_sample_data(physical_floppy_capture_sample_data),
        .decode_busy(physical_floppy_decode_busy),
        .decode_done_toggle(physical_floppy_decode_done_toggle),
        .decode_success(physical_floppy_decode_success),
        .decode_track(physical_floppy_decode_track),
        .decode_side(physical_floppy_decode_side),
        .decode_sector_valid(physical_floppy_decode_sector_valid),
        .decode_id_crc_errors(physical_floppy_decode_id_crc_errors),
        .decode_data_crc_errors(physical_floppy_decode_data_crc_errors),
        .decode_cache_data(physical_floppy_decode_cache_data)
    );
`else
    assign physical_floppy_present = 1'b0;
    assign physical_floppy_status = 3'b000;
    assign physical_floppy_index_count = 32'b0;
    assign physical_floppy_read_transition_count = 32'b0;
    assign physical_floppy_motor_active = 1'b0;
    assign physical_floppy_home_active = 1'b0;
    assign physical_floppy_home_done_toggle = 1'b0;
    assign physical_floppy_home_success = 1'b0;
    assign physical_floppy_home_step_count = 8'b0;
    assign physical_floppy_capture_busy = 1'b0;
    assign physical_floppy_capture_done_toggle = 1'b0;
    assign physical_floppy_capture_success = 1'b0;
    assign physical_floppy_capture_truncated = 1'b0;
    assign physical_floppy_capture_direction = 1'b0;
    assign physical_floppy_capture_side = 1'b0;
    assign physical_floppy_capture_flux_count = 16'b0;
    assign physical_floppy_capture_revolution_cycles = 24'b0;
    assign physical_floppy_capture_min_interval = 16'b0;
    assign physical_floppy_capture_max_interval = 16'b0;
    assign physical_floppy_capture_hash = 32'b0;
    assign physical_floppy_capture_sample_count = 16'b0;
    assign physical_floppy_capture_sample_data = 16'b0;
    assign physical_floppy_decode_busy = 1'b0;
    assign physical_floppy_decode_done_toggle = 1'b0;
    assign physical_floppy_decode_success = 1'b0;
    assign physical_floppy_decode_track = 8'b0;
    assign physical_floppy_decode_side = 1'b0;
    assign physical_floppy_decode_sector_valid = 18'b0;
    assign physical_floppy_decode_id_crc_errors = 8'b0;
    assign physical_floppy_decode_data_crc_errors = 8'b0;
    assign physical_floppy_decode_cache_data = 8'b0;
`endif

`ifdef HDMI_TEST_PATTERN
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
    // The low six bits are the existing offset-binary DAC. PIA1 PB1 is the
    // seventh, single-bit sound component used by several CoCo programs.
    // Center at the DAC's established midpoint so PB1=0 leaves existing
    // six-bit audio bit-for-bit unchanged.
    wire signed [7:0] centered_audio =
        $signed({1'b0, audio_dac}) - 8'sd32;
    wire signed [15:0] scaled_audio = centered_audio <<< 8;
    wire [23:0] library_rgb_direct;
    reg [23:0] narrow_rgb_delay [0:63];
    integer narrow_delay_index;
    // The 64-pixel delay aligns narrow GIME modes.  The management OSD is
    // already drawn in HDMI raster coordinates and must bypass that delay.
    wire [23:0] library_rgb = narrow_video_mode && !menu_active
        ? narrow_rgb_delay[63] : library_rgb_direct;

`ifdef HDMI_LIBRARY_COCO
    wire video_capture_request_toggle;
    wire [5:0] video_capture_stripe;
    wire [15:0] video_capture_read_address;
    wire [7:0] video_capture_read_data;
    wire video_capture_done_toggle;
    wire video_capture_busy;
`endif

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
    // Resync the GIME 23 clocks before horizontal wrap. The four clocks of
    // downstream RGB processing then place all 640 source pixels at HDMI
    // x=0..639. Border-transition artifacts must be fixed in the GIME path
    // rather than hidden by clipping valid source pixels.
    wire library_frame_start = (library_x == 10'd777) &&
                               (library_y == 10'd18);
    coco3_boot_system source_i (
        .pixel_clk(pixel_clk), .memory_clk(memory_clk), .reset(video_reset),
        .raster_resync(library_frame_start),
        .screen_x(library_x), .screen_y(library_y), .hsync(hsync),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .physical_joystick_up(physical_joystick_up),
        .physical_joystick_down(physical_joystick_down),
        .physical_joystick_left(physical_joystick_left),
        .physical_joystick_right(physical_joystick_right),
        .physical_joystick_button1(physical_joystick_button1),
        .physical_joystick_button2(physical_joystick_button2),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .physical_floppy_present(physical_floppy_present),
        .physical_floppy_status(physical_floppy_status),
        .physical_floppy_index_count(physical_floppy_index_count),
        .physical_floppy_read_transition_count(
            physical_floppy_read_transition_count),
        .physical_floppy_motor_request(physical_floppy_motor_request),
        .physical_floppy_direction_request(
            physical_floppy_direction_request),
        .physical_floppy_side_select_request(
            physical_floppy_side_select_request),
        .physical_floppy_step_request_toggle(
            physical_floppy_step_request_toggle),
        .physical_floppy_home_request_toggle(
            physical_floppy_home_request_toggle),
        .physical_floppy_abort_request_toggle(
            physical_floppy_abort_request_toggle),
        .physical_floppy_capture_request_toggle(
            physical_floppy_capture_request_toggle),
        .physical_floppy_capture_skip_count(
            physical_floppy_capture_skip_count),
        .physical_floppy_capture_sample_address(
            physical_floppy_capture_sample_address),
        .physical_floppy_motor_active(physical_floppy_motor_active),
        .physical_floppy_home_active(physical_floppy_home_active),
        .physical_floppy_home_done_toggle(physical_floppy_home_done_toggle),
        .physical_floppy_home_success(physical_floppy_home_success),
        .physical_floppy_home_step_count(physical_floppy_home_step_count),
        .physical_floppy_capture_busy(physical_floppy_capture_busy),
        .physical_floppy_capture_done_toggle(
            physical_floppy_capture_done_toggle),
        .physical_floppy_capture_success(physical_floppy_capture_success),
        .physical_floppy_capture_truncated(
            physical_floppy_capture_truncated),
        .physical_floppy_capture_direction(
            physical_floppy_capture_direction),
        .physical_floppy_capture_side(physical_floppy_capture_side),
        .physical_floppy_capture_flux_count(
            physical_floppy_capture_flux_count),
        .physical_floppy_capture_revolution_cycles(
            physical_floppy_capture_revolution_cycles),
        .physical_floppy_capture_min_interval(
            physical_floppy_capture_min_interval),
        .physical_floppy_capture_max_interval(
            physical_floppy_capture_max_interval),
        .physical_floppy_capture_hash(physical_floppy_capture_hash),
        .physical_floppy_capture_sample_count(
            physical_floppy_capture_sample_count),
        .physical_floppy_capture_sample_data(
            physical_floppy_capture_sample_data),
        .physical_floppy_decode_request_toggle(
            physical_floppy_decode_request_toggle),
        .physical_floppy_decode_cache_address(
            physical_floppy_decode_cache_address),
        .physical_floppy_decode_busy(physical_floppy_decode_busy),
        .physical_floppy_decode_done_toggle(
            physical_floppy_decode_done_toggle),
        .physical_floppy_decode_success(physical_floppy_decode_success),
        .physical_floppy_decode_track(physical_floppy_decode_track),
        .physical_floppy_decode_side(physical_floppy_decode_side),
        .physical_floppy_decode_sector_valid(
            physical_floppy_decode_sector_valid),
        .physical_floppy_decode_id_crc_errors(
            physical_floppy_decode_id_crc_errors),
        .physical_floppy_decode_data_crc_errors(
            physical_floppy_decode_data_crc_errors),
        .physical_floppy_decode_cache_data(
            physical_floppy_decode_cache_data),
        .vsync(vsync), .video_enable(video_enable),
        .red(library_red), .green(library_green), .blue(library_blue),
        .audio_dac(audio_dac), .narrow_video_mode(narrow_video_mode),
        .menu_active(menu_active),
        .uart_debug_tx(uart_tx), .uart_rx(uart_rx),
        .video_capture_request_toggle(video_capture_request_toggle),
        .video_capture_stripe(video_capture_stripe),
        .video_capture_read_address(video_capture_read_address),
        .video_capture_read_data(video_capture_read_data),
        .video_capture_done_toggle(video_capture_done_toggle),
        .video_capture_busy(video_capture_busy),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dqm(sdram_dqm), .sdram_address(sdram_address),
        .sdram_bank(sdram_bank), .sdram_data(sdram_data)
    );
    // The post-processing pipeline can retain non-black RGB values while the
    // GIME is blanked. The previous encoder honored video_enable; preserve
    // that behavior before handing pixels to the library-owned HDMI raster.
    assign library_rgb_direct = (video_enable || menu_active)
        ? {library_red, library_green, library_blue} : 24'd0;

    always @(posedge pixel_clk) begin
        // Keep the horizontal alignment history across the per-frame GIME
        // resync. Clearing all 64 taps only 19 clocks before HDMI wraps to
        // x=0 exposes the zero-filled delay as a deterministic black segment
        // at the start of scanline 19. The delay contains pixels, not raster
        // state, so only the board-level video reset needs to initialize it.
        if (video_reset) begin
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

    video_frame_capture capture_i (
        .clock(pixel_clk), .reset(video_reset),
        .screen_x(library_x), .screen_y(library_y), .rgb(library_rgb),
        .request_toggle(video_capture_request_toggle),
        .request_stripe(video_capture_stripe),
        .done_toggle(video_capture_done_toggle), .busy(video_capture_busy),
        .read_address(video_capture_read_address),
        .read_data(video_capture_read_data)
    );
`else
    assign uart_tx = 1'b1;
    assign sd_cs_n = 1'b1;
    assign sd_sck = 1'b0;
    assign sd_mosi = 1'b1;
    assign audio_dac = 7'd32;
    test_pattern library_pattern_i (
        .x(library_x), .y(library_y), .video_enable(library_active),
        .red(library_red), .green(library_green), .blue(library_blue)
    );
    assign library_rgb_direct = {library_red, library_green, library_blue};
    assign narrow_video_mode = 1'b0;
    assign menu_active = 1'b0;
    assign sdram_clk = 1'b0;
    assign sdram_cke = 1'b0;
    assign sdram_cs_n = 1'b1;
    assign sdram_ras_n = 1'b1;
    assign sdram_cas_n = 1'b1;
    assign sdram_we_n = 1'b1;
    assign sdram_dqm = 2'b11;
    assign sdram_address = 13'b0;
    assign sdram_bank = 2'b0;
    assign sdram_data = 16'hzzzz;
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
    assign audio_dac = 7'd32;
    assign narrow_video_mode = 1'b0;
    assign menu_active = 1'b0;
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
`endif // HDMI_TEST_PATTERN

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
