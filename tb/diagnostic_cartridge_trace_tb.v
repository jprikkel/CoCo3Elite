`timescale 1ns/1ps
`default_nettype none

module diagnostic_cartridge_trace_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg video_hsync = 1'b1;
    reg video_vsync = 1'b1;
    wire [15:0] address;
    wire vma, read_cycle, ram_write, io_write;
    wire [7:0] write_data;
    integer cycles = 0;
    integer trace_file;
    integer cart_reads = 0;
    integer io_events = 0;
    reg saw_firq = 1'b0;
    reg saw_cart_entry = 1'b0;

    always #5 clock = ~clock;
    always #16000 video_hsync = ~video_hsync;
    always #420000 video_vsync = ~video_vsync;

    coco3_boot_machine #(.CARTRIDGE_START_DELAY(2519999)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b0),
        .diagnostic_cartridge_enabled(1'b1),
        .debug_address(address), .debug_vma(vma),
        .debug_read(read_cycle), .debug_ram_write(ram_write),
        .debug_io_write(io_write), .debug_write_data(write_data),
        .keyboard_keys(56'b0), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0),
        .joystick_left_x(6'd32), .joystick_left_y(6'd32),
        .joystick_left_fire(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0),
        .sd_status(8'hff), .sd_detail(8'hff),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .video_address(20'h0), .video_read_data(), .audio_dac()
    );

    initial begin
        trace_file = $fopen("diagnostic_cartridge_trace.log", "w");
        repeat (20) @(posedge clock);
        reset <= 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (dut.cpu_firq) begin
                saw_firq = 1'b1;
            end
            if (cycles == 60000000) begin
                $fdisplay(trace_file,
                          "SUMMARY firq=%0d entry=%0d cart_reads=%0d io_events=%0d final=%04h",
                          saw_firq, saw_cart_entry, cart_reads, io_events, address);
                $fclose(trace_file);
                if (!saw_cart_entry)
                    $fatal(1, "Diagnostic cartridge did not enter $C000");
                $display("PASS: trace written; FIRQ=%0d C000=%0d cart reads=%0d",
                         saw_firq, saw_cart_entry, cart_reads);
                $finish;
            end
        end
    end

    // Sample halfway through the CPU's enabled bus cycle. At this point the
    // synchronous BRAM output corresponds to the stable address that the CPU
    // will consume on the following rising edge.
    always @(negedge clock) begin
        if (!reset && !dut.hold && vma) begin
            if (dut.cpu_firq)
                $fdisplay(trace_file, "%0d FIRQ address=%04h crb=%02h latch=%b",
                          cycles, address, dut.pia1_crb, dut.cartridge_irq_latch);
            if (!read_cycle && address[15:8] == 8'hff) begin
                io_events = io_events + 1;
                if ((address >= 16'hff00 && address <= 16'hff23) ||
                    (address >= 16'hff90 && address <= 16'hffbf) ||
                    (address >= 16'hffc0 && address <= 16'hffdf))
                    $fdisplay(trace_file, "%0d WRITE %04h=%02h",
                              cycles, address, write_data);
            end
            if (read_cycle && (address == 16'hff22 || address == 16'hff23))
                $fdisplay(trace_file, "%0d READ  %04h data=%02h",
                          cycles, address, dut.io_read_data);
            if (read_cycle && address >= 16'hc000 && address <= 16'hdfff) begin
                cart_reads = cart_reads + 1;
                if (address == 16'hc000) saw_cart_entry = 1'b1;
                if (cart_reads <= 512)
                    $fdisplay(trace_file, "%0d CART  %04h data=%02h",
                              cycles, address, dut.read_data);
            end
        end
    end
endmodule

`default_nettype wire
