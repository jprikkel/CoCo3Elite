`timescale 1ns/1ps
`default_nettype none
`include "decb_bin_loader_size.vh"

module decb_bin_loader_tb;
    reg clock = 0, reset = 1;
    reg cartridge_enabled = 0, cartridge_launch = 0;
    reg [14:0] cartridge_address = 0;
    reg [7:0] cartridge_write_data = 0;
    reg cartridge_write = 0;
    reg [7:0] loader [0:255];
    reg [7:0] stream [0:39];
    integer loader_size, n, stream_index = 0, cycles = 0;
    wire [15:0] pc, address;
    wire io_write, bin_fifo_pop, bin_loader_done;
    wire [7:0] write_data;

    always #5 clock = ~clock;

    coco3_boot_machine #(.CARTRIDGE_START_DELAY(10)) dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b1), .cpu_halt(1'b0),
        .cartridge_enabled(cartridge_enabled), .cartridge_launch(cartridge_launch),
        .cartridge_address(cartridge_address),
        .cartridge_write_data(cartridge_write_data),
        .cartridge_write(cartridge_write), .cold_start_clear(1'b0),
        .bin_fifo_data(stream[stream_index]),
        .bin_fifo_available(stream_index < 40),
        .bin_transfer_active(1'b1), .bin_transfer_complete(1'b1),
        .bin_transfer_error(1'b0), .bin_fifo_pop(bin_fifo_pop),
        .bin_loader_done(bin_loader_done),
        .debug_address(address), .debug_pc(pc), .debug_vma(), .debug_read(),
        .debug_opfetch(), .debug_read_data(), .debug_ram_write(),
        .debug_io_write(io_write), .debug_write_data(write_data),
        .keyboard_keys(56'b0), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0),
        .joystick_left_x(6'd32), .joystick_left_y(6'd32),
        .joystick_left_fire(1'b0), .joystick_left_fire2(1'b0), .joystick_right_x(6'd32),
        .joystick_right_y(6'd32), .joystick_right_fire(1'b0), .joystick_right_fire2(1'b0),
        .sd_status(8'b0), .sd_detail(8'b0), .video_hsync(1'b1),
        .pia_hsync(1'b1), .video_vsync(1'b1), .video_address(20'b0),
        .video_read_data(), .audio_dac(), .video_vdg_control(), .video_css(),
        .video_palette(), .video_border_palette(), .video_mode(),
        .video_resolution(), .video_vbank(), .video_scroll(), .video_offset(),
        .video_horizontal_offset(), .video_blink(), .sd_drive_present(2'b0),
        .sd_fdc_done_toggle(1'b0), .sd_fdc_success(1'b0),
        .sd_fdc_write_done_toggle(1'b0), .sd_fdc_write_success(1'b0),
        .sd_fdc_data(8'b0), .sd_fdc_buffer_address(), .sd_fdc_drive(),
        .sd_fdc_track(), .sd_fdc_sector(), .sd_fdc_last_type1(),
        .sd_fdc_debug_word(), .sd_fdc_completed_debug_word(),
        .sd_fdc_read_complete_toggle(), .sd_fdc_write_strobe(),
        .sd_fdc_write_data(), .sd_fdc_write_complete_toggle(),
        .sd_fdc_request_toggle()
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
        $readmemh("decb_bin_loader.mem", loader);
        loader_size = `DECB_BIN_LOADER_SIZE;
        // The loaded program snapshots its complete entry context before
        // publishing the completion marker.  Disk BASIC's EXEC dispatcher
        // enters with A=00, B=44, X=ABAB, DP=00, Z set, and its existing S.
        stream[0]=8'h00; stream[1]=8'h00; stream[2]=8'h1e;
        stream[3]=8'h60; stream[4]=8'h00;
        stream[5]=8'hb7; stream[6]=8'h60; stream[7]=8'h50; // STA $6050
        stream[8]=8'hf7; stream[9]=8'h60; stream[10]=8'h51; // STB $6051
        stream[11]=8'hbf; stream[12]=8'h60; stream[13]=8'h52; // STX $6052
        stream[14]=8'h1f; stream[15]=8'hb8;       // TFR DP,A
        stream[16]=8'hb7; stream[17]=8'h60; stream[18]=8'h54;
        stream[19]=8'h1f; stream[20]=8'ha8;       // TFR CC,A
        stream[21]=8'hb7; stream[22]=8'h60; stream[23]=8'h55;
        stream[24]=8'h10; stream[25]=8'hff;       // STS $6056
        stream[26]=8'h60; stream[27]=8'h56;
        stream[28]=8'h86; stream[29]=8'ha5;       // LDA #$A5
        stream[30]=8'hb7; stream[31]=8'hff; stream[32]=8'h70; // STA $FF70
        stream[33]=8'h20; stream[34]=8'hfe;       // BRA *
        stream[35]=8'hff; stream[36]=8'h00; stream[37]=8'h00;
        stream[38]=8'h60; stream[39]=8'h00;
        // Fill the manager port while the CoCo remains in reset.
        for (n=0; n<loader_size; n=n+1) begin
            @(negedge clock);
            cartridge_address = n;
            cartridge_write_data = loader[n];
            cartridge_write = 1;
            @(posedge clock);
        end
        @(negedge clock); cartridge_write = 0;
        // Bypass only the already-covered CART/FIRQ entry protocol: point the
        // reset vector at the mapped loader. The remainder of this test uses
        // the real 6809, cartridge RAM, I/O decode, and 128K RAM datapath.
        dut.rom_i.memory[15'h7ffe] = 8'hc0;
        dut.rom_i.memory[15'h7fff] = 8'h00;
        @(negedge clock);
        cartridge_enabled = 1;
        cartridge_launch = 1;
        reset = 0;
        repeat (2) @(posedge clock);
        @(negedge clock);
        cartridge_launch = 0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (bin_fifo_pop && stream_index < 40) begin
                stream_index <= stream_index + 1;
            end
            if (bin_loader_done)
                cartridge_enabled <= 0;
            if (io_write && address == 16'hff70 && write_data == 8'ha5) begin
                if (!dut.all_ram)
                    $fatal(1, "DECB BIN loader did not retain Disk BASIC's all-RAM map");
                if ((dut.cpu_i.core.cc & 8'h50) != 0)
                    $fatal(1, "DECB BIN loader left IRQ/FIRQ masked: CC=%02h",
                           dut.cpu_i.core.cc);
                if (dut.cpu_i.core.s !=
                    {dut.ram_i.memory_low[16'hff43],
                     dut.ram_i.memory_high[16'hff43]})
                    $fatal(1, "DECB BIN loader did not restore entry stack");
                if (physical_byte(17'h16050) !== 8'h00 ||
                    physical_byte(17'h16051) !== 8'h44 ||
                    physical_byte(17'h16052) !== 8'hAB ||
                    physical_byte(17'h16053) !== 8'hAB ||
                    physical_byte(17'h16054) !== 8'h00)
                    $fatal(1, "DECB BIN EXEC registers A=%02h B=%02h X=%02h%02h DP=%02h",
                           physical_byte(17'h16050), physical_byte(17'h16051),
                           physical_byte(17'h16052), physical_byte(17'h16053),
                           physical_byte(17'h16054));
                if ((physical_byte(17'h16055) & 8'h54) !== 8'h04)
                    $fatal(1, "DECB BIN EXEC condition code mismatch CC=%02h",
                           physical_byte(17'h16055));
                if ({physical_byte(17'h16056), physical_byte(17'h16057)} !==
                    {physical_byte(17'h1FE86), physical_byte(17'h1FE87)})
                    $fatal(1, "DECB BIN EXEC stack mismatch got=%02h%02h saved=%02h%02h",
                           physical_byte(17'h16056), physical_byte(17'h16057),
                           physical_byte(17'h1FE86), physical_byte(17'h1FE87));
                $display("PASS: DECB BIN loader matches Disk BASIC EXEC registers, all-RAM map, stack, and interrupts");
                $finish;
            end
            if (cycles == 1000000) begin
                $fatal(1, "DECB BIN loader timeout pc=%04h stream=%0d done=%0d mapped=%0d sent=%0d latch=%0d firq=%0d len=%02h%02h target=%02h%02h",
                       pc, stream_index, bin_loader_done,
                       dut.cartridge_mapped, dut.cartridge_start_sent,
                       dut.cartridge_irq_latch, dut.cpu_firq,
                       dut.ram_i.memory_low[16'hff40],
                       dut.ram_i.memory_high[16'hff40],
                       dut.ram_i.memory_low[16'hff41],
                       dut.ram_i.memory_high[16'hff41]);
            end
        end
    end
endmodule

`default_nettype wire
