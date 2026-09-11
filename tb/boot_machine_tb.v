`timescale 1ns/1ps
`default_nettype none

module boot_machine_tb;
    reg clock = 0;
    reg reset = 1;
    reg video_hsync = 1;
    reg video_vsync = 1;
    wire [15:0] address;
    wire vma, read_cycle, ram_write, io_write;
    wire [6:0] audio_dac;
    integer cycles = 0;
    integer ram_writes = 0;
    integer io_writes = 0;
    integer io_reads = 0;
    integer vector_reads = 0;
    integer active_cycles = 0;
    reg [15:0] history [0:15];
    integer history_pos = 0;
    integer h;
    integer copy_mismatches;
    integer copy_byte;
    reg [7:0] copied_value;
    reg saw_reset_target = 0;
    reg saw_disk_rom = 0;

    always #5 clock = ~clock;
    always #16000 video_hsync = ~video_hsync;
    always #420000 video_vsync = ~video_vsync;

    coco3_boot_machine dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b0), .cpu_halt(1'b0),
        .diagnostic_cartridge_enabled(1'b0), .debug_address(address),
        .debug_vma(vma), .debug_read(read_cycle),
        .debug_ram_write(ram_write), .debug_io_write(io_write),
        .debug_write_data(), .keyboard_keys(56'b0),
        .keyboard_shift(1'b0), .keyboard_shift_override(1'b0),
        .joystick_left_x(6'd32), .joystick_left_y(6'd32),
        .joystick_left_fire(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0), .sd_status(8'h00), .sd_detail(8'h00),
        .video_hsync(video_hsync),
        .video_vsync(video_vsync), .video_address(20'h00000),
        .video_read_data(), .audio_dac(audio_dac), .video_vdg_control(),
        .video_css(), .video_palette()
    );

    initial begin
        repeat (8) @(posedge clock);
        reset = 0;

        // The six-bit DAC must remain unchanged in bits 5:0 while PIA1 PB1
        // supplies the independent single-bit sound component in bit 6.
        @(negedge clock);
        force dut.sound_dac = 6'h15;
        force dut.pia1_outb = 8'h02;
        #1;
        if (audio_dac !== 7'h55) begin
            $display("FAIL: PB1 sound mix expected 55, got %02h", audio_dac);
            $finish;
        end
        force dut.pia1_outb = 8'h00;
        #1;
        if (audio_dac !== 7'h15) begin
            $display("FAIL: DAC-only audio expected 15, got %02h", audio_dac);
            $finish;
        end
        release dut.sound_dac;
        release dut.pia1_outb;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (vma && dut.active) begin
                history[history_pos] = address;
                history_pos = (history_pos + 1) & 15;
                active_cycles = active_cycles + 1;
            end
            if (dut.active && read_cycle && (address == 16'hFFFE || address == 16'hFFFF)) begin
                vector_reads = vector_reads + 1;
                if (vector_reads <= 12) begin
                    $write("VECTOR %04h history:", address);
                    for (h=0; h<16; h=h+1) $write(" %04h", history[(history_pos+h)&15]);
                    $display("");
                end
            end
            if (vma && read_cycle && address == 16'h8C1B)
                saw_reset_target = 1;
            if (vma && read_cycle && address >= 16'hC000 && address <= 16'hDFFF)
                saw_disk_rom = 1;
            if (ram_write) ram_writes = ram_writes + 1;
            if (io_write) io_writes = io_writes + 1;
            if (vma && read_cycle && address[15:8] == 8'hFF && address[7:4] != 4'hF) begin
                if (io_reads < 40) $display("IOREAD %04h", address);
                io_reads = io_reads + 1;
            end
            if (cycles == 5000000) begin
                $display("VIDEO STATE FF9B=%02h FF9C=%02h FF9F=%02h",
                    dut.gime_video_vbank, dut.gime_video_scroll, dut.gime_video_horizontal_offset);
                if (!saw_reset_target || !saw_disk_rom || ram_writes == 0 || io_writes == 0) begin
                    $display("FAIL: target=%0d disk=%0d RAM writes=%0d IO writes=%0d address=%04h",
                             saw_reset_target, saw_disk_rom, ram_writes, io_writes, address);
                    $finish;
                end
                $display("PASS: system and Disk BASIC ROMs entered; RAM writes=%0d IO writes=%0d vectors=%0d active=%0d address=%04h",
                         ram_writes, io_writes, vector_reads, active_cycles, address);
                $write("FINAL ACTIVE history:");
                for (h=0; h<16; h=h+1) $write(" %04h", history[(history_pos+h)&15]);
                $display("");
                $display("RAM physical $81E8: %02h %02h %02h %02h %02h %02h %02h %02h",
                    dut.ram_i.memory_low[16'h40f4], dut.ram_i.memory_high[16'h40f4],
                    dut.ram_i.memory_low[16'h40f5], dut.ram_i.memory_high[16'h40f5],
                    dut.ram_i.memory_low[16'h40f6], dut.ram_i.memory_high[16'h40f6],
                    dut.ram_i.memory_low[16'h40f7], dut.ram_i.memory_high[16'h40f7]);
                copy_mismatches = 0;
                for (copy_byte=0; copy_byte<16'h230; copy_byte=copy_byte+1) begin
                    copied_value = copy_byte[0] ?
                        dut.ram_i.memory_high[16'h4000+(copy_byte>>1)] :
                        dut.ram_i.memory_low[16'h4000+(copy_byte>>1)];
                    if (copied_value !== dut.rom_i.memory[16'h4000+copy_byte]) begin
                        if (copy_mismatches < 16)
                            $display("COPY MISMATCH +%04h ram=%02h rom=%02h", copy_byte,
                                copied_value, dut.rom_i.memory[16'h4000+copy_byte]);
                        copy_mismatches = copy_mismatches + 1;
                    end
                end
                $display("COPY CHECK mismatches=%0d/560", copy_mismatches);
                $finish;
            end
        end
    end
endmodule

`default_nettype wire
