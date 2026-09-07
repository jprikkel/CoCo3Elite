`timescale 1ns/1ps
`default_nettype none

module coco3_boot_system (
    input wire pixel_clk, input wire reset,
    input wire raster_resync,
    input wire ps2_clk, input wire ps2_data,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi,
    input wire sd_miso,
    output wire hsync, output wire vsync, output wire video_enable,
    output wire [5:0] audio_dac,
    output wire narrow_video_mode,
    output wire uart_debug_tx,
    output wire [7:0] red, output wire [7:0] green, output wire [7:0] blue
);
    wire [15:0] cpu_address;
    wire [15:0] cpu_pc;
    wire cpu_vma;
    wire cpu_read;
    wire cpu_opfetch;
    wire [7:0] cpu_read_data;
    wire io_write;
    wire [7:0] cpu_data;
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
    reg [1:0] keyboard_f6_sync;
    reg [1:0] keyboard_f3_sync;
    reg [1:0] keyboard_f7_sync;
    reg [1:0] keyboard_f10_sync;
    reg [1:0] keyboard_f8_sync;
    reg [1:0] keyboard_f9_sync;
    reg [1:0] keyboard_f11_sync;
    reg [1:0] keyboard_reset_sync;
    reg keyboard_f11_previous;
    reg keyboard_f6_previous;
    reg keyboard_f3_previous;
    reg keyboard_f7_previous;
    reg cpu_fast_mode;
    reg keyboard_right_joystick_enabled;
    reg artifact_enabled;
    reg crt_enabled;
    reg keyboard_f10_previous;
    reg keyboard_f8_previous;
    reg keyboard_f9_previous;
    reg keyboard_joystick_enabled;
    reg scanlines_enabled;
    reg soft_reset_active;
    reg diagnostic_cartridge_enabled;
    reg [21:0] soft_reset_release_count;
    wire soft_reset_keys_held = keyboard_reset_sync[1] || keyboard_f3_sync[1] ||
                                keyboard_keys[51] || keyboard_keys[52];
    wire system_reset = reset | soft_reset_active;
    wire [55:0] keyboard_joystick_mask = keyboard_joystick_enabled
        ? 56'h000000F8000000 : 56'b0;
    wire [55:0] keyboard_right_joystick_mask = keyboard_right_joystick_enabled
        ? ((56'b1 << 23) | (56'b1 << 19) | (56'b1 << 1) |
           (56'b1 << 4) | (56'b1 << 6)) : 56'b0;
    wire [55:0] machine_keyboard_keys = soft_reset_active ? 56'b0 :
        (keyboard_keys & ~keyboard_joystick_mask & ~keyboard_right_joystick_mask);
    wire machine_keyboard_shift = soft_reset_active ? 1'b0 : keyboard_shift;
    wire machine_keyboard_shift_override = soft_reset_active ? 1'b0 :
                                           keyboard_shift_override;
    wire joystick_left_only = keyboard_keys[29] && !keyboard_keys[30];
    wire joystick_right_only = keyboard_keys[30] && !keyboard_keys[29];
    wire joystick_up_only = keyboard_keys[27] && !keyboard_keys[28];
    wire joystick_down_only = keyboard_keys[28] && !keyboard_keys[27];
    wire [5:0] joystick_left_x = !keyboard_joystick_enabled ? 6'd32 :
                                 joystick_left_only ? 6'd0 :
                                 joystick_right_only ? 6'd63 : 6'd32;
    wire [5:0] joystick_left_y = !keyboard_joystick_enabled ? 6'd32 :
                                 joystick_up_only ? 6'd0 :
                                 joystick_down_only ? 6'd63 : 6'd32;
    wire joystick_left_fire = keyboard_joystick_enabled && keyboard_keys[31];
    wire joystick_right_left_only = keyboard_keys[1] && !keyboard_keys[4];
    wire joystick_right_right_only = keyboard_keys[4] && !keyboard_keys[1];
    wire joystick_right_up_only = keyboard_keys[23] && !keyboard_keys[19];
    wire joystick_right_down_only = keyboard_keys[19] && !keyboard_keys[23];
    wire [5:0] joystick_right_x = !keyboard_right_joystick_enabled ? 6'd32 :
                                  joystick_right_left_only ? 6'd0 :
                                  joystick_right_right_only ? 6'd63 : 6'd32;
    wire [5:0] joystick_right_y = !keyboard_right_joystick_enabled ? 6'd32 :
                                  joystick_right_up_only ? 6'd0 :
                                  joystick_right_down_only ? 6'd63 : 6'd32;
    wire joystick_right_fire = keyboard_right_joystick_enabled && keyboard_keys[6];
    wire [7:0] sd_init_status;
    wire [7:0] sd_init_detail;
    wire [7:0] sd_read_status;
    wire [7:0] sd_read_detail;
    wire sd_init_cs_n, sd_init_sck, sd_init_mosi;
    wire sd_read_cs_n, sd_read_sck, sd_read_mosi;
    wire sd_initialized = sd_init_status == 8'h80;
    wire [7:0] sd_status = sd_initialized ? sd_read_status : sd_init_status;
    wire [7:0] sd_detail = sd_initialized ? sd_read_detail : sd_init_detail;

    assign sd_cs_n = sd_initialized ? sd_read_cs_n : sd_init_cs_n;
    assign sd_sck  = sd_initialized ? sd_read_sck  : sd_init_sck;
    assign sd_mosi = sd_initialized ? sd_read_mosi : sd_init_mosi;

    sd_spi_init sd_i (
        .clock(pixel_clk), .reset(reset), .miso(sd_miso),
        .cs_n(sd_init_cs_n), .sck(sd_init_sck), .mosi(sd_init_mosi),
        .status(sd_init_status), .detail(sd_init_detail)
    );

    sd_spi_read_sector0 sd_sector0_i (
        .clock(pixel_clk), .reset(reset), .enable(sd_initialized),
        .miso(sd_miso), .cs_n(sd_read_cs_n), .sck(sd_read_sck),
        .mosi(sd_read_mosi), .status(sd_read_status),
        .detail(sd_read_detail)
    );

    COCOKEY keyboard_i (
        .RESET_N(~reset),
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
        .RESET(keyboard_reset)
    );

    // Function keys are decoded in the divided keyboard clock domain.
    // Synchronize their levels and toggle each feature once per make edge.
    always @(posedge pixel_clk) begin
        if (reset) begin
            keyboard_f6_sync <= 2'b00;
            keyboard_f3_sync <= 2'b00;
            keyboard_f7_sync <= 2'b00;
            keyboard_f11_sync <= 2'b00;
            keyboard_f10_sync <= 2'b00;
            keyboard_f8_sync <= 2'b00;
            keyboard_f9_sync <= 2'b00;
            keyboard_reset_sync <= 2'b00;
            keyboard_f11_previous <= 1'b0;
            keyboard_f6_previous <= 1'b0;
            keyboard_f3_previous <= 1'b0;
            keyboard_f7_previous <= 1'b0;
            cpu_fast_mode <= 1'b0;
            keyboard_right_joystick_enabled <= 1'b0;
            artifact_enabled <= 1'b1;
            keyboard_f10_previous <= 1'b0;
            keyboard_f8_previous <= 1'b0;
            keyboard_f9_previous <= 1'b0;
            keyboard_joystick_enabled <= 1'b0;
            scanlines_enabled <= 1'b0;
            crt_enabled <= 1'b0;
        end else begin
            keyboard_f6_sync <= {keyboard_f6_sync[0], keyboard_f6};
            keyboard_f3_sync <= {keyboard_f3_sync[0], keyboard_f3};
            keyboard_f7_sync <= {keyboard_f7_sync[0], keyboard_f7};
            keyboard_f11_sync <= {keyboard_f11_sync[0], keyboard_f11};
            keyboard_f10_sync <= {keyboard_f10_sync[0], keyboard_f10};
            keyboard_f8_sync <= {keyboard_f8_sync[0], keyboard_f8};
            keyboard_f9_sync <= {keyboard_f9_sync[0], keyboard_f9};
            keyboard_reset_sync <= {keyboard_reset_sync[0], keyboard_reset};
            keyboard_f11_previous <= keyboard_f11_sync[1];
            keyboard_f6_previous <= keyboard_f6_sync[1];
            keyboard_f3_previous <= keyboard_f3_sync[1];
            keyboard_f7_previous <= keyboard_f7_sync[1];
            keyboard_f10_previous <= keyboard_f10_sync[1];
            keyboard_f8_previous <= keyboard_f8_sync[1];
            keyboard_f9_previous <= keyboard_f9_sync[1];
            if (keyboard_reset_sync[1])
                artifact_enabled <= 1'b1;
            else if (keyboard_f11_sync[1] && !keyboard_f11_previous)
                artifact_enabled <= ~artifact_enabled;
            if (keyboard_f6_sync[1] && !keyboard_f6_previous)
                cpu_fast_mode <= ~cpu_fast_mode;
            if (keyboard_f7_sync[1] && !keyboard_f7_previous)
                keyboard_right_joystick_enabled <= ~keyboard_right_joystick_enabled;
            if (keyboard_f10_sync[1] && !keyboard_f10_previous)
                crt_enabled <= ~crt_enabled;
            if (keyboard_f8_sync[1] && !keyboard_f8_previous)
                keyboard_joystick_enabled <= ~keyboard_joystick_enabled;
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
            soft_reset_release_count <= 22'd0;
            diagnostic_cartridge_enabled <= 1'b0;
        end else if (keyboard_reset_sync[1]) begin
            soft_reset_active <= 1'b1;
            soft_reset_release_count <= 22'd0;
            diagnostic_cartridge_enabled <= 1'b0;
        end else if (keyboard_f3_sync[1] && !keyboard_f3_previous) begin
            // Present an autostart ROM-Pak to the already initialized
            // machine. Resetting the CPU and PIAs here leaves PIA0 port A in
            // DDR mode, causing ZIA's keyboard scanner to read $00 forever.
            // The cartridge controller supplies the delayed CART/FIRQ edge.
            diagnostic_cartridge_enabled <= 1'b1;
        end else if (soft_reset_active) begin
            if (soft_reset_keys_held) begin
                soft_reset_release_count <= 22'd0;
            end else if (soft_reset_release_count == 22'd2499999 &&
                         raster_resync) begin
                soft_reset_active <= 1'b0;
                soft_reset_release_count <= 22'd0;
            end else if (soft_reset_release_count == 22'd2499999) begin
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
        .clock(pixel_clk), .reset(system_reset), .debug_address(cpu_address),
        .debug_pc(cpu_pc),
        .cpu_fast_mode(cpu_fast_mode),
        .diagnostic_cartridge_enabled(diagnostic_cartridge_enabled),
        .debug_vma(cpu_vma), .debug_read(cpu_read),
        .debug_opfetch(cpu_opfetch), .debug_read_data(cpu_read_data),
        .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(cpu_data),
        .keyboard_keys(machine_keyboard_keys),
        .keyboard_shift(machine_keyboard_shift),
        .keyboard_shift_override(machine_keyboard_shift_override),
        .joystick_left_x(joystick_left_x),
        .joystick_left_y(joystick_left_y),
        .joystick_left_fire(joystick_left_fire),
        .joystick_right_x(joystick_right_x),
        .joystick_right_y(joystick_right_y),
        .joystick_right_fire(joystick_right_fire),
        .sd_status(sd_status), .sd_detail(sd_detail),
        .video_hsync(raw_hsync), .video_vsync(raw_vsync),
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

    coco3_uart_debug uart_debug_i (
        .clock(pixel_clk), .reset(reset), .cpu_address(cpu_address),
        .cpu_pc(cpu_pc),
        .cpu_vma(cpu_vma), .cpu_read(cpu_read), .cpu_opfetch(cpu_opfetch),
        .cpu_read_data(cpu_read_data), .cpu_write_data(cpu_data),
        .keyboard_active(|keyboard_keys),
        .cartridge_enabled(diagnostic_cartridge_enabled),
        .uart_tx_o(uart_debug_tx)
    );

    generate
        for (palette_index = 0; palette_index < 16; palette_index = palette_index + 1) begin : expand_palette
            assign palette[palette_index] = machine_palette[palette_index*6 +: 6];
        end
    endgenerate

    always @(posedge pixel_clk) begin
        if (system_reset) begin
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
        .PIX_CLK(pixel_clk), .RESET_N(~(system_reset | raster_resync)),
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
    always @* begin
        if (color[8]) begin
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
    // four-color modes destroys their CSS-selected palette.  F11 remains the
    // user preference, while this mode qualification protects all other VDG
    // and GIME video modes.
    wire artifact_compatible_mode = coco && (vid_cont == 4'b1111);
    wire artifact_on_pixel = raw_red[7] && raw_green[7] && raw_blue[7];
    // The HDMI wrapper realigns the GIME once per transport frame. Reset the
    // downstream pixel pipelines at the same instant; otherwise their delay
    // registers carry the tail of the previous frame into the visible border.
    wire video_pipeline_reset = system_reset | raster_resync;
    ntsc_artifact_filter artifact_i (
        .pixel_clk(pixel_clk), .reset(video_pipeline_reset),
        .enable(artifact_enabled && artifact_compatible_mode),
        .phase_reverse(1'b0), .in_hsync(raw_hsync), .in_vsync(raw_vsync),
        .in_video_enable(raw_video_enable),
        .in_on_pixel(artifact_on_pixel),
        .in_red(raw_red), .in_green(raw_green), .in_blue(raw_blue),
        .out_hsync(artifact_hsync), .out_vsync(artifact_vsync),
        .out_video_enable(artifact_video_enable),
        .out_red(artifact_red), .out_green(artifact_green), .out_blue(artifact_blue)
    );

    crt_filter crt_i (
        .pixel_clk(pixel_clk), .reset(video_pipeline_reset),
        .enable(crt_enabled | scanlines_enabled),
        .in_hsync(artifact_hsync), .in_vsync(artifact_vsync),
        .in_video_enable(artifact_video_enable),
        .in_red(artifact_red), .in_green(artifact_green), .in_blue(artifact_blue),
        .mask_layout(scanlines_enabled ? 5'd7 : 5'd0),
        .mask_intensity(8'd72),
        .bloom_size(crt_enabled ? 3'd6 : 3'd0), .bloom_threshold(8'd100),
        .corner_radius(7'd0), .vignette_size(7'd0),
        .vignette_strength(8'd0), .black_level(8'd0), .white_level(8'd255),
        .out_hsync(hsync), .out_vsync(vsync), .out_video_enable(video_enable),
        .out_red(red), .out_green(green), .out_blue(blue)
    );
    wire _unused = sync_flag;
    // Matches COCO3VIDEO's MODE_256 selection. In text modes this identifies
    // the 32-column/narrow raster that needs separate HDMI centering.
    assign narrow_video_mode = coco | ~hres[0];
endmodule
`default_nettype wire
