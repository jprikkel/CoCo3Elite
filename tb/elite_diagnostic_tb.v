`timescale 1ns/1ps
`default_nettype none
`include "elite_diagnostic_size.vh"
`include "decb_bin_loader_size.vh"

// Runs ELITEDIAG through the production F12 direct-BIN loader and real 6809
// bus.  The program itself supplies the checks; this bench verifies every
// serial record and the visible 80-column result screen.
module elite_diagnostic_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg cartridge_enabled = 1'b0;
    reg cartridge_launch = 1'b0;
    reg [14:0] cartridge_address = 15'd0;
    reg [7:0] cartridge_write_data = 8'd0;
    reg cartridge_write = 1'b0;
    reg pia_hsync = 1'b1;
    reg video_vsync = 1'b1;
    reg [55:0] keyboard_keys = 56'd0;
    reg [7:0] loader [0:8191];
    reg [7:0] stream [0:`ELITE_DIAGNOSTIC_BIN_SIZE-1];
    reg [7:0] mailbox [0:7];
    integer loader_size;
    integer index;
    integer stream_index = 0;
    integer cycles = 0;
    integer raster_clock = 0;
    integer raster_line = 0;
    integer record_count = 0;
    integer page_count = 0;
    integer key_delay = 0;
    integer key_hold = 0;
    integer summary_row;
    reg summary_found;
    reg serial_pattern_seen = 1'b0;
    wire [15:0] address;
    wire [15:0] pc;
    wire io_write;
    wire [7:0] write_data;
    wire bin_fifo_pop;
    wire bin_loader_done;

    always #5 clock = ~clock;

    coco3_boot_machine #(.CARTRIDGE_START_DELAY(10)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b1),
        .cpu_halt(1'b0), .cartridge_enabled(cartridge_enabled),
        .cartridge_launch(cartridge_launch),
        .cartridge_address(cartridge_address),
        .cartridge_write_data(cartridge_write_data),
        .cartridge_write(cartridge_write), .cold_start_clear(1'b0),
        .bin_fifo_data(stream[stream_index]),
        .bin_fifo_available(stream_index < `ELITE_DIAGNOSTIC_BIN_SIZE),
        .bin_transfer_active(1'b1), .bin_transfer_complete(1'b1),
        .bin_transfer_error(1'b0), .bin_fifo_pop(bin_fifo_pop),
        .bin_loader_done(bin_loader_done), .debug_address(address),
        .debug_pc(pc), .debug_vma(), .debug_read(), .debug_opfetch(),
        .debug_read_data(), .debug_ram_write(), .debug_io_write(io_write),
        .debug_write_data(write_data),
        .keyboard_keys(keyboard_keys), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0), .joystick_left_x(6'd32),
        .joystick_left_y(6'd32), .joystick_left_fire(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0), .sd_status(8'd0),
        .sd_detail(8'd0), .video_hsync(pia_hsync),
        .pia_hsync(pia_hsync), .video_vsync(video_vsync),
        .video_address(20'd0), .video_read_data(), .audio_dac(),
        .video_vdg_control(), .video_css(), .video_palette(),
        .video_border_palette(), .video_mode(), .video_resolution(),
        .video_vbank(), .video_scroll(), .video_offset(),
        .video_horizontal_offset(), .video_blink(),
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
        for (index = 0; index < 8; index = index + 1)
            mailbox[index] = 8'd0;
        $readmemh("decb_bin_loader.mem", loader);
        $readmemh("elite_diagnostic.mem", stream);
        loader_size = `DECB_BIN_LOADER_SIZE;
        for (index = 0; index < loader_size; index = index + 1) begin
            @(negedge clock);
            cartridge_address = index[14:0];
            cartridge_write_data = loader[index];
            cartridge_write = 1'b1;
            @(posedge clock);
        end
        @(negedge clock);
        cartridge_write = 1'b0;
        dut.rom_i.memory[15'h7FFE] = 8'hC0;
        dut.rom_i.memory[15'h7FFF] = 8'h00;
        cartridge_enabled = 1'b1;
        cartridge_launch = 1'b1;
        reset = 1'b0;
        repeat (2) @(posedge clock);
        @(negedge clock);
        cartridge_launch = 1'b0;
    end

    // Compact but realistic logical raster.  Both falling edges are consumed
    // by the same GIME event path used by hardware.
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
                    keyboard_keys[1] <= 1'b1; // A key
                    key_hold = 20000;
                end
            end else if (key_hold > 0) begin
                key_hold = key_hold - 1;
                if (key_hold == 0)
                    keyboard_keys[1] <= 1'b0;
            end
            if (bin_fifo_pop && stream_index < `ELITE_DIAGNOSTIC_BIN_SIZE)
                stream_index <= stream_index + 1;
            if (bin_loader_done) begin
                cartridge_enabled <= 1'b0;
                // The bench redirects reset to the temporary loader only to
                // avoid simulating a full BASIC boot.  Real hardware never
                // changes ROM, so restore the production reset vector before
                // ELITEDIAG reaches its ROM/vector checks.
                dut.rom_i.memory[15'h7FFE] <= 8'h8C;
                dut.rom_i.memory[15'h7FFF] <= 8'h1B;
            end

            if (io_write && address >= 16'hFF70 && address <= 16'hFF77)
                mailbox[address[2:0]] <= write_data;
            if (io_write && address == 16'hFF75 && write_data == 8'hA5)
                serial_pattern_seen <= 1'b1;

            if (io_write && address == 16'hFF70 && write_data == 8'h45) begin
                page_count = page_count + 1;
                if (physical_byte(17'h1278A) !== "P" ||
                    physical_byte(17'h1278B) !== "r")
                    $fatal(1, "diagnostic page prompt is not visible");
                key_delay = 20000;
            end

            if (io_write && address == 16'hFF70 && write_data == 8'h44) begin
                if (mailbox[1] !== record_count + 1)
                    $fatal(1, "diagnostic record sequence expected=%0d got=%0d",
                           record_count + 1, mailbox[1]);
                if (mailbox[2] !== 8'h00)
                    $fatal(1, "ELITEDIAG test %0d reported FAIL code=%02h",
                           mailbox[1], mailbox[2]);
                record_count = record_count + 1;
            end

            if (io_write && address == 16'hFF70 && write_data == 8'h53) begin
                if (record_count != 22 || mailbox[1] !== 8'd22 ||
                    mailbox[3] !== 8'd22 || mailbox[4] !== 8'd0)
                    $fatal(1, "diagnostic summary records=%0d total=%0d pass=%0d fail=%0d",
                           record_count, mailbox[1], mailbox[3], mailbox[4]);
                if (page_count != 1)
                    $fatal(1, "diagnostic pagination count expected=1 got=%0d",
                           page_count);
                if (!serial_pattern_seen || mailbox[5] !== 8'hA5 ||
                    mailbox[6] !== 8'h5A || mailbox[7] !== 8'h87)
                    $fatal(1, "serial telemetry pattern mismatch %02h %02h %02h",
                           mailbox[5], mailbox[6], mailbox[7]);
                if (stream_index != `ELITE_DIAGNOSTIC_BIN_SIZE)
                    $fatal(1, "diagnostic BIN stream incomplete %0d/%0d",
                           stream_index, `ELITE_DIAGNOSTIC_BIN_SIZE);
                if (dut.gime_video_mode !== 8'h03 ||
                    dut.gime_video_resolution !== 8'h34 ||
                    dut.gime_video_offset !== 16'hE400)
                    $fatal(1, "final 80-column GIME state mismatch VM=%02h VR=%02h O=%04h",
                           dut.gime_video_mode, dut.gime_video_resolution,
                           dut.gime_video_offset);
                // Physical $72000 aliases to $12000 in the installed 128 KiB.
                // Verify the continuation title and ten-space indentation.
                if (physical_byte(17'h12009) !== " " ||
                    physical_byte(17'h1200A) !== "C" ||
                    physical_byte(17'h1200B) !== "o")
                    $fatal(1, "80-column title/indentation mismatch");
                summary_found = 1'b0;
                for (summary_row = 0; summary_row < 25;
                     summary_row = summary_row + 1) begin
                    if (physical_byte(17'h12000 + summary_row * 80 + 10) == "S" &&
                        physical_byte(17'h12000 + summary_row * 80 + 11) == "u")
                        summary_found = 1'b1;
                end
                if (!summary_found)
                    $fatal(1, "visible summary line was not found");
                $display("PASS: ELITEDIAG paged report produced 22 PASS results in native 80-column text");
                $finish;
            end

            if (cycles == 60000000)
                $fatal(1, "ELITEDIAG timeout pc=%04h stream=%0d/%0d records=%0d",
                       pc, stream_index, `ELITE_DIAGNOSTIC_BIN_SIZE,
                       record_count);
        end
    end
endmodule

`default_nettype wire
