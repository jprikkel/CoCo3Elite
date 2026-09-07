`timescale 1ns/1ps
`default_nettype none

// Early real-ROM execution boundary. Peripheral reads are deliberately idle;
// GIME/MMU and PIA behavior will be added as boot tracing identifies needs.
module coco3_boot_machine #(
    // Give the system ROM time to initialize the GIME and both PIAs before
    // asserting the emulated CART edge. At 25.2 MHz this is one second.
    parameter integer CARTRIDGE_START_DELAY = 25199999
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        cpu_fast_mode,
    input  wire        diagnostic_cartridge_enabled,
    output wire [15:0] debug_address,
    output wire [15:0] debug_pc,
    output wire        debug_vma,
    output wire        debug_read,
    output wire        debug_opfetch,
    output wire [7:0]  debug_read_data,
    output wire        debug_ram_write,
    output wire        debug_io_write,
    output wire [7:0]  debug_write_data,
    input  wire [55:0] keyboard_keys,
    input  wire        keyboard_shift,
    input  wire        keyboard_shift_override,
    input  wire [5:0]  joystick_left_x,
    input  wire [5:0]  joystick_left_y,
    input  wire        joystick_left_fire,
    input  wire [5:0]  joystick_right_x,
    input  wire [5:0]  joystick_right_y,
    input  wire        joystick_right_fire,
    input  wire [7:0]  sd_status,
    input  wire [7:0]  sd_detail,
    input  wire        video_hsync,
    input  wire        video_vsync,
    input  wire [19:0] video_address,
    output wire [15:0] video_read_data,
    output wire [5:0]  audio_dac,
    output wire [3:0]  video_vdg_control,
    output wire        video_css,
    output wire [95:0] video_palette,
    output wire [5:0]  video_border_palette,
    output wire [7:0]  video_mode,
    output wire [7:0]  video_resolution,
    output wire [1:0]  video_vbank,
    output wire [3:0]  video_scroll,
    output wire [15:0] video_offset,
    output wire [7:0]  video_horizontal_offset,
    output wire        video_blink
);
    reg [4:0] divider;
    reg hold;
    reg all_ram;
    reg mmu_enable;
    reg mmu_task;
    reg [7:0] gime_init0;
    reg [7:0] gime_init1;
    reg [7:0] pia0_ddra;
    reg [7:0] pia0_ddrb;
    reg [7:0] pia0_outa;
    reg [7:0] pia0_outb;
    reg [5:0] pia0_cra;
    reg [5:0] pia0_crb;
    reg [7:0] pia1_ddra;
    reg [7:0] pia1_ddrb;
    reg [7:0] pia1_outa;
    reg [7:0] pia1_outb;
    reg [5:0] pia1_cra;
    reg [5:0] pia1_crb;

    // PIA1 PB3 is the CoCo 3 RGB/composite monitor-sense input whenever
    // that bit is configured as an input.  The HDMI output is an RGB path,
    // so hold PB3 low just as the original CoCo3FPGA implementation does.
    // Other presently-unmodelled PIA1 port-B inputs retain their pull-ups.
    wire [7:0] pia1_portb_inputs = 8'b1111_0111;
    // The physical CoCo routes the six-bit DAC to audio only when SOUND_EN is
    // asserted and the analog multiplexer selects the DAC (SEL=00). Keep a
    // separate held audio value so JOYSTK's comparator sweep is inaudible.
    reg [5:0] sound_dac;
    reg [24:0] cartridge_start_count;
    reg cartridge_irq_latch;
    reg cartridge_start_sent;
    reg [12:0] diagnostic_probe_address;
    reg [7:0] mmu [0:15];
    reg [5:0] palette [0:15];
    reg [5:0] border_palette;
    reg [7:0] gime_video_mode;
    reg [7:0] gime_video_resolution;
    reg [1:0] gime_video_vbank;
    reg [3:0] gime_video_scroll;
    reg [15:0] gime_video_offset;
    reg [7:0] gime_video_horizontal_offset;
    reg [4:0] boot_palette_write_count;
    reg hdmi_palette_initialized;
    integer index;
    genvar palette_index;

    wire composite_palette_preset =
        palette[0]  == 6'h12 && palette[1]  == 6'h24 &&
        palette[2]  == 6'h0b && palette[3]  == 6'h07 &&
        palette[4]  == 6'h3f && palette[5]  == 6'h1f &&
        palette[6]  == 6'h09 && palette[7]  == 6'h26 &&
        palette[8]  == 6'h00 && palette[9]  == 6'h12 &&
        palette[10] == 6'h00 && palette[11] == 6'h3f &&
        palette[12] == 6'h00 && palette[13] == 6'h12 &&
        palette[14] == 6'h00 && palette[15] == 6'h26;

    wire vma;
    wire opfetch;
    wire [15:0] address;
    wire read_cycle;
    wire [7:0] write_data;
    wire [7:0] ram_data;
    wire [7:0] rom_data;
    wire [7:0] disk_rom_data;
    wire [7:0] diagnostic_rom_data;
    wire [3:0] gime_timer_msb;
    wire [7:0] gime_timer_lsb;
    wire [7:0] fdc_read_data;
    wire fdc_nmi;
    wire io_select = address[15:8] == 8'hFF && address[7:4] != 4'hF;
    wire vector_select = address[15:4] == 12'hFFF;
    // GIME INIT0 ROM map 00/01 exposes an internal lower 16K and external
    // upper 16K. The Disk BASIC cartridge occupies the upper half's first
    // 8K at $C000-$DFFF. ROM map 10 selects the full internal 32K image.
    wire disk_rom_select = !all_ram && !io_select &&
                           address[15:13] == 3'b110 &&
                           gime_init0[1:0] != 2'b10;
    wire diagnostic_rom_select = diagnostic_cartridge_enabled &&
                                 !io_select && address[15:13] == 3'b110;
    // $FE00-$FEFF is RAM in both modes. INIT0 bit 3 selects the fixed page
    // $3F instead of MMU block 7, matching the original CoCo3FPGA decode.
    wire vector_page = address[15:8] == 8'hFE;
    wire rom_select = vector_select ||
                      (!all_ram && !io_select && address[15] &&
                       !vector_page);
    wire [7:0] mapped_page = vector_page && gime_init0[3]
        ? 8'h3f
        : mmu_enable
        ? mmu[{mmu_task, address[15:13]}]
        : {5'b00111, address[15:13]};
    // A 128K machine implements 16 physical 8K pages. Higher GIME page
    // numbers alias modulo 16, matching absent physical address pins.
    wire [16:0] physical_address = {mapped_page[3:0], address[12:0]};
    wire active = !hold && vma;
    wire io_read = active && read_cycle && io_select;
    wire pia0_hsync_event = (~video_hsync) ^ pia0_cra[1];
    wire pia0_vsync_event = (~video_vsync) ^ pia0_crb[1];
    wire cpu_irq = (pia0_cra[0] && pia0_hsync_event) ||
                   (pia0_crb[0] && pia0_vsync_event);
    // An autostart ROM-Pak boots through the normal system ROM.  Its CART
    // edge is then latched by PIA1 CB1 and presented as FIRQ once software
    // enables that interrupt in $FF23.  Starting the cartridge through the
    // RESET vector skips ROM/GIME/PIA initialization and corrupts video.
    wire cpu_firq = diagnostic_cartridge_enabled &&
                    pia1_crb[0] && cartridge_irq_latch;
    wire ram_write = active && !read_cycle && !io_select && !rom_select;
    wire io_write = active && !read_cycle && io_select;
    wire [7:0] keyboard_columns =
        (pia0_outb & pia0_ddrb) | (~pia0_ddrb);
    wire [7:0] keyboard_rows;
    wire [5:0] joystick_dac = pia1_outa[7:2];
    wire [1:0] joystick_select = {pia0_crb[3], pia0_cra[3]};
    // Match the original CoCo3FPGA paddle selection: right X/Y are 00/01 and
    // left X/Y are 10/11.
    wire [5:0] joystick_value = joystick_select == 2'b11 ? joystick_left_y :
                                joystick_select == 2'b10 ? joystick_left_x :
                                joystick_select == 2'b01 ? joystick_right_y :
                                joystick_right_x;
    wire joystick_comparator = joystick_value >= joystick_dac;
    wire [7:0] keyboard_joystick_rows =
        {joystick_comparator, keyboard_rows[6:2],
         keyboard_rows[1] & ~joystick_left_fire,
         keyboard_rows[0] & ~joystick_right_fire};
    reg [7:0] io_read_data;
    wire [7:0] read_data = io_select ? io_read_data :
                             (diagnostic_rom_select ? diagnostic_rom_data :
                             (disk_rom_select ? disk_rom_data :
                             (rom_select ? rom_data : ram_data)));

    always @* begin
        io_read_data = 8'hFF;
        case (address)
            // Match the original CoCo3FPGA PIA model. In peripheral-register
            // mode the keyboard matrix drives the complete port; in DDR mode
            // the direction register is read back. Treating DDRA as a per-bit
            // output mask here makes the diagnostic ROM see every row low.
            16'hFF00: io_read_data = pia0_cra[2]
                ? keyboard_joystick_rows : pia0_ddra;
            16'hFF01: io_read_data = {pia0_hsync_event, 3'b011, pia0_cra[3:0]};
            16'hFF02: io_read_data = pia0_crb[2]
                ? pia0_outb : pia0_ddrb;
            16'hFF03: io_read_data = {pia0_vsync_event, 3'b011, pia0_crb[3:0]};
            16'hFF20: io_read_data = pia1_cra[2]
                ? ((pia1_outa & pia1_ddra) | (~pia1_ddra)) : pia1_ddra;
            16'hFF21: io_read_data = {2'b00, pia1_cra};
            16'hFF22: io_read_data = pia1_crb[2]
                ? ((pia1_outb & pia1_ddrb) |
                   (pia1_portb_inputs & ~pia1_ddrb)) : pia1_ddrb;
            16'hFF23: io_read_data = {cartridge_irq_latch, 1'b0, pia1_crb};
            16'hFF60: io_read_data = sd_status;
            16'hFF61: io_read_data = sd_detail;
            // Project diagnostic window for validating the ROM-Pak image
            // without resetting away from a running BASIC test.
            16'hFF70: io_read_data = diagnostic_probe_address[7:0];
            16'hFF71: io_read_data = {3'b000, diagnostic_probe_address[12:8]};
            16'hFF72: io_read_data = diagnostic_rom_data;
            16'hFF73: io_read_data = 8'hC3;
            16'hFF90: io_read_data = gime_init0;
            16'hFF91: io_read_data = gime_init1;
            16'hFF94: io_read_data = {4'h0, gime_timer_msb};
            16'hFF95: io_read_data = gime_timer_lsb;
            16'hFF98: io_read_data = gime_video_mode;
            16'hFF99: io_read_data = gime_video_resolution;
            16'hFF9A: io_read_data = {2'b00, border_palette};
            16'hFF9B: io_read_data = {6'b000000, gime_video_vbank};
            16'hFF9C: io_read_data = {4'b0000, gime_video_scroll};
            16'hFF9D: io_read_data = gime_video_offset[15:8];
            16'hFF9E: io_read_data = gime_video_offset[7:0];
            16'hFF9F: io_read_data = gime_video_horizontal_offset;
            default: begin
                if (address >= 16'hFFA0 && address <= 16'hFFAF)
                    io_read_data = mmu[address[3:0]];
                else if (address == 16'hFF40 ||
                    (address >= 16'hFF48 && address <= 16'hFF4B))
                    io_read_data = fdc_read_data;
                else if (address >= 16'hFFA0 && address <= 16'hFFAF)
                    io_read_data = mmu[address[3:0]];
                else if (address >= 16'hFFB0 && address <= 16'hFFBF)
                    io_read_data = {2'b00, palette[address[3:0]]};
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            divider <= 0;
            hold <= 1'b1;
        // The MC6809E wrapper consumes four enabled pixel-clock edges per E
        // cycle.  Release it every 4 clocks in fast mode and every 7 clocks
        // in normal mode, producing approximately 1.6 MHz and 0.9 MHz E.
        end else if (divider == (cpu_fast_mode ? 5'd3 : 5'd6)) begin
            divider <= 0;
            hold <= 1'b0;
        end else begin
            divider <= divider + 1'b1;
            hold <= 1'b1;
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            all_ram <= 1'b0;
            mmu_enable <= 1'b0;
            mmu_task <= 1'b0;
            gime_init0 <= 8'h00;
            gime_init1 <= 8'h00;
            pia0_ddra <= 8'h00;
            pia0_ddrb <= 8'h00;
            pia0_outa <= 8'h00;
            pia0_outb <= 8'h00;
            pia0_cra <= 6'h00;
            pia0_crb <= 6'h00;
            pia1_ddra <= 8'h00;
            pia1_ddrb <= 8'h00;
            pia1_outa <= 8'h00;
            pia1_outb <= 8'h00;
            pia1_cra <= 6'h00;
            pia1_crb <= 6'h00;
            sound_dac <= 6'd32;
            cartridge_start_count <= 25'd0;
            cartridge_irq_latch <= 1'b0;
            cartridge_start_sent <= 1'b0;
            diagnostic_probe_address <= 13'd0;
            boot_palette_write_count <= 5'd0;
            hdmi_palette_initialized <= 1'b0;
            for (index = 0; index < 16; index = index + 1)
                mmu[index] <= 8'h00;
            palette[4'h0] <= 6'h12;
            palette[4'h1] <= 6'h36;
            palette[4'h2] <= 6'h09;
            palette[4'h3] <= 6'h24;
            palette[4'h4] <= 6'h3f;
            palette[4'h5] <= 6'h1b;
            palette[4'h6] <= 6'h2d;
            palette[4'h7] <= 6'h26;
            palette[4'h8] <= 6'h00;
            palette[4'h9] <= 6'h12;
            palette[4'ha] <= 6'h00;
            palette[4'hb] <= 6'h3f;
            palette[4'hc] <= 6'h00;
            palette[4'hd] <= 6'h12;
            palette[4'he] <= 6'h00;
            palette[4'hf] <= 6'h26;
            border_palette <= 6'h00;
            gime_video_mode <= 8'h00;
            gime_video_resolution <= 8'h00;
            gime_video_vbank <= 2'b00;
            gime_video_scroll <= 4'h0;
            gime_video_offset <= 16'h0000;
            gime_video_horizontal_offset <= 8'h00;
        end else begin
            // Extended Color BASIC starts with its PALETTE CMP preset.  HDMI
            // is an RGB output, so apply the ROM's PALETTE RGB preset once,
            // after the complete 16-entry startup write has arrived.  This
            // changes the real palette registers (and their readback) rather
            // than disguising values in the renderer.  Later PALETTE CMP/RGB
            // commands and direct software writes remain untouched.
            if (!hdmi_palette_initialized &&
                boot_palette_write_count == 5'd16 &&
                composite_palette_preset) begin
                palette[4'h0] <= 6'h12;
                palette[4'h1] <= 6'h36;
                palette[4'h2] <= 6'h09;
                palette[4'h3] <= 6'h24;
                palette[4'h4] <= 6'h3f;
                palette[4'h5] <= 6'h1b;
                palette[4'h6] <= 6'h2d;
                palette[4'h7] <= 6'h26;
                palette[4'h8] <= 6'h00;
                palette[4'h9] <= 6'h12;
                palette[4'ha] <= 6'h00;
                palette[4'hb] <= 6'h3f;
                palette[4'hc] <= 6'h00;
                palette[4'hd] <= 6'h12;
                palette[4'he] <= 6'h00;
                palette[4'hf] <= 6'h26;
                hdmi_palette_initialized <= 1'b1;
            end
            // After the cartridge is presented, wait for the configured
            // interval before producing one emulated CART edge. Reading PIA1
            // port B is the normal interrupt acknowledge operation.
            if (diagnostic_cartridge_enabled && !cartridge_start_sent) begin
                if (cartridge_start_count == CARTRIDGE_START_DELAY) begin
                    cartridge_irq_latch <= 1'b1;
                    cartridge_start_sent <= 1'b1;
                end else begin
                    cartridge_start_count <= cartridge_start_count + 1'b1;
                end
            end
            if (io_read && address == 16'hFF22)
                cartridge_irq_latch <= 1'b0;

          if (io_write) begin
            if (address == 16'hFF00) begin
                if (pia0_cra[2]) pia0_outa <= write_data;
                else pia0_ddra <= write_data;
            end
            if (address == 16'hFF01)
                pia0_cra <= write_data[5:0];
            if (address == 16'hFF02) begin
                if (pia0_crb[2]) pia0_outb <= write_data;
                else pia0_ddrb <= write_data;
            end
            if (address == 16'hFF03)
                pia0_crb <= write_data[5:0];
            if (address == 16'hFF20) begin
                if (pia1_cra[2]) begin
                    pia1_outa <= write_data;
                    if (pia1_crb[3] && joystick_select == 2'b00)
                        sound_dac <= write_data[7:2];
                end
                else pia1_ddra <= write_data;
            end
            if (address == 16'hFF21)
                pia1_cra <= write_data[5:0];
            if (address == 16'hFF22) begin
                if (pia1_crb[2]) pia1_outb <= write_data;
                else pia1_ddrb <= write_data;
            end
            if (address == 16'hFF23)
                pia1_crb <= write_data[5:0];
            if (address == 16'hFF70)
                diagnostic_probe_address[7:0] <= write_data;
            if (address == 16'hFF71)
                diagnostic_probe_address[12:8] <= write_data[4:0];
            if (address == 16'hFF90) begin
                gime_init0 <= write_data;
                mmu_enable <= write_data[6];
            end
            if (address == 16'hFF91) begin
                gime_init1 <= write_data;
                mmu_task <= write_data[0];
            end
            if (address == 16'hFF98)
                gime_video_mode <= write_data;
            if (address == 16'hFF99)
                gime_video_resolution <= write_data;
            if (address == 16'hFF9A)
                border_palette <= write_data[5:0];
            if (address == 16'hFF9B)
                gime_video_vbank <= write_data[1:0];
            if (address == 16'hFF9C)
                gime_video_scroll <= write_data[3:0];
            if (address == 16'hFF9D)
                gime_video_offset[15:8] <= write_data;
            if (address == 16'hFF9E)
                gime_video_offset[7:0] <= write_data;
            if (address == 16'hFF9F)
                gime_video_horizontal_offset <= write_data;
            if (address >= 16'hFFA0 && address <= 16'hFFAF)
                mmu[address[3:0]] <= write_data;
            if (address >= 16'hFFB0 && address <= 16'hFFBF) begin
                palette[address[3:0]] <= write_data[5:0];
                if (!hdmi_palette_initialized && boot_palette_write_count < 5'd16)
                    boot_palette_write_count <= boot_palette_write_count + 1'b1;
            end
            if (address == 16'hFFDE)
                all_ram <= 1'b0;
            if (address == 16'hFFDF)
                all_ram <= 1'b1;
          end
        end
    end

    cpu09 cpu_i (
        .clk(clock), .rst(reset), .vma(vma), .lic_out(), .ifetch(),
        .opfetch(opfetch), .ba(), .bs(), .addr(address), .rw(read_cycle),
        .debug_pc(debug_pc),
        .data_out(write_data), .data_in(read_data), .irq(cpu_irq),
        .firq(cpu_firq), .nmi(fdc_nmi), .halt(1'b0), .hold(hold)
    );

    coco3_system_rom rom_i (
        .clock(clock), .address(address[14:0]), .data(rom_data)
    );

    coco3_disk_rom disk_rom_i (
        .clock(clock), .address(address[12:0]), .data(disk_rom_data)
    );

    coco3_diagnostic_cartridge diagnostic_rom_i (
        .clock(clock),
        .address(diagnostic_rom_select ? address[12:0] : diagnostic_probe_address),
        .data(diagnostic_rom_data)
    );

    coco3_fdc fdc_i (
        .clock(clock), .reset(reset), .io_read(io_read), .io_write(io_write),
        .address(address), .write_data(write_data),
        .read_data(fdc_read_data), .nmi(fdc_nmi)
    );

    coco3_gime_timer gime_timer_i (
        .clock(clock), .reset(reset), .hsync(video_hsync),
        .fast_select(gime_init1[5]),
        .write_msb(io_write && address == 16'hFF94),
        .write_lsb(io_write && address == 16'hFF95),
        .write_data(write_data), .timer_msb(gime_timer_msb),
        .timer_lsb(gime_timer_lsb), .blink(video_blink)
    );

    coco3_128k_ram #(.INIT_VALUE(8'h00)) ram_i (
        .clock(clock), .cpu_address(physical_address),
        .cpu_write_data(write_data), .cpu_write_enable(ram_write),
        .cpu_read_data(ram_data), .video_address(video_address),
        .video_read_data(video_read_data)
    );

    coco3_keyboard_matrix keyboard_matrix_i (
        .keys(keyboard_keys),
        .forced_shift(keyboard_shift),
        .shift_override(keyboard_shift_override),
        .columns(keyboard_columns),
        .rows(keyboard_rows)
    );

    assign debug_address = address;
    assign debug_vma = vma;
    assign debug_read = read_cycle;
    assign debug_opfetch = opfetch;
    assign debug_read_data = read_data;
    assign debug_ram_write = ram_write;
    assign debug_io_write = io_write;
    assign debug_write_data = write_data;
    assign audio_dac = sound_dac;
    assign video_vdg_control = pia1_outb[7:4];
    assign video_css = pia1_outb[3];
    assign video_border_palette = border_palette;
    assign video_mode = gime_video_mode;
    assign video_resolution = gime_video_resolution;
    assign video_vbank = gime_video_vbank;
    assign video_scroll = gime_video_scroll;
    assign video_offset = gime_video_offset;
    assign video_horizontal_offset = gime_video_horizontal_offset;
    generate
        for (palette_index = 0; palette_index < 16; palette_index = palette_index + 1) begin : flatten_palette
            assign video_palette[palette_index*6 +: 6] = palette[palette_index];
        end
    endgenerate
endmodule

`default_nettype wire
