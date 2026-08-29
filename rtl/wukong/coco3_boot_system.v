`timescale 1ns/1ps
`default_nettype none

module coco3_boot_system (
    input wire pixel_clk, input wire reset,
    input wire ps2_clk, input wire ps2_data,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi,
    input wire sd_miso,
    output wire hsync, output wire vsync, output wire video_enable,
    output wire [7:0] red, output wire [7:0] green, output wire [7:0] blue
);
    wire [15:0] cpu_address;
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
    reg bp;
    reg [6:0] vert;
    reg [3:0] vid_cont;
    reg css;
    reg [2:0] lpr;
    reg hlpr;
    reg [1:0] lpf, cres;
    reg [3:0] hres, scroll;
    reg hven;
    reg [6:0] hor_offset;
    reg [1:0] start_hsb;
    reg [7:0] start_msb, start_lsb;
    reg [5:0] palette [0:15];
    reg pia_ddr4;
    reg [3:0] direct_red, direct_green, direct_blue;
    integer i;
    wire [55:0] keyboard_keys;
    wire keyboard_shift;
    wire keyboard_shift_override;
    wire keyboard_reset;
    wire keyboard_f8;
    wire keyboard_f11;
    wire keyboard_f10;
    reg [1:0] keyboard_f10_sync;
    reg [1:0] keyboard_f8_sync;
    reg [1:0] keyboard_f11_sync;
    reg [1:0] keyboard_reset_sync;
    reg keyboard_f11_previous;
    reg artifact_enabled;
    reg crt_enabled;
    reg keyboard_f10_previous;
    reg keyboard_f8_previous;
    reg keyboard_joystick_enabled;
    reg soft_reset_active;
    reg [21:0] soft_reset_release_count;
    wire soft_reset_keys_held = keyboard_reset_sync[1] ||
                                keyboard_keys[51] || keyboard_keys[52];
    wire system_reset = reset | soft_reset_active;
    wire [55:0] keyboard_joystick_mask = keyboard_joystick_enabled
        ? 56'h000000F8000000 : 56'b0;
    wire [55:0] machine_keyboard_keys = soft_reset_active ? 56'b0 :
                                       (keyboard_keys & ~keyboard_joystick_mask);
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
        .F8(keyboard_f8),
        .F10(keyboard_f10),
        .F11(keyboard_f11),
        .RESET(keyboard_reset)
    );

    // F11 is decoded in the divided keyboard clock domain. Synchronize its
    // level and toggle artifact color once on each make-code edge.
    always @(posedge pixel_clk) begin
        if (reset) begin
            keyboard_f11_sync <= 2'b00;
            keyboard_f10_sync <= 2'b00;
            keyboard_f8_sync <= 2'b00;
            keyboard_reset_sync <= 2'b00;
            keyboard_f11_previous <= 1'b0;
            artifact_enabled <= 1'b1;
            keyboard_f10_previous <= 1'b0;
            keyboard_f8_previous <= 1'b0;
            keyboard_joystick_enabled <= 1'b0;
            crt_enabled <= 1'b0;
        end else begin
            keyboard_f11_sync <= {keyboard_f11_sync[0], keyboard_f11};
            keyboard_f10_sync <= {keyboard_f10_sync[0], keyboard_f10};
            keyboard_f8_sync <= {keyboard_f8_sync[0], keyboard_f8};
            keyboard_reset_sync <= {keyboard_reset_sync[0], keyboard_reset};
            keyboard_f11_previous <= keyboard_f11_sync[1];
            keyboard_f10_previous <= keyboard_f10_sync[1];
            keyboard_f8_previous <= keyboard_f8_sync[1];
            if (keyboard_reset_sync[1])
                artifact_enabled <= 1'b1;
            else if (keyboard_f11_sync[1] && !keyboard_f11_previous)
                artifact_enabled <= ~artifact_enabled;
            if (keyboard_f10_sync[1] && !keyboard_f10_previous)
                crt_enabled <= ~crt_enabled;
            if (keyboard_f8_sync[1] && !keyboard_f8_previous)
                keyboard_joystick_enabled <= ~keyboard_joystick_enabled;
        end
    end

    // Ctrl+Alt+Delete is also the CoCo 3 Easter-egg chord. Keep the emulated
    // machine in reset until the modifiers have been released, then provide a
    // short key-free guard interval before allowing the ROM to start.
    always @(posedge pixel_clk) begin
        if (reset) begin
            soft_reset_active <= 1'b0;
            soft_reset_release_count <= 22'd0;
        end else if (keyboard_reset_sync[1]) begin
            soft_reset_active <= 1'b1;
            soft_reset_release_count <= 22'd0;
        end else if (soft_reset_active) begin
            if (soft_reset_keys_held) begin
                soft_reset_release_count <= 22'd0;
            end else if (soft_reset_release_count == 22'd2499999) begin
                soft_reset_active <= 1'b0;
                soft_reset_release_count <= 22'd0;
            end else begin
                soft_reset_release_count <= soft_reset_release_count + 1'b1;
            end
        end
    end

    coco3_boot_machine machine_i (
        .clock(pixel_clk), .reset(system_reset), .debug_address(cpu_address),
        .debug_vma(), .debug_read(), .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(cpu_data),
        .keyboard_keys(machine_keyboard_keys),
        .keyboard_shift(machine_keyboard_shift),
        .keyboard_shift_override(machine_keyboard_shift_override),
        .joystick_left_x(joystick_left_x),
        .joystick_left_y(joystick_left_y),
        .joystick_left_fire(joystick_left_fire),
        .sd_status(sd_status), .sd_detail(sd_detail),
        .video_hsync(raw_hsync), .video_vsync(raw_vsync),
        .video_address(video_address), .video_read_data(video_data)
    );

    always @(posedge pixel_clk) begin
        if (system_reset) begin
            coco <= 0; v <= 0; bp <= 0; vert <= 0; vid_cont <= 0; css <= 0;
            lpr <= 0; hlpr <= 0; lpf <= 0; cres <= 0; hres <= 0;
            scroll <= 0; hven <= 0; hor_offset <= 0;
            start_hsb <= 0; start_msb <= 0; start_lsb <= 0;
            pia_ddr4 <= 0;
            for (i=0; i<16; i=i+1) palette[i] <= i;
        end else if (io_write) begin
            case (cpu_address)
                16'hFF90: coco <= cpu_data[7];
                16'hFF98: begin bp <= cpu_data[7]; hres[3] <= cpu_data[6]; lpr <= cpu_data[2:0]; end
                16'hFF99: begin hlpr <= cpu_data[7]; lpf <= cpu_data[6:5]; hres[2:0] <= cpu_data[4:2]; cres <= cpu_data[1:0]; end
                16'hFF9B: start_hsb <= cpu_data[1:0];
                16'hFF9C: scroll <= cpu_data[3:0];
                16'hFF9D: start_msb <= cpu_data;
                16'hFF9E: start_lsb <= cpu_data;
                16'hFF9F: begin hven <= cpu_data[7]; hor_offset <= cpu_data[6:0]; end
                16'hFF22: if (pia_ddr4) begin
                    vid_cont <= cpu_data[7:4];
                    css <= cpu_data[3];
                end
                16'hFF23: pia_ddr4 <= cpu_data[2];
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
                default: if (cpu_address >= 16'hFFB0 && cpu_address <= 16'hFFBF)
                    palette[cpu_address[3:0]] <= cpu_data[5:0];
            endcase
        end
    end

    COCO3VIDEO video_i (
        .PIX_CLK(pixel_clk), .RESET_N(~system_reset), .COLOR(color), .HSYNC(raw_hsync),
        .SYNC_FLAG(sync_flag), .VSYNC(raw_vsync), .HBLANKING(hblank),
        .VBLANKING(vblank), .RAM_ADDRESS(video_address), .RAM_DATA(video_data),
        .VIDEO_ACTIVE(raw_video_enable),
        .COCO(coco), .V(v), .BP(bp), .VERT(vert), .VID_CONT(vid_cont), .CSS(css),
        .LPF(lpf), .VERT_FIN_SCRL(scroll), .HLPR(hlpr), .LPR(lpr), .HRES(hres),
        .CRES(cres), .HVEN(hven), .HOR_OFFSET(hor_offset),
        .SCRN_START_HSB(start_hsb), .SCRN_START_MSB(start_msb),
        .SCRN_START_LSB(start_lsb), .BLINK(1'b1), .SWITCH5(1'b0)
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
            raw_red={palette[color[3:0]][5],palette[color[3:0]][2],palette[color[3:0]][5],palette[color[3:0]][2],
                 palette[color[3:0]][5],palette[color[3:0]][2],palette[color[3:0]][5],palette[color[3:0]][2]};
            raw_green={palette[color[3:0]][4],palette[color[3:0]][1],palette[color[3:0]][4],palette[color[3:0]][1],
                   palette[color[3:0]][4],palette[color[3:0]][1],palette[color[3:0]][4],palette[color[3:0]][1]};
            raw_blue={palette[color[3:0]][3],palette[color[3:0]][0],palette[color[3:0]][3],palette[color[3:0]][0],
                  palette[color[3:0]][3],palette[color[3:0]][0],palette[color[3:0]][3],palette[color[3:0]][0]};
        end
    end

    // Software reaches artifact-capable 256-pixel modes through several
    // SAM/VDG configurations, so F11 controls the effect directly.
    wire artifact_on_pixel = raw_red[7] && raw_green[7] && raw_blue[7];
    ntsc_artifact_filter artifact_i (
        .pixel_clk(pixel_clk), .reset(system_reset), .enable(artifact_enabled),
        .phase_reverse(1'b0), .in_hsync(raw_hsync), .in_vsync(raw_vsync),
        .in_video_enable(raw_video_enable),
        .in_on_pixel(artifact_on_pixel),
        .in_red(raw_red), .in_green(raw_green), .in_blue(raw_blue),
        .out_hsync(artifact_hsync), .out_vsync(artifact_vsync),
        .out_video_enable(artifact_video_enable),
        .out_red(artifact_red), .out_green(artifact_green), .out_blue(artifact_blue)
    );

    crt_filter crt_i (
        .pixel_clk(pixel_clk), .reset(system_reset), .enable(crt_enabled),
        .in_hsync(artifact_hsync), .in_vsync(artifact_vsync),
        .in_video_enable(artifact_video_enable),
        .in_red(artifact_red), .in_green(artifact_green), .in_blue(artifact_blue),
        .mask_layout(5'd4), .mask_intensity(8'd72),
        .bloom_size(3'd4), .bloom_threshold(8'd180),
        .corner_radius(7'd0), .vignette_size(7'd0),
        .vignette_strength(8'd0), .black_level(8'd0), .white_level(8'd255),
        .out_hsync(hsync), .out_vsync(vsync), .out_video_enable(video_enable),
        .out_red(red), .out_green(green), .out_blue(blue)
    );
    wire _unused = sync_flag;
endmodule
`default_nettype wire
