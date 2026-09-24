`timescale 1ns/1ps
`default_nettype none
`include "gime_reference_dsk_loader_size.vh"

// Execute GIMEREF.BIN from a generated DECB disk through the production FDC.
// A small test-only ROM-Pak reads track 18/sector 1, loads the DECB payload,
// and jumps to it. This keeps the regression deterministic while exercising
// the real 6809, FDC sector buffer, RAM, and GIME I/O decode.
module gime_reference_dsk_load_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg cartridge_enabled = 1'b0;
    reg cartridge_launch = 1'b0;
    reg [14:0] cartridge_address = 15'h0000;
    reg [7:0] cartridge_write_data = 8'h00;
    reg cartridge_write = 1'b0;
    reg [7:0] loader [0:`GIME_REFERENCE_DSK_LOADER_SIZE-1];
    reg [7:0] disk_memory [0:161279];
    reg backend_done_toggle = 1'b0;
    reg backend_success = 1'b0;
    integer index;
    integer cycles = 0;
    integer disk_byte_address;
    wire [15:0] pc;
    wire [15:0] address;
    wire io_write;
    wire [7:0] write_data;
    wire [7:0] backend_buffer_address;
    wire [1:0] backend_drive;
    wire [7:0] backend_track;
    wire [7:0] backend_sector;
    wire backend_request_toggle;
    wire [7:0] backend_data;

    always #5 clock = ~clock;

    always @* begin
        disk_byte_address = ((backend_track * 18) + backend_sector - 1) * 256
                            + backend_buffer_address;
    end
    assign backend_data = (backend_drive == 0 && backend_sector >= 1 &&
                           backend_sector <= 18 && backend_track < 35)
                        ? disk_memory[disk_byte_address] : 8'hFF;

    coco3_boot_machine #(.CARTRIDGE_START_DELAY(10)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b1),
        .cpu_halt(1'b0), .cartridge_enabled(cartridge_enabled),
        .cartridge_launch(cartridge_launch),
        .cartridge_address(cartridge_address),
        .cartridge_write_data(cartridge_write_data),
        .cartridge_write(cartridge_write), .cold_start_clear(1'b0),
        .bin_fifo_data(8'h00), .bin_fifo_available(1'b0),
        .bin_transfer_active(1'b0), .bin_transfer_complete(1'b0),
        .bin_transfer_error(1'b0), .bin_fifo_pop(), .bin_loader_done(),
        .debug_address(address), .debug_pc(pc), .debug_vma(),
        .debug_read(), .debug_opfetch(), .debug_read_data(),
        .debug_ram_write(), .debug_io_write(io_write),
        .debug_write_data(write_data),
        .keyboard_keys(56'h0), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0), .joystick_left_x(6'd32),
        .joystick_left_y(6'd32), .joystick_left_fire(1'b0), .joystick_left_fire2(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0), .joystick_right_fire2(1'b0), .sd_status(8'h00),
        .sd_detail(8'h00), .video_hsync(1'b1), .pia_hsync(1'b1),
        .video_vsync(1'b1), .video_address(20'h00000),
        .video_read_data(), .audio_dac(), .video_vdg_control(),
        .video_css(), .video_palette(), .video_border_palette(),
        .video_mode(), .video_resolution(), .video_vbank(),
        .video_scroll(), .video_offset(), .video_horizontal_offset(),
        .video_blink(), .sd_drive_present(2'b01),
        .sd_fdc_done_toggle(backend_done_toggle),
        .sd_fdc_success(backend_success),
        .sd_fdc_write_done_toggle(1'b0),
        .sd_fdc_write_success(1'b0), .sd_fdc_data(backend_data),
        .sd_fdc_buffer_address(backend_buffer_address),
        .sd_fdc_drive(backend_drive), .sd_fdc_track(backend_track),
        .sd_fdc_sector(backend_sector), .sd_fdc_last_type1(),
        .sd_fdc_debug_word(), .sd_fdc_completed_debug_word(),
        .sd_fdc_read_complete_toggle(), .sd_fdc_write_strobe(),
        .sd_fdc_write_data(), .sd_fdc_write_complete_toggle(),
        .sd_fdc_request_toggle(backend_request_toggle)
    );

    // Make the requested sector visible through the owned 256-byte buffer,
    // then acknowledge the firmware/FDC toggle handshake.
    always @(posedge clock) begin
        if (reset) begin
            backend_done_toggle <= 1'b0;
            backend_success <= 1'b0;
        end else if (backend_done_toggle != backend_request_toggle) begin
            backend_success <= backend_drive == 0 && backend_track < 35 &&
                               backend_sector >= 1 && backend_sector <= 18;
            backend_done_toggle <= backend_request_toggle;
        end
    end

    task verify_gime_state;
        begin
            if (dut.gime_video_mode !== 8'h87 ||
                dut.gime_video_resolution !== 8'h7E ||
                dut.border_palette !== 6'h2A ||
                dut.gime_video_scroll !== 4'hB ||
                dut.gime_video_offset !== 16'h1234 ||
                dut.gime_video_horizontal_offset !== 8'h85 ||
                {dut.gime_timer_msb, dut.gime_timer_lsb} !== 12'h001)
                $fatal(1, "DSK launch GIME state mismatch VM=%02h VR=%02h B=%02h S=%01h O=%04h H=%02h T=%03h",
                       dut.gime_video_mode, dut.gime_video_resolution,
                       dut.border_palette, dut.gime_video_scroll,
                       dut.gime_video_offset, dut.gime_video_horizontal_offset,
                       {dut.gime_timer_msb, dut.gime_timer_lsb});
        end
    endtask

    initial begin
        $readmemh("gime_reference_dsk_loader.mem", loader);
        $readmemh("gime_reference.dsk.mem", disk_memory);

        for (index = 0; index < `GIME_REFERENCE_DSK_LOADER_SIZE;
             index = index + 1) begin
            @(negedge clock);
            cartridge_address = index[14:0];
            cartridge_write_data = loader[index];
            cartridge_write = 1'b1;
            @(posedge clock);
        end
        @(negedge clock);
        cartridge_write = 1'b0;

        // Start directly in the deterministic test ROM-Pak. Cartridge cold
        // launch sequencing is covered independently by the boot regressions.
        dut.rom_i.memory[15'h7FFE] = 8'hC0;
        dut.rom_i.memory[15'h7FFF] = 8'h00;
        cartridge_enabled = 1'b1;
        cartridge_launch = 1'b1;
        reset = 1'b0;
        repeat (2) @(posedge clock);
        @(negedge clock);
        cartridge_launch = 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (io_write && address == 16'hFF70 && write_data == 8'hA5) begin
                verify_gime_state();
                $display("PASS: GIME reference probe loaded and executed through DSK/FDC path");
                $finish;
            end
            if (io_write && address == 16'hFF70 && write_data == 8'hE1)
                $fatal(1, "DSK loader rejected the DECB record header");
            if (cycles == 2000000)
                $fatal(1, "DSK launch timeout pc=%04h track=%0d sector=%0d request=%0d done=%0d",
                       pc, backend_track, backend_sector,
                       backend_request_toggle, backend_done_toggle);
        end
    end
endmodule

`default_nettype wire
