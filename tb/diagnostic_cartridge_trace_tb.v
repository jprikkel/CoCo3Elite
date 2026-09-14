`timescale 1ns/1ps
`default_nettype none

module diagnostic_cartridge_trace_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg video_hsync = 1'b1;
    reg pia_hsync = 1'b1;
    reg video_vsync = 1'b1;
    reg cartridge_enabled = 1'b0;
    reg cartridge_launch = 1'b0;
    reg cpu_halt = 1'b0;
    wire [15:0] address;
    wire [111:0] cpu_registers = dut.cpu_i.registers;
    wire vma, read_cycle, opfetch, ram_write, io_write;
    wire [7:0] write_data;
    integer cycles = 0;
    integer max_cycles = 40000000;
    integer trace_file;
    integer cart_reads = 0;
    integer io_events = 0;
    integer launch_opcode_count = 0;
    integer cartridge_pc_samples = 0;
    reg saw_firq = 1'b0;
    reg saw_cart_signal = 1'b0;
    reg cart_event_seen = 1'b0;
    reg [15:0] previous_trace_pc = 16'hffff;
    reg saw_cart_entry = 1'b0;
    reg [7:0] prelaunch_init0;
    reg prelaunch_all_ram;
    reg fast_mode = 1'b0;
    reg long_trace_mode = 1'b0;
    reg music_check_mode = 1'b0;
    reg music_irq_enabled = 1'b0;
    reg [7:0] music_previous_dac = 8'h02;
    integer music_dac_changes = 0;
    integer music_keyboard_scans = 0;
    reg [15:0] history_address [0:255];
    reg [15:0] history_pc [0:255];
    reg [15:0] history_stack [0:255];
    reg [7:0] history_data [0:255];
    reg history_read [0:255];
    reg history_opfetch [0:255];
    integer history_index = 0;
    integer history_count = 0;
    integer history_dump_index;
    integer history_slot;
    integer boot_wait_cycles = 0;

    // Match the production 25.2 MHz pixel clock and 640x480/60 raster.  The
    // old 100 MHz clock and 1.19 kHz VSYNC made CPU/PIA interrupt timing in
    // this test fundamentally different from hardware.
    always #19.84127 clock = ~clock;
    always #15873.016 video_hsync = ~video_hsync;
    always #31746.032 pia_hsync = ~pia_hsync;
    always #8333333.333 video_vsync = ~video_vsync;

    // Let BASIC initialize, present the cartridge while halted, and release
    // the CPU to service the normal CART/FIRQ path. PIAs, GIME, RAM, video,
    // and CPU state must not be reset by the manager.
    coco3_boot_machine #(.CARTRIDGE_START_DELAY(999)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(fast_mode), .cpu_halt(cpu_halt),
        .cartridge_enabled(cartridge_enabled), .cartridge_launch(cartridge_launch),
        .cartridge_address(15'd0), .cartridge_write_data(8'd0),
        .cartridge_write(1'b0), .cold_start_clear(1'b0),
        .debug_address(address),
        .debug_vma(vma),
        .debug_read(read_cycle), .debug_opfetch(opfetch), .debug_ram_write(ram_write),
        .debug_io_write(io_write), .debug_write_data(write_data),
        .keyboard_keys(56'b0), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0),
        .joystick_left_x(6'd32), .joystick_left_y(6'd32),
        .joystick_left_fire(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0),
        .sd_status(8'hff), .sd_detail(8'hff),
        .video_hsync(video_hsync), .pia_hsync(pia_hsync),
        .video_vsync(video_vsync),
        .video_address(20'h0), .video_read_data(), .audio_dac()
    );

    initial begin
        if ($test$plusargs("LONG_TRACE")) begin
            max_cycles = 160000000;
            long_trace_mode = 1'b1;
        end
        if ($test$plusargs("FAST"))
            fast_mode = 1'b1;
        if ($test$plusargs("MUSIC_CHECK")) begin
            music_check_mode = 1'b1;
            if (!long_trace_mode)
                max_cycles = 80000000;
        end
        // The firmware normally fills this RAM through its manager port.
        // Preload it here so this trace isolates the CoCo CART/FIRQ protocol.
        $readmemh("build/roms/diagnostic_cart.mem", dut.cartridge_i.memory);
        trace_file = $fopen("diagnostic_cartridge_trace.log", "w");
        repeat (20) @(posedge clock);
        reset <= 1'b0;
        // Wait for the steady Disk BASIC keyboard loop, not a fixed wall-clock
        // delay.  Normal and fast CPU modes take different times to reach it;
        // launching normal mode early leaves INIT0 and the PIAs mid-boot.
        while (!((cpu_registers[111:96] >= 16'ha7d3) &&
                 (cpu_registers[111:96] <= 16'ha7d7) &&
                 (dut.pia1_crb == 6'h37))) begin
            @(posedge clock);
            boot_wait_cycles = boot_wait_cycles + 1;
            if (boot_wait_cycles == 30000000)
                $fatal(1, "Disk BASIC did not reach its idle keyboard loop");
        end
        $display("PRE-LAUNCH PC=%04h CC=%02h INIT0=%02h PIA1CRB=%02h ALLRAM=%b",
                 cpu_registers[111:96], cpu_registers[87:80], dut.gime_init0,
                 dut.pia1_crb, dut.all_ram);
        prelaunch_init0 = dut.gime_init0;
        prelaunch_all_ram = dut.all_ram;
        @(negedge clock);
        cpu_halt <= 1'b1;
        cartridge_enabled <= 1'b1;
        cartridge_launch <= 1'b1;
        repeat (2) @(posedge clock);
        @(negedge clock);
        cartridge_launch <= 1'b0;
        // Firmware keeps the F12 OSD active while it reports the load and
        // waits for Enter to be released.  Reproduce the production order:
        // the current design's delayed CART event occurs while HALT is still
        // asserted, and only afterward does the menu release the CPU.  CART
        // must now remain pending until that release.
        repeat (2000) @(posedge clock);
        @(negedge clock);
        if (dut.cartridge_start_sent || dut.cartridge_irq_latch)
            $fatal(1, "CART event was consumed while the CPU was halted");
        if (dut.gime_init0 !== prelaunch_init0)
            $fatal(1, "Cartridge mapping changed GIME INIT0 before CART");
        if (dut.all_ram !== prelaunch_all_ram)
            $fatal(1, "Cartridge mapping changed SAM all-RAM before CART");
        cpu_halt <= 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (dut.cpu_firq) begin
                saw_firq = 1'b1;
            end
            if (dut.cartridge_event)
                cart_event_seen = 1'b1;
            if (cart_event_seen && cpu_registers[111:96] >= 16'hc000 &&
                cpu_registers[111:96] <= 16'hdfff)
                cartridge_pc_samples = cartridge_pc_samples + 1;
            if (dut.cartridge_irq_latch || dut.cartridge_event)
                saw_cart_signal = 1'b1;
            if (cart_event_seen && cpu_registers[111:96] != previous_trace_pc &&
                launch_opcode_count < 10000) begin
                $fdisplay(trace_file,
                          "%0d PC pc=%04h addr=%04h data=%02h read=%0d s=%04h y=%04h cc=%02h",
                          cycles, cpu_registers[111:96], address, dut.read_data,
                          read_cycle,
                          cpu_registers[63:48], cpu_registers[47:32],
                          cpu_registers[87:80]);
                previous_trace_pc = cpu_registers[111:96];
                launch_opcode_count = launch_opcode_count + 1;
            end
            if (dut.active) begin
                history_address[history_index] = address;
                history_pc[history_index] = cpu_registers[111:96];
                history_stack[history_index] = cpu_registers[63:48];
                history_data[history_index] = read_cycle ? dut.read_data : write_data;
                history_read[history_index] = read_cycle;
                history_opfetch[history_index] = opfetch;
                history_index = (history_index + 1) & 255;
                if (history_count < 256)
                    history_count = history_count + 1;

                if ($test$plusargs("LONG_TRACE") && opfetch && read_cycle &&
                    address >= 16'hf300 && address < 16'hf400) begin
                    $fdisplay(trace_file,
                              "FAULT-HISTORY current addr=%04h pc=%04h s=%04h data=%02h",
                              address, cpu_registers[111:96], cpu_registers[63:48],
                              dut.read_data);
                    for (history_dump_index = 0;
                         history_dump_index < history_count;
                         history_dump_index = history_dump_index + 1) begin
                        history_slot = (history_index - history_count +
                                        history_dump_index) & 255;
                        $fdisplay(trace_file,
                                  "H %0d a=%04h pc=%04h s=%04h d=%02h r=%0d op=%0d",
                                  history_dump_index,
                                  history_address[history_slot],
                                  history_pc[history_slot],
                                  history_stack[history_slot],
                                  history_data[history_slot],
                                  history_read[history_slot],
                                  history_opfetch[history_slot]);
                    end
                    $fclose(trace_file);
                    $display("LONG TRACE: reached $F300; history written");
                    $finish;
                end
                if (music_check_mode && io_write && address == 16'hff03 &&
                    write_data == 8'h35)
                    music_irq_enabled = 1'b1;
                if (music_check_mode && music_irq_enabled && io_write &&
                    address == 16'hff20) begin
                    if (write_data != music_previous_dac)
                        music_dac_changes = music_dac_changes + 1;
                    music_previous_dac = write_data;
                end
                if (music_check_mode && music_irq_enabled && io_write &&
                    address == 16'hff02)
                    music_keyboard_scans = music_keyboard_scans + 1;
            end
            if (cycles == max_cycles) begin
                $fdisplay(trace_file,
                          "SUMMARY firq=%0d entry=%0d cart_reads=%0d io_events=%0d final=%04h",
                          saw_firq, saw_cart_entry, cart_reads, io_events, address);
                $fclose(trace_file);
                if (!saw_cart_signal)
                    $fatal(1, "Diagnostic cartridge did not receive its CART event");
                if (!saw_cart_entry)
                    $fatal(1, "Diagnostic cartridge did not enter $C000");
                if (cartridge_pc_samples < 100)
                    $fatal(1, "Only %0d cartridge PC samples; startup did not transfer to ROM-Pak code",
                           cartridge_pc_samples);
                if (music_check_mode && !music_irq_enabled)
                    $fatal(1, "Music did not enable its 60 Hz PIA interrupt");
                if (music_check_mode && music_dac_changes < 100)
                    $fatal(1, "Music DAC remained idle (%0d changes)",
                           music_dac_changes);
                if (music_check_mode && music_keyboard_scans < 100)
                    $fatal(1, "Music did not enter its keyboard scan loop (%0d writes)",
                           music_keyboard_scans);
                $display("PASS: trace written; CART=%0d FIRQ=%0d C000=%0d cart reads=%0d",
                         saw_cart_signal, saw_firq, saw_cart_entry, cart_reads);
                if (music_check_mode)
                    $display("PASS: Music normal-speed startup; DAC changes=%0d keyboard scans=%0d",
                             music_dac_changes, music_keyboard_scans);
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
            if (dut.cartridge_mapped && read_cycle &&
                address >= 16'hc000 && address <= 16'hdfff) begin
                cart_reads = cart_reads + 1;
                if (address == 16'hc000) begin
                    saw_cart_entry = 1'b1;
                end
                if (cart_reads <= 512)
                    $fdisplay(trace_file, "%0d CART  %04h data=%02h",
                              cycles, address, dut.read_data);
            end
        end
    end
endmodule

`default_nettype wire
