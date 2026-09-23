`timescale 1ns/1ps
`default_nettype none

// Executes the project-owned ELITEMEM cartridge directly through the real
// MC6809 and CoCo memory/MMU datapath. Each invocation selects one menu suite
// through the normal keyboard matrix and requires every emitted result to pass.
module elite_memory_diagnostic_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg cartridge_enabled = 1'b1;
    reg cartridge_launch = 1'b1;
    reg [55:0] keyboard_keys = 56'd0;
    reg pia_hsync = 1'b1;
    reg video_vsync = 1'b1;
    reg [7:0] cartridge [0:8191];
    reg [7:0] mailbox [0:7];
    integer index;
    integer cycles = 0;
    integer records = 0;
    integer expected_records = 4;
    integer selected_key = 17; // Q
    reg [7:0] expected_mode = 8'h40;
    integer key_hold = 0;
    integer key_delay = 0;
    integer page_writes [0:15];
    reg count_page_writes = 1'b0;
    reg selection_only = 1'b0;
    reg [8*8-1:0] suite_name = "QUICK";
    wire [15:0] address;
    wire [15:0] pc;
    wire io_write;
    wire [7:0] write_data;

    always #5 clock = ~clock;

    coco3_boot_machine #(.CARTRIDGE_START_DELAY(10)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b1), .cpu_halt(1'b0),
        .cartridge_enabled(cartridge_enabled),
        .cartridge_launch(cartridge_launch),
        .cartridge_address(15'd0), .cartridge_write_data(8'd0),
        .cartridge_write(1'b0), .cold_start_clear(1'b0),
        .bin_fifo_data(8'd0), .bin_fifo_available(1'b0),
        .bin_transfer_active(1'b0), .bin_transfer_complete(1'b0),
        .bin_transfer_error(1'b0), .bin_fifo_pop(), .bin_loader_done(),
        .debug_address(address), .debug_pc(pc), .debug_vma(),
        .debug_read(), .debug_opfetch(), .debug_read_data(),
        .debug_ram_write(), .debug_io_write(io_write),
        .debug_write_data(write_data),
        .keyboard_keys(keyboard_keys), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0), .joystick_left_x(6'd32),
        .joystick_left_y(6'd32), .joystick_left_fire(1'b0), .joystick_left_fire2(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0), .joystick_right_fire2(1'b0),
        .sd_status(8'd0), .sd_detail(8'd0),
        .video_hsync(pia_hsync), .pia_hsync(pia_hsync),
        .video_vsync(video_vsync), .video_address(20'd0),
        .video_read_data(), .audio_dac(), .video_vdg_control(),
        .video_css(), .video_palette(), .video_border_palette(),
        .video_mode(), .video_resolution(), .video_vbank(), .video_scroll(),
        .video_offset(), .video_horizontal_offset(), .video_blink(),
        .sd_drive_present(3'd0), .sd_fdc_done_toggle(1'b0),
        .sd_fdc_success(1'b0), .sd_fdc_write_done_toggle(1'b0),
        .sd_fdc_write_success(1'b0), .sd_fdc_data(8'd0),
        .sd_fdc_buffer_address(), .sd_fdc_drive(), .sd_fdc_track(),
        .sd_fdc_sector(), .sd_fdc_last_type1(), .sd_fdc_debug_word(),
        .sd_fdc_completed_debug_word(), .sd_fdc_read_complete_toggle(),
        .sd_fdc_write_strobe(), .sd_fdc_write_data(),
        .sd_fdc_write_complete_toggle(), .sd_fdc_request_toggle()
    );

    function [7:0] physical_byte;
        input [16:0] byte_address;
        begin
            if (byte_address[0])
                physical_byte = dut.ram_i.memory_high[byte_address[16:1]];
            else
                physical_byte = dut.ram_i.memory_low[byte_address[16:1]];
        end
    endfunction

    initial begin
        if ($test$plusargs("SUITE_LONG")) begin
            expected_records = 2;
            selected_key = 12; // L
            expected_mode = 8'h80;
            suite_name = "LONG";
        end else if ($test$plusargs("SUITE_ALL")) begin
            expected_records = 6;
            selected_key = 1; // A
            expected_mode = 8'hC0;
            suite_name = "ALL";
        end
        if ($test$plusargs("SELECTION_ONLY"))
            selection_only = 1'b1;
        for (index = 0; index < 8; index = index + 1)
            mailbox[index] = 8'd0;
        for (index = 0; index < 16; index = index + 1)
            page_writes[index] = 0;
        $readmemh("elite_memory_cart.mem", cartridge);
        for (index = 0; index < 8192; index = index + 1)
            dut.cartridge_i.memory[index] = cartridge[index];
        repeat (4) @(posedge clock);
        // Bypass a lengthy BASIC boot only in this focused regression. The
        // production F12 cartridge launch path is covered separately.
        dut.rom_i.memory[15'h7FFE] = 8'hC0;
        dut.rom_i.memory[15'h7FFF] = 8'h00;
        @(negedge clock);
        reset = 1'b0;
        repeat (2) @(posedge clock);
        @(negedge clock);
        cartridge_launch = 1'b0;
    end

    // Logical raster edges exercise the same GIME event/status path while the
    // cartridge performs its memory test.
    integer raster_clock = 0;
    integer raster_line = 0;
    always @(posedge clock) begin
        if (reset) begin
            raster_clock <= 0;
            raster_line <= 0;
            pia_hsync <= 1'b1;
            video_vsync <= 1'b1;
        end else begin
            raster_clock <= raster_clock + 1;
            pia_hsync <= raster_clock >= 8;
            video_vsync <= !(raster_line >= 240 && raster_line < 243);
            if (raster_clock == 79) begin
                raster_clock <= 0;
                if (raster_line == 261)
                    raster_line <= 0;
                else
                    raster_line <= raster_line + 1;
            end
        end
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (key_delay > 0) begin
                key_delay = key_delay - 1;
                if (key_delay == 0) begin
                    keyboard_keys[selected_key] = 1'b1;
                    key_hold = 20000;
                end
            end
            if (key_hold > 0) begin
                key_hold = key_hold - 1;
                if (key_hold == 0)
                    keyboard_keys = 56'd0;
            end
            if (io_write && address >= 16'hFF70 && address <= 16'hFF77)
                mailbox[address[2:0]] <= write_data;

            if (io_write && address == 16'hFF70 && write_data == 8'h4D) begin
                $display("ELITEMEM menu ready pc=%04h", pc);
                key_delay = 20000;
            end

            if (io_write && address == 16'hFF70 && write_data == 8'h50 &&
                selection_only) begin
                if (mailbox[1] !== expected_mode)
                    $fatal(1, "%s menu selected mode %02h", suite_name, mailbox[1]);
                $display("PASS: ELITEMEM %s menu selection", suite_name);
                $finish;
            end
            if (io_write && address == 16'hFF70 && write_data == 8'h50)
                count_page_writes = 1'b1;

            if (count_page_writes && dut.ram_write)
                page_writes[dut.physical_address[16:13]] =
                    page_writes[dut.physical_address[16:13]] + 1;

            if (io_write && address == 16'hFF70 && write_data == 8'h51)
                $display("ELITEMEM phase %0d result=%02h", mailbox[1], mailbox[2]);
            if (io_write && address == 16'hFF70 && write_data == 8'h52)
                $display("ELITEMEM first failure page=%0d address=%02h%02h value=%02h%02h pc=%04h",
                         mailbox[3], mailbox[4], mailbox[5], mailbox[6], mailbox[7], pc);
            if (io_write && address == 16'hFF70 && write_data == 8'h54) begin
                count_page_writes = 1'b0;
                for (index = 0; index < 16; index = index + 1)
                    if (page_writes[index] != 8192 ||
                        physical_byte(index * 8192) !== 8'h00 ||
                        physical_byte(index * 8192 + 1) !== 8'h00)
                        $display("ELITEMEM init page %0d writes=%0d begins %02h%02h",
                                 index, page_writes[index],
                                 physical_byte(index * 8192),
                                 physical_byte(index * 8192 + 1));
            end

            if (io_write && address == 16'hFF70 && write_data == 8'h44) begin
                if (mailbox[1] !== records + 1)
                    $fatal(1, "%s sequence expected=%0d got=%0d",
                           suite_name, records + 1, mailbox[1]);
                if (mailbox[2] !== 8'h00)
                    $fatal(1, "%s memory test %0d failed code=%02h",
                           suite_name, mailbox[1], mailbox[2]);
                records = records + 1;
            end

            if (io_write && address == 16'hFF70 && write_data == 8'h53) begin
                if (records != expected_records ||
                    mailbox[1] !== expected_records ||
                    mailbox[3] !== expected_records || mailbox[4] !== 0)
                    $fatal(1, "%s summary records=%0d total=%0d pass=%0d fail=%0d",
                           suite_name, records, mailbox[1], mailbox[3], mailbox[4]);
                if (mailbox[5] !== 8'hA5 || mailbox[6] !== 8'h5A ||
                    mailbox[7] !== 8'h87)
                    $fatal(1, "%s telemetry signature mismatch", suite_name);
                if (dut.gime_video_mode !== 8'h03 ||
                    dut.gime_video_resolution !== 8'h34 ||
                    dut.gime_video_offset !== 16'hE400)
                    $fatal(1, "%s did not restore native 80-column output", suite_name);
                if (physical_byte(17'h12009) !== " " ||
                    physical_byte(17'h1200A) !== "C" ||
                    physical_byte(17'h1200B) !== "o")
                    $fatal(1, "%s result title/indentation mismatch", suite_name);
                // Long and All finish March C- with zero in untouched page 0.
                if (selected_key != 17 &&
                    (physical_byte(17'h00100) !== 8'h00 ||
                     physical_byte(17'h1E100) !== 8'h00))
                    $fatal(1, "%s final March state mismatch", suite_name);
                $display("PASS: ELITEMEM %s suite reported %0d passing full-memory tests",
                         suite_name, records);
                $finish;
            end

            if (cycles == 250000000)
                $fatal(1, "%s timeout pc=%04h records=%0d", suite_name, pc, records);
            if (selection_only && cycles == 2000000)
                $fatal(1, "%s menu selection timeout pc=%04h mapped=%0d",
                       suite_name, pc, dut.cartridge_mapped);
        end
    end
endmodule

`default_nettype wire
