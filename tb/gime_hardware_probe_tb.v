`timescale 1ns/1ps
`default_nettype none
`include "gime_hardware_probe_size.vh"
`include "decb_bin_loader_size.vh"

// Proves that the hardware raster probe survives the production direct-BIN
// transport, fills its screen buffer, programs the expected GIME mode, and
// publishes its first serial mailbox record. Exact raster behavior is then
// measured on hardware by the passive UART fields.
module gime_hardware_probe_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg cartridge_enabled = 1'b0;
    reg cartridge_launch = 1'b0;
    reg [14:0] cartridge_address = 15'd0;
    reg [7:0] cartridge_write_data = 8'd0;
    reg cartridge_write = 1'b0;
    reg [7:0] loader [0:8191];
    reg [7:0] stream [0:`GIME_HARDWARE_PROBE_BIN_SIZE-1];
    integer loader_size;
    integer index;
    integer stream_index = 0;
    integer cycles = 0;
    integer screen_writes = 0;
    reg first_byte_seen = 1'b0;
    reg second_row_seen = 1'b0;
    wire [15:0] address;
    wire [15:0] pc;
    wire vma;
    wire read_cycle;
    wire ram_write;
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
        .bin_fifo_available(stream_index < `GIME_HARDWARE_PROBE_BIN_SIZE),
        .bin_transfer_active(1'b1), .bin_transfer_complete(1'b1),
        .bin_transfer_error(1'b0), .bin_fifo_pop(bin_fifo_pop),
        .bin_loader_done(bin_loader_done), .debug_address(address),
        .debug_pc(pc), .debug_vma(vma), .debug_read(read_cycle),
        .debug_opfetch(), .debug_read_data(), .debug_ram_write(ram_write),
        .debug_io_write(io_write), .debug_write_data(write_data),
        .keyboard_keys(56'd0),
        .keyboard_shift(1'b0), .keyboard_shift_override(1'b0),
        .joystick_left_x(6'd32), .joystick_left_y(6'd32),
        .joystick_left_fire(1'b0), .joystick_right_x(6'd32),
        .joystick_right_y(6'd32), .joystick_right_fire(1'b0),
        .sd_status(8'd0), .sd_detail(8'd0), .video_hsync(1'b1),
        .pia_hsync(1'b1), .video_vsync(1'b1),
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

    initial begin
        $readmemh("decb_bin_loader.mem", loader);
        $readmemh("gime_hardware_probe.mem", stream);
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

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (bin_fifo_pop && stream_index < `GIME_HARDWARE_PROBE_BIN_SIZE)
                stream_index <= stream_index + 1;
            if (bin_loader_done)
                cartridge_enabled <= 1'b0;
            if (ram_write && address >= 16'h2000 && address < 16'h5e80) begin
                screen_writes = screen_writes + 1;
                if (address == 16'h2000 && write_data == 8'h1b)
                    first_byte_seen = 1'b1;
                if (address == 16'h2050 && write_data == 8'he4)
                    second_row_seen = 1'b1;
            end
            if (io_write && address == 16'hff70 && write_data == 8'h47) begin
                if (stream_index != `GIME_HARDWARE_PROBE_BIN_SIZE)
                    $fatal(1, "probe BIN stream incomplete %0d/%0d",
                           stream_index, `GIME_HARDWARE_PROBE_BIN_SIZE);
                if (screen_writes != 16000 || !first_byte_seen ||
                    !second_row_seen)
                    $fatal(1, "probe screen fill mismatch writes=%0d first=%0d row2=%0d",
                           screen_writes, first_byte_seen, second_row_seen);
                if (dut.gime_video_mode != 8'h80 ||
                    dut.gime_video_resolution != 8'h35 ||
                    dut.gime_video_offset != 16'he400)
                    $fatal(1, "probe GIME setup mismatch VM=%02h VR=%02h O=%04h",
                           dut.gime_video_mode, dut.gime_video_resolution,
                           dut.gime_video_offset);
                $display("PASS: 1987 GIME hardware probe loads, fills video RAM, and publishes telemetry");
                $finish;
            end
            if (cycles == 5000000)
                $fatal(1, "GIME hardware probe timeout pc=%04h stream=%0d/%0d",
                       pc, stream_index, `GIME_HARDWARE_PROBE_BIN_SIZE);
        end
    end
endmodule

`default_nettype wire
