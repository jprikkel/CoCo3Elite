`timescale 1ns/1ps
`default_nettype none

module coco3_boot_system #(
    parameter integer SOFT_RESET_GUARD_CLOCKS = 2499999,
    parameter integer CARTRIDGE_COLD_RESET_CLOCKS = 2519999
) (
    input wire pixel_clk, input wire memory_clk, input wire reset,
    input wire raster_resync,
    input wire [9:0] screen_x, input wire [9:0] screen_y,
    input wire ps2_clk, input wire ps2_data,
    input wire physical_joystick_up, input wire physical_joystick_down,
    input wire physical_joystick_left, input wire physical_joystick_right,
    input wire physical_joystick_button1,
    input wire physical_joystick_button2,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi,
    input wire sd_miso,
    input wire physical_floppy_present,
    input wire [2:0] physical_floppy_status,
    input wire [31:0] physical_floppy_index_count,
    input wire [31:0] physical_floppy_read_transition_count,
    output wire physical_floppy_motor_request,
    output wire physical_floppy_direction_request,
    output wire physical_floppy_side_select_request,
    output wire physical_floppy_step_request_toggle,
    output wire physical_floppy_home_request_toggle,
    output wire physical_floppy_abort_request_toggle,
    input wire physical_floppy_motor_active,
    input wire physical_floppy_home_active,
    input wire physical_floppy_home_done_toggle,
    input wire physical_floppy_home_success,
    input wire [7:0] physical_floppy_home_step_count,
    output wire hsync, output wire vsync, output wire video_enable,
    output wire [6:0] audio_dac,
    output wire narrow_video_mode,
    output wire menu_active,
    output wire uart_debug_tx, input wire uart_rx,
    output wire video_capture_request_toggle,
    output wire [2:0] video_capture_stripe,
    output wire [15:0] video_capture_read_address,
    input wire [7:0] video_capture_read_data,
    input wire video_capture_done_toggle, input wire video_capture_busy,
    output wire sdram_clk, output wire sdram_cke,
    output wire sdram_cs_n, output wire sdram_ras_n,
    output wire sdram_cas_n, output wire sdram_we_n,
    output wire [1:0] sdram_dqm,
    output wire [12:0] sdram_address,
    output wire [1:0] sdram_bank,
    inout wire [15:0] sdram_data,
    output wire [7:0] red, output wire [7:0] green, output wire [7:0] blue
);
    wire [15:0] cpu_address;
    wire [15:0] cpu_pc;
    wire cpu_vma;
    wire cpu_read;
    wire [7:0] cpu_read_data;
    wire io_write;
    wire [7:0] cpu_data;
    wire [7:0] debug_gime_init0, debug_gime_init1;
    wire [2:0] debug_memory_flags;
    wire [127:0] debug_mmu;
    wire [19:0] video_address;
    wire [15:0] video_data;
    wire [8:0] color;
    wire raw_hsync, raw_vsync, raw_video_enable;
    wire artifact_hsync, artifact_vsync, artifact_video_enable;
    wire [7:0] artifact_red, artifact_green, artifact_blue;
    reg [7:0] raw_red, raw_green, raw_blue;
    wire hblank, vblank, sync_flag;
    reg coco;
    reg [2:0] v;
    wire bp;
    reg [6:0] vert;
    wire [3:0] vid_cont;
    wire css;
    wire [2:0] lpr;
    wire hlpr;
    wire [1:0] lpf, cres;
    wire [3:0] hres, scroll;
    wire hven;
    wire [6:0] hor_offset;
    wire [1:0] start_hsb;
    wire [7:0] start_msb, start_lsb;
    wire [7:0] gime_video_mode;
    wire [7:0] gime_video_resolution;
    wire [15:0] gime_video_offset;
    wire [7:0] gime_horizontal_offset;
    wire artifact_compatible_mode = coco && (vid_cont == 4'b1111);
    wire [95:0] machine_palette;
    wire [5:0] border_palette;
    wire gime_blink;
    wire [5:0] palette [0:15];
    genvar palette_index;
    reg [3:0] direct_red, direct_green, direct_blue;
    integer i;

    wire [55:0] keyboard_keys;
    wire keyboard_shift;
    wire keyboard_shift_override;
    wire keyboard_reset;
    wire keyboard_f3;
    wire keyboard_f6;
    wire keyboard_f7;
    wire keyboard_f8;
    wire keyboard_f9;
    wire keyboard_f11;
    wire keyboard_f10;
    wire keyboard_f12;
    reg [1:0] keyboard_f6_sync;
    reg [1:0] keyboard_f7_sync;
    reg [1:0] keyboard_f10_sync;
    reg [1:0] keyboard_f8_sync;
    reg [1:0] keyboard_f9_sync;
    reg [1:0] keyboard_f11_sync;
    reg [1:0] keyboard_f12_sync;
    reg [1:0] keyboard_reset_sync;
    reg keyboard_reset_previous;
    reg keyboard_f6_previous;
    reg keyboard_f7_previous;
    reg cpu_fast_mode;
    // F8 cycles keyboard joystick emulation: 0=off, 1=left, 2=right.
    // Space and Ctrl drive the selected CoCo 3 port's genuine Button 1 and
    // Button 2 inputs, respectively.
    reg [1:0] keyboard_joystick_mode;
    // F7 selects which CoCo joystick port receives the physical J10 stick.
    // Reset defaults to the right port for compatibility with most games.
    reg physical_joystick_right_port;
    reg artifact_enabled;
    reg keyboard_f10_previous;
    reg keyboard_f8_previous;
    reg keyboard_f9_previous;
    reg scanlines_enabled;
    reg soft_reset_active;
    reg soft_reset_cold_start;
    reg [21:0] soft_reset_release_count;
    wire keyboard_reset_event = keyboard_reset_sync[1] &&
                                !keyboard_reset_previous;
    wire [55:0] manager_serial_keyboard_keys;
    wire manager_serial_keyboard_shift, manager_serial_keyboard_shift_override;
    wire [7:0] manager_serial_function_keys;
    wire manager_serial_cold_reset;
    wire manager_serial_trace_enable;
    wire manager_serial_trace_snapshot_toggle;
    wire [55:0] effective_keyboard_keys = keyboard_keys |
                                                manager_serial_keyboard_keys;
    wire soft_reset_keys_held = effective_keyboard_keys[51] ||
                                effective_keyboard_keys[52];
    wire system_reset = reset | soft_reset_active;
    // Clear the decoder's internal key and RESET latches as part of a soft
    // reset.  COCOKEY only updates RESET on a Delete scan code; without this
    // wrapper reset, releasing Ctrl or Alt before Delete can leave RESET high.
    wire keyboard_decoder_reset = reset | soft_reset_active;
    wire keyboard_joystick_enabled = keyboard_joystick_mode != 2'd0;
    wire keyboard_joystick_left = keyboard_joystick_mode == 2'd1;
    wire keyboard_joystick_right = keyboard_joystick_mode == 2'd2;
    wire [55:0] keyboard_joystick_mask = keyboard_joystick_enabled
        ? ((56'b1 << 27) | (56'b1 << 28) | (56'b1 << 29) |
           (56'b1 << 30) | (56'b1 << 31) | (56'b1 << 52)) : 56'b0;
    wire [55:0] machine_keyboard_keys = (soft_reset_active | menu_active) ? 56'b0 :
        (effective_keyboard_keys & ~keyboard_joystick_mask);
    wire machine_keyboard_shift = soft_reset_active ? 1'b0 :
        (keyboard_shift | manager_serial_keyboard_shift);
    wire machine_keyboard_shift_override = soft_reset_active ? 1'b0 :
        (keyboard_shift_override | manager_serial_keyboard_shift_override);
    wire joystick_left_only = effective_keyboard_keys[29] && !effective_keyboard_keys[30];
    wire joystick_right_only = effective_keyboard_keys[30] && !effective_keyboard_keys[29];
    wire joystick_up_only = effective_keyboard_keys[27] && !effective_keyboard_keys[28];
    wire joystick_down_only = effective_keyboard_keys[28] && !effective_keyboard_keys[27];
    // Gate J10 while the manager owns the display, then merge it with the
    // optional F8 keyboard mapping. F7 independently assigns J10 to the left
    // or right CoCo port. Opposing directions resolve to the centered value.
    wire physical_joystick_enabled = !soft_reset_active && !menu_active;
    wire physical_joystick_to_left =
        physical_joystick_enabled && !physical_joystick_right_port;
    wire physical_joystick_to_right =
        physical_joystick_enabled && physical_joystick_right_port;
    wire joystick_left_left =
        (keyboard_joystick_left && joystick_left_only) ||
        (physical_joystick_to_left && physical_joystick_left);
    wire joystick_left_right =
        (keyboard_joystick_left && joystick_right_only) ||
        (physical_joystick_to_left && physical_joystick_right);
    wire joystick_left_up =
        (keyboard_joystick_left && joystick_up_only) ||
        (physical_joystick_to_left && physical_joystick_up);
    wire joystick_left_down =
        (keyboard_joystick_left && joystick_down_only) ||
        (physical_joystick_to_left && physical_joystick_down);
    wire joystick_right_left =
        (keyboard_joystick_right && joystick_left_only) ||
        (physical_joystick_to_right && physical_joystick_left);
    wire joystick_right_right =
        (keyboard_joystick_right && joystick_right_only) ||
        (physical_joystick_to_right && physical_joystick_right);
    wire joystick_right_up =
        (keyboard_joystick_right && joystick_up_only) ||
        (physical_joystick_to_right && physical_joystick_up);
    wire joystick_right_down =
        (keyboard_joystick_right && joystick_down_only) ||
        (physical_joystick_to_right && physical_joystick_down);
    wire [5:0] joystick_left_x =
        joystick_left_left && !joystick_left_right ? 6'd0 :
        joystick_left_right && !joystick_left_left ? 6'd63 : 6'd32;
    wire [5:0] joystick_left_y =
        joystick_left_up && !joystick_left_down ? 6'd0 :
        joystick_left_down && !joystick_left_up ? 6'd63 : 6'd32;
    wire [5:0] joystick_right_x =
        joystick_right_left && !joystick_right_right ? 6'd0 :
        joystick_right_right && !joystick_right_left ? 6'd63 : 6'd32;
    wire [5:0] joystick_right_y =
        joystick_right_up && !joystick_right_down ? 6'd0 :
        joystick_right_down && !joystick_right_up ? 6'd63 : 6'd32;
    // The CoCo 3 adds a distinct second button to each six-pin joystick port.
    // F7 therefore moves both J10 buttons together without borrowing either
    // button input from the unselected port.
    wire joystick_left_fire =
        (keyboard_joystick_left && effective_keyboard_keys[31]) ||
        (physical_joystick_to_left && physical_joystick_button1);
    wire joystick_left_fire2 =
        (keyboard_joystick_left && effective_keyboard_keys[52]) ||
        (physical_joystick_to_left && physical_joystick_button2);
    wire joystick_right_fire =
        (keyboard_joystick_right && effective_keyboard_keys[31]) ||
        (physical_joystick_to_right && physical_joystick_button1);
    wire joystick_right_fire2 =
        (keyboard_joystick_right && effective_keyboard_keys[52]) ||
        (physical_joystick_to_right && physical_joystick_button2);
    // J=PBBDLRU in the UART trace: P is 1 for right/0 for left, followed by
    // button 2, button 1, and the four active-high contact states.
    wire [6:0] physical_joystick_debug =
        {physical_joystick_right_port, physical_joystick_button2,
         physical_joystick_button1, physical_joystick_right,
         physical_joystick_left, physical_joystick_down,
         physical_joystick_up};
    // The manager owns the SD pins and filesystem.  The CoCo sees only a
    // WD1773-like sector service, preserving Disk BASIC's normal protocol.
    wire manager_uart_tx, manager_uart_busy, manager_uart_claim;
    wire manager_ready, manager_done_toggle, manager_success;
    wire manager_write_done_toggle, manager_write_success;
    wire [2:0] manager_drive_present;
    wire [1:0] manager_fdc_drive;
    wire manager_fdc_side;
    wire [7:0] manager_fdc_track, manager_fdc_sector, manager_fdc_last_type1, manager_fdc_data,
               manager_fdc_data_address;
    wire [31:0] manager_fdc_debug_word;
    wire [31:0] manager_fdc_completed_debug_word;
    wire manager_fdc_read_complete_toggle;
    wire manager_fdc_write_strobe, manager_fdc_write_complete_toggle;
    wire [7:0] manager_fdc_write_data;
    wire manager_fdc_request_toggle;
    wire [14:0] manager_cartridge_address;
    wire [7:0] manager_cartridge_data;
    wire manager_cartridge_write, manager_cartridge_enabled, manager_cartridge_launch;
    wire [7:0] manager_bin_fifo_data;
    wire manager_bin_fifo_available, manager_bin_transfer_active;
    wire manager_bin_transfer_complete, manager_bin_transfer_error;
    wire machine_bin_fifo_pop, machine_bin_loader_done;
    localparam [2:0] CART_BOOT_IDLE       = 3'd0;
    localparam [2:0] CART_BOOT_RESET      = 3'd1;
    localparam [2:0] CART_BOOT_WAIT_START = 3'd2;
    localparam [2:0] CART_BOOT_WAIT_BASIC = 3'd3;
    localparam [2:0] CART_BOOT_LAUNCH     = 3'd4;
    reg [2:0] cartridge_boot_state;
    reg [21:0] cartridge_cold_reset_count;
    reg cartridge_session_active;
    wire cartridge_cold_reset = cartridge_boot_state == CART_BOOT_RESET;
    wire basic_idle = cpu_pc >= 16'ha7d3 && cpu_pc <= 16'ha7d7;
    wire effective_cartridge_launch =
        cartridge_boot_state == CART_BOOT_LAUNCH && !soft_reset_active;
    wire effective_cartridge_enabled = manager_cartridge_enabled &&
                                       !soft_reset_active &&
                                       (cartridge_session_active ||
                                        cartridge_boot_state == CART_BOOT_LAUNCH);
    wire machine_memory_ready;
    wire [31:0] machine_memory_debug_status;
    wire video_cache_miss;
    reg [19:0] previous_video_address;
    reg [11:0] frame_video_miss_count;
    reg [9:0] frame_last_miss_x, frame_last_miss_y;
    reg [31:0] completed_video_miss_status;
    wire machine_reset = system_reset | cartridge_cold_reset |
                         !machine_memory_ready;
    // Keep the GIME stopped until the first HDMI alignment pulse after each
    // machine reset, then let both rasters free-run from the same pixel clock.
    // Resetting the GIME on every transport frame creates a short invalid RGB
    // interval which appears later in narrow modes through their pixel delay.
    reg video_raster_wait;
    always @(posedge pixel_clk) begin
        if (machine_reset)
            video_raster_wait <= 1'b1;
        else if (video_raster_wait && raster_resync)
            video_raster_wait <= 1'b0;
    end
    wire video_core_reset = machine_reset | video_raster_wait;
    // Passive per-frame diagnostic: count distinct upper-RAM video addresses
    // requested before either line buffer contains their SDRAM block. The
    // position is the HDMI raster at the GIME fetch, ahead of RGB pipeline
    // delay. Keep a completed frame stable for the once-per-second UART trace.
    always @(posedge pixel_clk) begin
        if (reset) begin
            previous_video_address <= 0;
            frame_video_miss_count <= 0;
            frame_last_miss_x <= 0;
            frame_last_miss_y <= 0;
            completed_video_miss_status <= 0;
        end else begin
            previous_video_address <= video_address;
            if (screen_x == 0 && screen_y == 0) begin
                completed_video_miss_status <= {frame_video_miss_count,
                    frame_last_miss_x, frame_last_miss_y};
                frame_video_miss_count <= 0;
                frame_last_miss_x <= 0;
                frame_last_miss_y <= 0;
            end else if (!video_core_reset && !menu_active && !hblank &&
                         !vblank && screen_x < 10'd640 &&
                         screen_y < 10'd480 && video_cache_miss &&
                         video_address != previous_video_address) begin
                if (frame_video_miss_count != 12'hfff)
                    frame_video_miss_count <= frame_video_miss_count + 1'b1;
                frame_last_miss_x <= screen_x;
                frame_last_miss_y <= screen_y;
            end
        end
    end
    wire [10:0] manager_osd_char_address;
    wire [7:0] manager_osd_char_data;
    wire [11:0] manager_osd_preview_read_address;
    wire [31:0] manager_osd_preview_read_data;
    wire manager_osd_preview_active;
    wire [127:0] manager_osd_preview_palette;
    wire [4:0] manager_osd_selected_row;
    wire manager_osd_active;
    wire manager_osd_narrow_selection;
    wire manager_osd_option_selection;
    wire [1:0] manager_osd_font_style;
    wire [2:0] manager_artifact_mode;
    wire [1:0] manager_artifact_palette;
    wire [3:0] manager_coco2_palette;
    wire [3:0] manager_text_color_theme;
    wire [9:0] manager_menu_key_state = {
        effective_keyboard_keys[52], effective_keyboard_keys[49],
        effective_keyboard_keys[30], effective_keyboard_keys[29], keyboard_f11_sync[1],
        effective_keyboard_keys[50], effective_keyboard_keys[48], effective_keyboard_keys[28],
        effective_keyboard_keys[27], keyboard_f12_sync[1]};
    wire [7:0] sd_status = {4'b1010, manager_ready, manager_drive_present};
    wire [7:0] sd_detail = {5'b0, manager_drive_present};
    wire coco_uart_debug_tx;
    wire machine_sdram_clk, machine_sdram_cke, machine_sdram_cs_n;
    wire machine_sdram_ras_n, machine_sdram_cas_n, machine_sdram_we_n;
    wire [1:0] machine_sdram_dqm;
    wire [12:0] machine_sdram_address;
    wire [1:0] machine_sdram_bank;
    wire [15:0] machine_sdram_data;
    wire manager_sdram_clk, manager_sdram_cke, manager_sdram_cs_n;
    wire manager_sdram_ras_n, manager_sdram_cas_n, manager_sdram_we_n;
    wire [1:0] manager_sdram_dqm;
    wire [12:0] manager_sdram_address;
    wire [1:0] manager_sdram_bank;
    wire [15:0] manager_sdram_data;
    wire shared_disk_write, shared_disk_write_ready, shared_disk_write_idle;
    wire [19:0] shared_disk_write_address, shared_disk_sector_base_address;
    wire [7:0] shared_disk_write_data, shared_disk_sector_read_data;
    wire shared_disk_sector_request_toggle, shared_disk_sector_done_toggle;

    ultraembedded_manager_sd_mount manager_i (
        .clock(pixel_clk), .memory_clock(memory_clk), .reset(reset),
        .uart_tx(manager_uart_tx), .uart_busy(manager_uart_busy),
        .uart_claim(manager_uart_claim),
        .uart_rx(uart_rx),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .fdc_drive(manager_fdc_drive), .fdc_side(manager_fdc_side),
        .fdc_track(manager_fdc_track),
        .fdc_sector(manager_fdc_sector), .fdc_request_toggle(manager_fdc_request_toggle),
        .fdc_last_type1(manager_fdc_last_type1),
        .fdc_debug_word(manager_fdc_debug_word), .fdc_read_complete_toggle(manager_fdc_read_complete_toggle),
        .fdc_completed_debug_word(manager_fdc_completed_debug_word),
        .fdc_write_complete_toggle(manager_fdc_write_complete_toggle),
        .fdc_buffer_address(manager_fdc_data_address), .fdc_buffer_data(manager_fdc_data),
        .fdc_write_strobe(manager_fdc_write_strobe), .fdc_write_data(manager_fdc_write_data),
        .menu_key_state(manager_menu_key_state),
        .osd_char_address(manager_osd_char_address),
        .osd_char_data(manager_osd_char_data),
        .osd_preview_read_address(manager_osd_preview_read_address),
        .osd_preview_read_data(manager_osd_preview_read_data),
        .osd_preview_active(manager_osd_preview_active),
        .osd_preview_palette(manager_osd_preview_palette),
        .osd_active(manager_osd_active),
        .osd_selected_row(manager_osd_selected_row),
        .osd_narrow_selection(manager_osd_narrow_selection),
        .osd_option_selection(manager_osd_option_selection),
        .osd_font_style(manager_osd_font_style),
        .artifact_mode(manager_artifact_mode),
        .artifact_palette(manager_artifact_palette),
        .coco2_palette(manager_coco2_palette),
        .text_color_theme(manager_text_color_theme),
        .serial_keyboard_keys(manager_serial_keyboard_keys),
        .serial_keyboard_shift(manager_serial_keyboard_shift),
        .serial_keyboard_shift_override(manager_serial_keyboard_shift_override),
        .serial_function_keys(manager_serial_function_keys),
        .serial_cold_reset(manager_serial_cold_reset),
        .serial_trace_enable(manager_serial_trace_enable),
        .serial_trace_snapshot_toggle(
            manager_serial_trace_snapshot_toggle),
        .debug_cpu_pc(cpu_pc), .debug_gime_init0(debug_gime_init0),
        .debug_gime_init1(debug_gime_init1),
        .debug_video_mode(gime_video_mode),
        .debug_video_resolution(gime_video_resolution),
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
        .physical_floppy_motor_active(physical_floppy_motor_active),
        .physical_floppy_home_active(physical_floppy_home_active),
        .physical_floppy_home_done_toggle(physical_floppy_home_done_toggle),
        .physical_floppy_home_success(physical_floppy_home_success),
        .physical_floppy_home_step_count(physical_floppy_home_step_count),
        .video_capture_request_toggle(video_capture_request_toggle),
        .video_capture_stripe(video_capture_stripe),
        .video_capture_read_address(video_capture_read_address),
        .video_capture_read_data(video_capture_read_data),
        .video_capture_done_toggle(video_capture_done_toggle),
        .video_capture_busy(video_capture_busy),
        .fdc_done_toggle(manager_done_toggle), .fdc_success(manager_success),
        .fdc_write_done_toggle(manager_write_done_toggle), .fdc_write_success(manager_write_success),
        .fdc_present(manager_drive_present), .manager_ready(manager_ready)
        ,.cartridge_address(manager_cartridge_address), .cartridge_data(manager_cartridge_data),
        .cartridge_write(manager_cartridge_write), .cartridge_enabled(manager_cartridge_enabled),
        .cartridge_launch(manager_cartridge_launch),
        .bin_fifo_pop(machine_bin_fifo_pop), .bin_loader_done(machine_bin_loader_done),
        .bin_cancel(soft_reset_active), .bin_fifo_data(manager_bin_fifo_data),
        .bin_fifo_available(manager_bin_fifo_available),
        .bin_transfer_active(manager_bin_transfer_active),
        .bin_transfer_complete(manager_bin_transfer_complete),
        .bin_transfer_error(manager_bin_transfer_error),
        .shared_disk_write(shared_disk_write),
        .shared_disk_write_address(shared_disk_write_address),
        .shared_disk_write_data(shared_disk_write_data),
        .shared_disk_write_ready(shared_disk_write_ready),
        .shared_disk_write_idle(shared_disk_write_idle),
        .shared_disk_sector_request_toggle(shared_disk_sector_request_toggle),
        .shared_disk_sector_base_address(shared_disk_sector_base_address),
        .shared_disk_sector_read_data(shared_disk_sector_read_data),
        .shared_disk_sector_done_toggle(shared_disk_sector_done_toggle),
        .shared_disk_ready(machine_memory_ready),
        .sdram_clk(manager_sdram_clk), .sdram_cke(manager_sdram_cke),
        .sdram_cs_n(manager_sdram_cs_n),
        .sdram_ras_n(manager_sdram_ras_n),
        .sdram_cas_n(manager_sdram_cas_n),
        .sdram_we_n(manager_sdram_we_n),
        .sdram_dqm(manager_sdram_dqm),
        .sdram_address(manager_sdram_address),
        .sdram_bank(manager_sdram_bank),
        .sdram_data(manager_sdram_data)
    );

`ifdef WUKONG_HYBRID_512K
    // One controller arbitrates upper CoCo RAM, video prefetch and disk cache.
    // The manager never drives the board SDRAM pins directly in this build.
    assign sdram_clk = machine_sdram_clk;
    assign sdram_cke = machine_sdram_cke;
    assign sdram_cs_n = machine_sdram_cs_n;
    assign sdram_ras_n = machine_sdram_ras_n;
    assign sdram_cas_n = machine_sdram_cas_n;
    assign sdram_we_n = machine_sdram_we_n;
    assign sdram_dqm = machine_sdram_dqm;
    assign sdram_address = machine_sdram_address;
    assign sdram_bank = machine_sdram_bank;
`else
    assign sdram_clk = manager_sdram_clk;
    assign sdram_cke = manager_sdram_cke;
    assign sdram_cs_n = manager_sdram_cs_n;
    assign sdram_ras_n = manager_sdram_ras_n;
    assign sdram_cas_n = manager_sdram_cas_n;
    assign sdram_we_n = manager_sdram_we_n;
    assign sdram_dqm = manager_sdram_dqm;
    assign sdram_address = manager_sdram_address;
    assign sdram_bank = manager_sdram_bank;
`ifdef COCO3_BOOT_SIM
    // The boot regression does not exercise external SDRAM. Avoid Vivado
    // Simulator's unsupported bidirectional tran primitive in this one model.
    assign manager_sdram_data = 16'hzzzz;
    assign sdram_data = 16'hzzzz;
`else
    tran manager_sdram_bus[15:0](sdram_data, manager_sdram_data);
`endif
`endif

    // The SD manager intentionally survives both Ctrl-Alt-Delete and a
    // cartridge power cycle, preserving mounted disks and dirty-cache
    // ownership.  A real ROM-Pak is installed with power off, so an F12
    // selection is staged as the same operation: isolate the old cartridge,
    // cold-reset only the CoCo, wait for the system ROM's initialized BASIC
    // loop, and only then map the verified image and present its CART edge.
    // This prevents a second selection from injecting FIRQ into arbitrary
    // game state.
    always @(posedge pixel_clk) begin
        if (reset || soft_reset_active) begin
            cartridge_boot_state <= CART_BOOT_IDLE;
            cartridge_cold_reset_count <= 22'd0;
            cartridge_session_active <= 1'b0;
        end else if (!manager_cartridge_enabled) begin
            cartridge_boot_state <= CART_BOOT_IDLE;
            cartridge_cold_reset_count <= 22'd0;
            cartridge_session_active <= 1'b0;
        end else begin
            case (cartridge_boot_state)
                CART_BOOT_IDLE: begin
                    if (manager_cartridge_launch) begin
                        cartridge_boot_state <= CART_BOOT_RESET;
                        cartridge_cold_reset_count <= 22'd0;
                        cartridge_session_active <= 1'b0;
                    end
                end
                CART_BOOT_RESET: begin
                    if (cartridge_cold_reset_count < CARTRIDGE_COLD_RESET_CLOCKS)
                        cartridge_cold_reset_count <= cartridge_cold_reset_count + 1'b1;
                    else if (!menu_active) begin
                        // debug_pc can retain its pre-reset $A7D5 value for
                        // several clocks while the 6809 reset pipeline starts.
                        // Require visible departure from the BASIC idle loop
                        // before accepting a later return as completed boot.
                        cartridge_boot_state <= CART_BOOT_WAIT_START;
                        cartridge_cold_reset_count <= 22'd0;
                    end
                end
                CART_BOOT_WAIT_START: begin
                    if (!basic_idle)
                        cartridge_boot_state <= CART_BOOT_WAIT_BASIC;
                end
                CART_BOOT_WAIT_BASIC: begin
                    if (basic_idle)
                        cartridge_boot_state <= CART_BOOT_LAUNCH;
                end
                CART_BOOT_LAUNCH: begin
                    cartridge_boot_state <= CART_BOOT_IDLE;
                    cartridge_session_active <= 1'b1;
                end
                default: begin
                    cartridge_boot_state <= CART_BOOT_IDLE;
                    cartridge_session_active <= 1'b0;
                end
            endcase
        end
    end
`ifdef COCO3_CPU_UART_DEBUG
    // A cartridge launch is followed immediately by CoCo-side execution
    // diagnostics. Keep the pin with that trace for the entire cartridge
    // session: switching sources mid-character corrupts both UART lines.
    // Before a cartridge is active, retain firmware/menu status output.
    assign uart_debug_tx = (manager_uart_claim || manager_uart_busy)
        ? manager_uart_tx : coco_uart_debug_tx;
`else
    // Control build: remove the CPU/MMU tracer entirely. The manager UART
    // remains available, but it cannot share the pin with a CoCo trace.
    assign uart_debug_tx = (manager_uart_claim || manager_uart_busy)
        ? manager_uart_tx : 1'b1;
`endif

    COCOKEY keyboard_i (
        .RESET_N(~keyboard_decoder_reset),
        .CLK50MHZ(pixel_clk),
        .SLO_CLK(pixel_clk),
        .PS2_CLK(ps2_clk),
        .PS2_DATA(ps2_data),
        .KEY(keyboard_keys),
        .SHIFT(keyboard_shift),
        .SHIFT_OVERRIDE(keyboard_shift_override),
        .F3(keyboard_f3),
        .F6(keyboard_f6),
        .F7(keyboard_f7),
        .F8(keyboard_f8),
        .F9(keyboard_f9),
        .F10(keyboard_f10),
        .F11(keyboard_f11),
        .F12(keyboard_f12),
        .RESET(keyboard_reset)
    );

    // Function keys are decoded in the divided keyboard clock domain.
    // Synchronize their levels and toggle each feature once per make edge.
    always @(posedge pixel_clk) begin
        if (reset) begin
            keyboard_f6_sync <= 2'b00;
            keyboard_f7_sync <= 2'b00;
            keyboard_f11_sync <= 2'b00;
            keyboard_f12_sync <= 2'b00;
            keyboard_f10_sync <= 2'b00;
            keyboard_f8_sync <= 2'b00;
            keyboard_f9_sync <= 2'b00;
            keyboard_reset_sync <= 2'b00;
            keyboard_reset_previous <= 1'b0;
            keyboard_f6_previous <= 1'b0;
            keyboard_f7_previous <= 1'b0;
            cpu_fast_mode <= 1'b0;
            keyboard_joystick_mode <= 2'd0;
            physical_joystick_right_port <= 1'b1;
            artifact_enabled <= 1'b1;
            keyboard_f10_previous <= 1'b0;
            keyboard_f8_previous <= 1'b0;
            keyboard_f9_previous <= 1'b0;
            scanlines_enabled <= 1'b0;
        end else begin
            keyboard_f6_sync <= {keyboard_f6_sync[0], keyboard_f6 | manager_serial_function_keys[1]};
            keyboard_f7_sync <= {keyboard_f7_sync[0], keyboard_f7 | manager_serial_function_keys[2]};
            keyboard_f11_sync <= {keyboard_f11_sync[0], keyboard_f11 | manager_serial_function_keys[6]};
            keyboard_f12_sync <= {keyboard_f12_sync[0], keyboard_f12 | manager_serial_function_keys[7]};
            keyboard_f10_sync <= {keyboard_f10_sync[0], keyboard_f10 | manager_serial_function_keys[5]};
            keyboard_f8_sync <= {keyboard_f8_sync[0], keyboard_f8 | manager_serial_function_keys[3]};
            keyboard_f9_sync <= {keyboard_f9_sync[0], keyboard_f9 | manager_serial_function_keys[4]};
            keyboard_reset_sync <= {keyboard_reset_sync[0], keyboard_reset};
            keyboard_reset_previous <= keyboard_reset_sync[1];
            keyboard_f6_previous <= keyboard_f6_sync[1];
            keyboard_f7_previous <= keyboard_f7_sync[1];
            keyboard_f10_previous <= keyboard_f10_sync[1];
            keyboard_f8_previous <= keyboard_f8_sync[1];
            keyboard_f9_previous <= keyboard_f9_sync[1];
            if (keyboard_reset_sync[1])
                artifact_enabled <= 1'b1;
            else if (keyboard_f10_sync[1] && !keyboard_f10_previous)
                artifact_enabled <= ~artifact_enabled;
            if (keyboard_f6_sync[1] && !keyboard_f6_previous)
                cpu_fast_mode <= ~cpu_fast_mode;
            if (keyboard_f7_sync[1] && !keyboard_f7_previous)
                physical_joystick_right_port <= ~physical_joystick_right_port;
            if (keyboard_f8_sync[1] && !keyboard_f8_previous)
                keyboard_joystick_mode <= keyboard_joystick_mode == 2'd2
                    ? 2'd0 : keyboard_joystick_mode + 1'b1;
            if (keyboard_f9_sync[1] && !keyboard_f9_previous)
                scanlines_enabled <= ~scanlines_enabled;
        end
    end

    // Ctrl+Alt+Delete is also the CoCo 3 Easter-egg chord. Keep the emulated
    // machine in reset until the modifiers have been released, then provide a
    // short key-free guard interval. Release only on the next raster alignment
    // pulse so the reset raster and the HDMI library raster start together.
    always @(posedge pixel_clk) begin
        if (reset) begin
            soft_reset_active <= 1'b0;
            soft_reset_cold_start <= 1'b0;
            soft_reset_release_count <= 22'd0;
        end else if (keyboard_reset_event || manager_serial_cold_reset) begin
            soft_reset_active <= 1'b1;
            soft_reset_cold_start <= manager_serial_cold_reset;
            soft_reset_release_count <= 22'd0;
        end else if (soft_reset_active) begin
            if (soft_reset_keys_held) begin
                soft_reset_release_count <= 22'd0;
            end else if (soft_reset_release_count == SOFT_RESET_GUARD_CLOCKS &&
                         raster_resync) begin
                soft_reset_active <= 1'b0;
                soft_reset_cold_start <= 1'b0;
                soft_reset_release_count <= 22'd0;
            end else if (soft_reset_release_count == SOFT_RESET_GUARD_CLOCKS) begin
                // Saturate after the key-release guard interval.  The HDMI
                // frame pulse is only one pixel clock wide and may arrive
                // after this counter reaches its terminal value.
                soft_reset_release_count <= soft_reset_release_count;
            end else begin
                soft_reset_release_count <= soft_reset_release_count + 1'b1;
            end
        end
    end

    coco3_boot_machine machine_i (
        .clock(pixel_clk), .reset(machine_reset),
        .memory_clock(memory_clk), .memory_reset(reset),
        .memory_ready(machine_memory_ready),
        .memory_debug_status(machine_memory_debug_status),
        .video_cache_miss(video_cache_miss),
        .disk_cache_write(shared_disk_write),
        .disk_cache_write_address(shared_disk_write_address),
        .disk_cache_write_data(shared_disk_write_data),
        .disk_cache_write_ready(shared_disk_write_ready),
        .disk_cache_write_idle(shared_disk_write_idle),
        .disk_sector_request_toggle(shared_disk_sector_request_toggle),
        .disk_sector_base_address(shared_disk_sector_base_address),
        .disk_sector_read_address(manager_fdc_data_address),
        .disk_sector_read_data(shared_disk_sector_read_data),
        .disk_sector_done_toggle(shared_disk_sector_done_toggle),
        .sdram_clk(machine_sdram_clk), .sdram_cke(machine_sdram_cke),
        .sdram_cs_n(machine_sdram_cs_n),
        .sdram_ras_n(machine_sdram_ras_n),
        .sdram_cas_n(machine_sdram_cas_n),
        .sdram_we_n(machine_sdram_we_n),
        .sdram_dqm(machine_sdram_dqm),
        .sdram_address(machine_sdram_address),
        .sdram_bank(machine_sdram_bank),
`ifdef WUKONG_HYBRID_512K
        .sdram_data(sdram_data),
`else
        .sdram_data(machine_sdram_data),
`endif
        .debug_address(cpu_address),
        .debug_pc(cpu_pc),
        .cpu_fast_mode(cpu_fast_mode),
        .cartridge_enabled(effective_cartridge_enabled),
        .cartridge_launch(effective_cartridge_launch),
        .cartridge_address(manager_cartridge_address), .cartridge_write_data(manager_cartridge_data),
        .cartridge_write(manager_cartridge_write),
        .cold_start_clear(cartridge_cold_reset |
                          (soft_reset_active && soft_reset_cold_start)),
        .bin_fifo_data(manager_bin_fifo_data),
        .bin_fifo_available(manager_bin_fifo_available),
        .bin_transfer_active(manager_bin_transfer_active),
        .bin_transfer_complete(manager_bin_transfer_complete),
        .bin_transfer_error(manager_bin_transfer_error),
        .bin_fifo_pop(machine_bin_fifo_pop),
        .bin_loader_done(machine_bin_loader_done),
        // UART ownership is asserted for the complete multi-stripe screen
        // transfer. Halt the 6809 so all eight stripes describe one instant.
        .cpu_halt(menu_active | manager_uart_claim),
        .debug_vma(cpu_vma), .debug_read(cpu_read),
        .debug_opfetch(), .debug_read_data(cpu_read_data),
        .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(cpu_data),
        .debug_gime_init0(debug_gime_init0),
        .debug_gime_init1(debug_gime_init1),
        .debug_memory_flags(debug_memory_flags), .debug_mmu(debug_mmu),
        .keyboard_keys(machine_keyboard_keys),
        .keyboard_shift(machine_keyboard_shift),
        .keyboard_shift_override(machine_keyboard_shift_override),
        .joystick_left_x(joystick_left_x),
        .joystick_left_y(joystick_left_y),
        .joystick_left_fire(joystick_left_fire),
        .joystick_left_fire2(joystick_left_fire2),
        .joystick_right_x(joystick_right_x),
        .joystick_right_y(joystick_right_y),
        .joystick_right_fire(joystick_right_fire),
        .joystick_right_fire2(joystick_right_fire2),
        .sd_status(sd_status), .sd_detail(sd_detail),
        .sd_drive_present(manager_drive_present),
        .sd_fdc_done_toggle(manager_done_toggle), .sd_fdc_success(manager_success),
        .sd_fdc_write_done_toggle(manager_write_done_toggle), .sd_fdc_write_success(manager_write_success),
        .sd_fdc_data(manager_fdc_data), .sd_fdc_buffer_address(manager_fdc_data_address),
        .sd_fdc_drive(manager_fdc_drive), .sd_fdc_side(manager_fdc_side),
        .sd_fdc_track(manager_fdc_track),
        .sd_fdc_sector(manager_fdc_sector), .sd_fdc_last_type1(manager_fdc_last_type1),
        .sd_fdc_debug_word(manager_fdc_debug_word), .sd_fdc_read_complete_toggle(manager_fdc_read_complete_toggle), .sd_fdc_request_toggle(manager_fdc_request_toggle),
        .sd_fdc_completed_debug_word(manager_fdc_completed_debug_word),
        .sd_fdc_write_strobe(manager_fdc_write_strobe), .sd_fdc_write_data(manager_fdc_write_data),
        .sd_fdc_write_complete_toggle(manager_fdc_write_complete_toggle),
        // COCO3VIDEO renders doubled scanlines.  The original CoCo3FPGA
        // hardware gated PIA0 CA1 with SYNC_FLAG so legacy software receives
        // the CoCo's ~15.7 kHz horizontal interrupt rather than every
        // ~31 kHz output line.  GIME/video events continue to use raw_hsync.
        // The SDRAM remains live across CoCo cold resets. Treat the interval
        // while the video core is held in reset as blanking so accumulated
        // refreshes are serviced instead of waiting for emergency debt.
        .video_hsync(raw_hsync),
        .video_hblank(hblank | vblank | machine_reset),
        .pia_hsync(raw_hsync | ~sync_flag),
        .video_vsync(raw_vsync),
        .video_address(video_address), .video_read_data(video_data),
        .audio_dac(audio_dac), .video_vdg_control(vid_cont),
        .video_css(css), .video_palette(machine_palette),
        .video_border_palette(border_palette),
        .video_mode(gime_video_mode),
        .video_resolution(gime_video_resolution),
        .video_vbank(start_hsb), .video_scroll(scroll),
        .video_offset(gime_video_offset),
        .video_horizontal_offset(gime_horizontal_offset),
        .video_blink(gime_blink)
    );

    assign bp = gime_video_mode[7];
    assign hres = {gime_video_mode[6], gime_video_resolution[4:2]};
    assign lpr = gime_video_mode[2:0];
    assign hlpr = gime_video_resolution[7];
    assign lpf = gime_video_resolution[6:5];
    assign cres = gime_video_resolution[1:0];
    assign start_msb = gime_video_offset[15:8];
    assign start_lsb = gime_video_offset[7:0];
    assign hven = gime_horizontal_offset[7];
    assign hor_offset = gime_horizontal_offset[6:0];

`ifdef COCO3_CPU_UART_DEBUG
    coco3_uart_debug uart_debug_i (
        .clock(pixel_clk), .reset(machine_reset), .cpu_address(cpu_address),
        .trace_periodic_enable(manager_serial_trace_enable),
        .trace_snapshot_toggle(manager_serial_trace_snapshot_toggle),
        .cpu_pc(cpu_pc),
        .cpu_vma(cpu_vma), .cpu_read(cpu_read),
        .cpu_read_data(cpu_read_data), .cpu_write_data(cpu_data),
        .keyboard_active(|keyboard_keys),
        .cartridge_enabled(effective_cartridge_enabled),
        .sd_status(sd_status),
        .video_state({gime_video_mode,gime_video_resolution,{6'b0,start_hsb},
                      gime_video_offset,gime_horizontal_offset,machine_palette,video_data}),
        .gime_init0(debug_gime_init0), .gime_init1(debug_gime_init1),
        .memory_flags(debug_memory_flags), .mmu_state(debug_mmu),
        .sdram_debug_status(machine_memory_debug_status),
        .video_cache_miss_status(completed_video_miss_status),
        .physical_joystick_state(physical_joystick_debug),
        .uart_tx_o(coco_uart_debug_tx)
    );
`endif

    generate
        for (palette_index = 0; palette_index < 16; palette_index = palette_index + 1) begin : expand_palette
            assign palette[palette_index] = machine_palette[palette_index*6 +: 6];
        end
    endgenerate

    always @(posedge pixel_clk) begin
        if (machine_reset) begin
            coco <= 0; v <= 0; vert <= 0;
        end else if (io_write) begin
            case (cpu_address)
                16'hFF90: coco <= cpu_data[7];
                16'hFFC0: v[0] <= 1'b0;
                16'hFFC1: v[0] <= 1'b1;
                16'hFFC2: v[1] <= 1'b0;
                16'hFFC3: v[1] <= 1'b1;
                16'hFFC4: v[2] <= 1'b0;
                16'hFFC5: v[2] <= 1'b1;
                16'hFFC6: vert[0] <= 1'b0;
                16'hFFC7: vert[0] <= 1'b1;
                16'hFFC8: vert[1] <= 1'b0;
                16'hFFC9: vert[1] <= 1'b1;
                16'hFFCA: vert[2] <= 1'b0;
                16'hFFCB: vert[2] <= 1'b1;
                16'hFFCC: vert[3] <= 1'b0;
                16'hFFCD: vert[3] <= 1'b1;
                16'hFFCE: vert[4] <= 1'b0;
                16'hFFCF: vert[4] <= 1'b1;
                16'hFFD0: vert[5] <= 1'b0;
                16'hFFD1: vert[5] <= 1'b1;
                16'hFFD2: vert[6] <= 1'b0;
                16'hFFD3: vert[6] <= 1'b1;
                default: begin end
            endcase
        end
    end

    COCO3VIDEO video_i (
        .PIX_CLK(pixel_clk), .RESET_N(~video_core_reset),
        .COLOR(color), .HSYNC(raw_hsync),
        .SYNC_FLAG(sync_flag), .VSYNC(raw_vsync), .HBLANKING(hblank),
        .VBLANKING(vblank), .RAM_ADDRESS(video_address), .RAM_DATA(video_data),
        .VIDEO_ACTIVE(raw_video_enable),
        .COCO(coco), .V(v), .BP(bp), .VERT(vert), .VID_CONT(vid_cont), .CSS(css),
        .LPF(lpf), .VERT_FIN_SCRL(scroll), .HLPR(hlpr), .LPR(lpr), .HRES(hres),
        .CRES(cres), .HVEN(hven), .HOR_OFFSET(hor_offset),
        .SCRN_START_HSB(start_hsb), .SCRN_START_MSB(start_msb),
        .SCRN_START_LSB(start_lsb), .BLINK(gime_blink), .SWITCH5(1'b0)
    );

    // User-selectable text themes apply only to the MC6847-compatible alpha
    // screen.  They recolor the two text slots and border after emulation;
    // CoCo/GIME palette registers and display RAM remain untouched.
    function [23:0] text_theme_rgb;
        input [3:0] theme;
        input [1:0] role; // 0 background, 1 text, 2 border
        begin
            case (theme)
                4'd1: case (role) // C64
                    2'd0: text_theme_rgb=24'h40318d;
                    2'd1: text_theme_rgb=24'hb8afe8;
                    default: text_theme_rgb=24'h7869c4;
                endcase
                4'd2: case (role) // Atari
                    2'd0: text_theme_rgb=24'h183060;
                    2'd1: text_theme_rgb=24'hd8d8b0;
                    default: text_theme_rgb=24'h101820;
                endcase
                4'd3: case (role) // VT100
                    2'd0: text_theme_rgb=24'h041008;
                    2'd1: text_theme_rgb=24'ha0d8a0;
                    default: text_theme_rgb=24'h081808;
                endcase
                4'd4: case (role) // VT220 amber
                    2'd0: text_theme_rgb=24'h100c04;
                    2'd1: text_theme_rgb=24'hffb850;
                    default: text_theme_rgb=24'h201408;
                endcase
                4'd5: case (role) // VT220 green
                    2'd0: text_theme_rgb=24'h041008;
                    2'd1: text_theme_rgb=24'h70e890;
                    default: text_theme_rgb=24'h082010;
                endcase
                4'd6: case (role) // IBM PC/DOS
                    2'd0: text_theme_rgb=24'h0000aa;
                    2'd1: text_theme_rgb=24'hffffff;
                    default: text_theme_rgb=24'h000055;
                endcase
                4'd7: case (role) // Apple II green monitor
                    2'd0: text_theme_rgb=24'h000000;
                    2'd1: text_theme_rgb=24'h40ff40;
                    default: text_theme_rgb=24'h001800;
                endcase
                4'd8: case (role) // Amstrad CPC
                    2'd0: text_theme_rgb=24'h000080;
                    2'd1: text_theme_rgb=24'hffff00;
                    default: text_theme_rgb=24'h000040;
                endcase
                default: case (role) // Paperwhite
                    2'd0: text_theme_rgb=24'he8e0c8;
                    2'd1: text_theme_rgb=24'h181818;
                    default: text_theme_rgb=24'h807860;
                endcase
            endcase
        end
    endfunction
    wire coco_alpha_text = coco && !vid_cont[3] && !color[8];
    wire coco_alpha_text_color = color[3:0] == 4'hc ||
                                 color[3:0] == 4'hd ||
                                 color[3:0] == 4'he ||
                                 color[3:0] == 4'hf;
    wire [1:0] text_theme_role = color[4] ? 2'd2 :
                                  ((color[3:0] == 4'hc ||
                                    color[3:0] == 4'he) ? 2'd1 : 2'd0);
    wire [23:0] selected_text_rgb =
        text_theme_rgb(manager_text_color_theme, text_theme_role);

    always @* begin
        if (manager_text_color_theme != 0 && coco_alpha_text &&
            (color[4] || coco_alpha_text_color)) begin
            raw_red=selected_text_rgb[23:16];
            raw_green=selected_text_rgb[15:8];
            raw_blue=selected_text_rgb[7:0];
        end else if (coco && !artifact_compatible_mode && manager_coco2_palette != 0 &&
            !color[8] && !color[4]) begin
            // Optional CoCo 2/MC6847 themes are a display-only replacement
            // for the four logical VDG colors. They never alter GIME palette
            // registers, native CoCo 3 modes, or the border color.
            case (manager_coco2_palette)
                4'd1: case (color[1:0]) // Base: requested semantic remap
                    2'd0: begin raw_red=8'h00;raw_green=8'h00;raw_blue=8'h00;end
                    2'd1: begin raw_red=8'hc4;raw_green=8'h8a;raw_blue=8'h52;end
                    2'd2: begin raw_red=8'h78;raw_green=8'h3c;raw_blue=8'h18;end
                    default: begin raw_red=8'h18;raw_green=8'h68;raw_blue=8'h28;end
                endcase
                4'd2: case (color[1:0]) // C64 green/yellow/blue/red
                    2'd0: begin raw_red=8'h58;raw_green=8'h8d;raw_blue=8'h43;end
                    2'd1: begin raw_red=8'hb8;raw_green=8'hc7;raw_blue=8'h6f;end
                    2'd2: begin raw_red=8'h35;raw_green=8'h28;raw_blue=8'h79;end
                    default: begin raw_red=8'h68;raw_green=8'h37;raw_blue=8'h2b;end
                endcase
                4'd3: case (color[1:0]) // Atari green/yellow/blue/red
                    2'd0: begin raw_red=8'h48;raw_green=8'h98;raw_blue=8'h48;end
                    2'd1: begin raw_red=8'he8;raw_green=8'hd8;raw_blue=8'h78;end
                    2'd2: begin raw_red=8'h40;raw_green=8'h40;raw_blue=8'hc0;end
                    default: begin raw_red=8'hd8;raw_green=8'h28;raw_blue=8'h00;end
                endcase
                4'd4: case (color[1:0]) // CGA-inspired
                    2'd0: begin raw_red=8'h10;raw_green=8'h10;raw_blue=8'h10;end
                    2'd1: begin raw_red=8'h40;raw_green=8'hc8;raw_blue=8'hd0;end
                    2'd2: begin raw_red=8'hd0;raw_green=8'h50;raw_blue=8'ha0;end
                    default: begin raw_red=8'he8;raw_green=8'he8;raw_blue=8'he0;end
                endcase
                4'd5: case (color[1:0]) // Earth
                    2'd0: begin raw_red=8'h00;raw_green=8'h00;raw_blue=8'h00;end
                    2'd1: begin raw_red=8'h78;raw_green=8'h3c;raw_blue=8'h18;end
                    2'd2: begin raw_red=8'h18;raw_green=8'h68;raw_blue=8'h28;end
                    default: begin raw_red=8'hb8;raw_green=8'h28;raw_blue=8'h20;end
                endcase
                4'd6: case (color[1:0]) // Amber
                    2'd0: begin raw_red=8'h00;raw_green=8'h00;raw_blue=8'h00;end
                    2'd1: begin raw_red=8'h58;raw_green=8'h30;raw_blue=8'h00;end
                    2'd2: begin raw_red=8'hd0;raw_green=8'h90;raw_blue=8'h20;end
                    default: begin raw_red=8'hff;raw_green=8'hdf;raw_blue=8'h80;end
                endcase
                4'd7: case (color[1:0]) // Cool adventure
                    2'd0: begin raw_red=8'h10;raw_green=8'h18;raw_blue=8'h20;end
                    2'd1: begin raw_red=8'h28;raw_green=8'h50;raw_blue=8'h80;end
                    2'd2: begin raw_red=8'h50;raw_green=8'hc8;raw_blue=8'hc8;end
                    default: begin raw_red=8'hf0;raw_green=8'he0;raw_blue=8'hb0;end
                endcase
                4'd8: case (color[1:0]) // CoCo artifact
                    2'd0: begin raw_red=8'h18;raw_green=8'h18;raw_blue=8'h18;end
                    2'd1: begin raw_red=8'h30;raw_green=8'h60;raw_blue=8'he0;end
                    2'd2: begin raw_red=8'he0;raw_green=8'h60;raw_blue=8'h20;end
                    default: begin raw_red=8'hd8;raw_green=8'hd0;raw_blue=8'hb8;end
                endcase
                4'd9: case (color[1:0]) // Forest
                    2'd0: begin raw_red=8'h10;raw_green=8'h18;raw_blue=8'h10;end
                    2'd1: begin raw_red=8'h28;raw_green=8'h60;raw_blue=8'h40;end
                    2'd2: begin raw_red=8'h80;raw_green=8'hb8;raw_blue=8'h50;end
                    default: begin raw_red=8'he8;raw_green=8'he0;raw_blue=8'h90;end
                endcase
                4'd10: case (color[1:0]) // Fire
                    2'd0: begin raw_red=8'h18;raw_green=8'h0c;raw_blue=8'h10;end
                    2'd1: begin raw_red=8'h70;raw_green=8'h20;raw_blue=8'h20;end
                    2'd2: begin raw_red=8'hd0;raw_green=8'h60;raw_blue=8'h28;end
                    default: begin raw_red=8'hf0;raw_green=8'hd0;raw_blue=8'h58;end
                endcase
                4'd11: case (color[1:0]) // Ice
                    2'd0: begin raw_red=8'h10;raw_green=8'h10;raw_blue=8'h18;end
                    2'd1: begin raw_red=8'h30;raw_green=8'h38;raw_blue=8'h78;end
                    2'd2: begin raw_red=8'h68;raw_green=8'ha8;raw_blue=8'hd8;end
                    default: begin raw_red=8'he8;raw_green=8'hf0;raw_blue=8'hf0;end
                endcase
                4'd12: case (color[1:0]) // Purple dusk
                    2'd0: begin raw_red=8'h24;raw_green=8'h18;raw_blue=8'h30;end
                    2'd1: begin raw_red=8'h60;raw_green=8'h48;raw_blue=8'h78;end
                    2'd2: begin raw_red=8'hc0;raw_green=8'h70;raw_blue=8'h88;end
                    default: begin raw_red=8'hf0;raw_green=8'hc8;raw_blue=8'h98;end
                endcase
                4'd13: case (color[1:0]) // Game Boy style
                    2'd0: begin raw_red=8'h18;raw_green=8'h20;raw_blue=8'h18;end
                    2'd1: begin raw_red=8'h40;raw_green=8'h58;raw_blue=8'h38;end
                    2'd2: begin raw_red=8'h88;raw_green=8'ha8;raw_blue=8'h50;end
                    default: begin raw_red=8'hd0;raw_green=8'hd8;raw_blue=8'h90;end
                endcase
                4'd14: case (color[1:0]) // Ocean/sunset
                    2'd0: begin raw_red=8'h10;raw_green=8'h18;raw_blue=8'h38;end
                    2'd1: begin raw_red=8'h28;raw_green=8'h58;raw_blue=8'ha0;end
                    2'd2: begin raw_red=8'he0;raw_green=8'h68;raw_blue=8'h58;end
                    default: begin raw_red=8'hf0;raw_green=8'hd8;raw_blue=8'h98;end
                endcase
                default: case (color[1:0]) // Neutral grayscale
                    2'd0: begin raw_red=8'h10;raw_green=8'h10;raw_blue=8'h10;end
                    2'd1: begin raw_red=8'h50;raw_green=8'h50;raw_blue=8'h50;end
                    2'd2: begin raw_red=8'ha8;raw_green=8'ha8;raw_blue=8'ha8;end
                    default: begin raw_red=8'hf0;raw_green=8'hf0;raw_blue=8'hf0;end
                endcase
            endcase
        end else if (color[8]) begin
            // Preserve the four direct-color intensity modes used by the
            // original CoCo3FPGA DAC. COLOR[5:0] is R-G-B interleaved.
            case (color[7:6])
                2'b00: begin
                    direct_red   = {1'b0, color[5], color[2], 1'b0};
                    direct_green = {1'b0, color[4], color[1], 1'b0};
                    direct_blue  = {1'b0, color[3], color[0], 1'b0};
                end
                2'b01: begin
                    direct_red   = {1'b0, color[5], color[2], 1'b0} + {2'b00, color[5], color[2]};
                    direct_green = {1'b0, color[4], color[1], 1'b0} + {2'b00, color[4], color[1]};
                    direct_blue  = {1'b0, color[3], color[0], 1'b0} + {2'b00, color[3], color[0]};
                end
                2'b10: begin
                    direct_red   = {color[5], color[2], 2'b00};
                    direct_green = {color[4], color[1], 2'b00};
                    direct_blue  = {color[3], color[0], 2'b00};
                end
                default: begin
                    direct_red   = {color[5], color[2], color[5], color[2]};
                    direct_green = {color[4], color[1], color[4], color[1]};
                    direct_blue  = {color[3], color[0], color[3], color[0]};
                end
            endcase
            raw_red   = {direct_red, direct_red};
            raw_green = {direct_green, direct_green};
            raw_blue  = {direct_blue, direct_blue};
        end else begin
            // GIME palette encoding is R2 G2 B2 R1 G1 B1, not RR GG BB.
            // COCO3VIDEO emits logical color 16 for the GIME border. Keep
            // that fifth index bit instead of truncating the border to
            // palette entry zero.
            raw_red={(color[4] ? border_palette[5] : palette[color[3:0]][5]),
                     (color[4] ? border_palette[2] : palette[color[3:0]][2]),
                     (color[4] ? border_palette[5] : palette[color[3:0]][5]),
                     (color[4] ? border_palette[2] : palette[color[3:0]][2]),
                     (color[4] ? border_palette[5] : palette[color[3:0]][5]),
                     (color[4] ? border_palette[2] : palette[color[3:0]][2]),
                     (color[4] ? border_palette[5] : palette[color[3:0]][5]),
                     (color[4] ? border_palette[2] : palette[color[3:0]][2])};
            raw_green={(color[4] ? border_palette[4] : palette[color[3:0]][4]),
                       (color[4] ? border_palette[1] : palette[color[3:0]][1]),
                       (color[4] ? border_palette[4] : palette[color[3:0]][4]),
                       (color[4] ? border_palette[1] : palette[color[3:0]][1]),
                       (color[4] ? border_palette[4] : palette[color[3:0]][4]),
                       (color[4] ? border_palette[1] : palette[color[3:0]][1]),
                       (color[4] ? border_palette[4] : palette[color[3:0]][4]),
                       (color[4] ? border_palette[1] : palette[color[3:0]][1])};
            raw_blue={(color[4] ? border_palette[3] : palette[color[3:0]][3]),
                      (color[4] ? border_palette[0] : palette[color[3:0]][0]),
                      (color[4] ? border_palette[3] : palette[color[3:0]][3]),
                      (color[4] ? border_palette[0] : palette[color[3:0]][0]),
                      (color[4] ? border_palette[3] : palette[color[3:0]][3]),
                      (color[4] ? border_palette[0] : palette[color[3:0]][0]),
                      (color[4] ? border_palette[3] : palette[color[3:0]][3]),
                      (color[4] ? border_palette[0] : palette[color[3:0]][0])};
        end
    end

    // NTSC artifact color is meaningful only for the MC6847's 256x192
    // one-bit graphics mode (A/G=1, GM2:GM0=111).  Applying the decoder to
    // four-color modes destroys their CSS-selected palette.  F10 remains the
    // user preference, while this mode qualification protects all other VDG
    // and GIME video modes.
    wire artifact_on_pixel = raw_red[7] && raw_green[7] && raw_blue[7];
    // Keep the downstream pipelines in reset while the GIME waits for its
    // one-shot raster alignment. Once released, all stages free-run together.
    wire video_pipeline_reset = video_core_reset;
    ntsc_artifact_filter artifact_i (
        .pixel_clk(pixel_clk), .reset(video_pipeline_reset),
        .enable(artifact_enabled && artifact_compatible_mode &&
                manager_artifact_mode != 0),
        .decoder_style(manager_artifact_mode),
        .color_set(manager_artifact_palette),
        .phase_reverse(1'b0), .in_hsync(raw_hsync), .in_vsync(raw_vsync),
        .in_video_enable(raw_video_enable),
        .in_on_pixel(artifact_on_pixel),
        .in_red(raw_red), .in_green(raw_green), .in_blue(raw_blue),
        .out_hsync(artifact_hsync), .out_vsync(artifact_vsync),
        .out_video_enable(artifact_video_enable),
        .out_red(artifact_red), .out_green(artifact_green), .out_blue(artifact_blue)
    );

    wire [7:0] filtered_red, filtered_green, filtered_blue;
    crt_filter crt_i (
        .pixel_clk(pixel_clk), .reset(video_pipeline_reset),
        .enable(scanlines_enabled),
        .in_hsync(artifact_hsync), .in_vsync(artifact_vsync),
        .in_video_enable(artifact_video_enable),
        .in_red(artifact_red), .in_green(artifact_green), .in_blue(artifact_blue),
        .mask_layout(scanlines_enabled ? 5'd7 : 5'd0),
        .mask_intensity(8'd72),
        .bloom_size(3'd0), .bloom_threshold(8'd100),
        .corner_radius(7'd0), .vignette_size(7'd0),
        .vignette_strength(8'd0), .black_level(8'd0), .white_level(8'd255),
        .out_hsync(hsync), .out_vsync(vsync), .out_video_enable(video_enable),
        .out_red(filtered_red), .out_green(filtered_green), .out_blue(filtered_blue)
    );
    wire [7:0] osd_red, osd_green, osd_blue;
    manager_osd osd_i (
        .clock(pixel_clk), .reset(reset), .active(manager_osd_active),
        .screen_x(screen_x), .screen_y(screen_y),
        .selected_row(manager_osd_selected_row),
        .narrow_selection(manager_osd_narrow_selection),
        .option_selection(manager_osd_option_selection),
        .font_style(manager_osd_font_style),
        .char_address(manager_osd_char_address),
        .char_data(manager_osd_char_data),
        .preview_read_address(manager_osd_preview_read_address),
        .preview_read_data(manager_osd_preview_read_data),
        .preview_active(manager_osd_preview_active),
        .preview_palette(manager_osd_preview_palette),
        .red(osd_red), .green(osd_green), .blue(osd_blue)
    );
    assign menu_active = manager_osd_active;
    assign red = manager_osd_active ? osd_red : filtered_red;
    assign green = manager_osd_active ? osd_green : filtered_green;
    assign blue = manager_osd_active ? osd_blue : filtered_blue;
    wire _unused = sync_flag;
    // Matches COCO3VIDEO's MODE_256 selection. In text modes this identifies
    // the 32-column/narrow raster that needs separate HDMI centering.
    assign narrow_video_mode = coco | ~hres[0];
endmodule
`default_nettype wire
