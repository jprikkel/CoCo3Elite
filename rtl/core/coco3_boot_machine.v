`timescale 1ns/1ps
`default_nettype none

// Early real-ROM execution boundary. Peripheral reads are deliberately idle;
// GIME/MMU and PIA behavior will be added as boot tracing identifies needs.
module coco3_boot_machine (
    input  wire        clock,
    input  wire        reset,
    output wire [15:0] debug_address,
    output wire        debug_vma,
    output wire        debug_read,
    output wire        debug_ram_write,
    output wire        debug_io_write,
    output wire [7:0]  debug_write_data,
    input  wire [55:0] keyboard_keys,
    input  wire        keyboard_shift,
    input  wire        keyboard_shift_override,
    input  wire        video_hsync,
    input  wire        video_vsync,
    input  wire [19:0] video_address,
    output wire [15:0] video_read_data
);
    reg [3:0] divider;
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
    reg [7:0] mmu [0:15];
    integer index;

    wire vma;
    wire [15:0] address;
    wire read_cycle;
    wire [7:0] write_data;
    wire [7:0] ram_data;
    wire [7:0] rom_data;
    wire [7:0] disk_rom_data;
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
    // The legacy design always services $FFF0-$FFFF from its dedicated fast
    // vector shadow, even after SAM selects all-RAM mode.
    wire rom_select = vector_select ||
                      (!all_ram && !io_select && address[15]);
    wire [7:0] mapped_page = mmu_enable
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
    wire ram_write = active && !read_cycle && !io_select && !rom_select;
    wire io_write = active && !read_cycle && io_select;
    wire [7:0] keyboard_columns =
        (pia0_outb & pia0_ddrb) | (~pia0_ddrb);
    wire [7:0] keyboard_rows;
    reg [7:0] io_read_data;
    wire [7:0] read_data = io_select ? io_read_data :
                             (disk_rom_select ? disk_rom_data :
                             (rom_select ? rom_data : ram_data));

    always @* begin
        io_read_data = 8'hFF;
        case (address)
            16'hFF00: io_read_data = pia0_cra[2]
                ? ((pia0_outa & pia0_ddra) |
                   (keyboard_rows & ~pia0_ddra)) : pia0_ddra;
            16'hFF01: io_read_data = {pia0_hsync_event, 3'b011, pia0_cra[3:0]};
            16'hFF02: io_read_data = pia0_crb[2]
                ? ((pia0_outb & pia0_ddrb) | (~pia0_ddrb)) : pia0_ddrb;
            16'hFF03: io_read_data = {pia0_vsync_event, 3'b011, pia0_crb[3:0]};
            16'hFF90: io_read_data = gime_init0;
            16'hFF91: io_read_data = gime_init1;
            default: begin
                if (address == 16'hFF40 ||
                    (address >= 16'hFF48 && address <= 16'hFF4B))
                    io_read_data = fdc_read_data;
                else if (address >= 16'hFFA0 && address <= 16'hFFAF)
                    io_read_data = mmu[address[3:0]];
            end
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            divider <= 0;
            hold <= 1'b1;
        end else if (divider == 13) begin
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
            for (index = 0; index < 16; index = index + 1)
                mmu[index] <= 8'h00;
        end else if (io_write) begin
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
            if (address == 16'hFF90) begin
                gime_init0 <= write_data;
                mmu_enable <= write_data[6];
            end
            if (address == 16'hFF91) begin
                gime_init1 <= write_data;
                mmu_task <= write_data[0];
            end
            if (address >= 16'hFFA0 && address <= 16'hFFAF)
                mmu[address[3:0]] <= write_data;
            if (address == 16'hFFDE)
                all_ram <= 1'b0;
            if (address == 16'hFFDF)
                all_ram <= 1'b1;
        end
    end

    cpu09 cpu_i (
        .clk(clock), .rst(reset), .vma(vma), .lic_out(), .ifetch(),
        .opfetch(), .ba(), .bs(), .addr(address), .rw(read_cycle),
        .data_out(write_data), .data_in(read_data), .irq(cpu_irq),
        .firq(1'b0), .nmi(fdc_nmi), .halt(1'b0), .hold(hold)
    );

    coco3_system_rom rom_i (
        .clock(clock), .address(address[14:0]), .data(rom_data)
    );

    coco3_disk_rom disk_rom_i (
        .clock(clock), .address(address[12:0]), .data(disk_rom_data)
    );

    coco3_fdc fdc_i (
        .clock(clock), .reset(reset), .io_read(io_read), .io_write(io_write),
        .address(address), .write_data(write_data),
        .read_data(fdc_read_data), .nmi(fdc_nmi)
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
    assign debug_ram_write = ram_write;
    assign debug_io_write = io_write;
    assign debug_write_data = write_data;
endmodule

`default_nettype wire
