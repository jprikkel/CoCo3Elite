`timescale 1ns/1ps
`default_nettype none
`include "coco3_banked_bin_loader_size.vh"

module coco3_banked_bin_loader_tb;
    reg clock = 0, reset = 1;
    reg cartridge_enabled = 0, cartridge_launch = 0;
    reg [14:0] cartridge_address = 0;
    reg [7:0] cartridge_write_data = 0;
    reg cartridge_write = 0;
    reg [7:0] loader [0:255];
    reg [7:0] stream [0:22];
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
        .bin_fifo_available(stream_index < 23),
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

    initial begin
        $readmemh("coco3_banked_bin_loader.mem", loader);
        loader_size = `COCO3_BANKED_BIN_LOADER_SIZE;
        // One discontinuous record maps its payload to physical $76080 and
        // its final descriptor maps execution back to logical $2080.
        stream[0]=8'h00; stream[1]=8'h00; stream[2]=8'h09;
        stream[3]=8'h04; stream[4]=8'h00;
        stream[5]=8'h76; stream[6]=8'h08;
        stream[7]=8'h86; stream[8]=8'ha5;
        stream[9]=8'hb7; stream[10]=8'hff; stream[11]=8'h70;
        stream[12]=8'h20; stream[13]=8'hfe;
        stream[14]=8'h00; stream[15]=8'h00; stream[16]=8'h04;
        stream[17]=8'h00; stream[18]=8'h00;
        stream[19]=8'h00; stream[20]=8'h00;
        stream[21]=8'h76; stream[22]=8'h08;
        for (n=0; n<loader_size; n=n+1) begin
            @(negedge clock);
            cartridge_address = n;
            cartridge_write_data = loader[n];
            cartridge_write = 1;
            @(posedge clock);
        end
        @(negedge clock); cartridge_write = 0;
        dut.rom_i.memory[15'h7ffe] = 8'hc0;
        dut.rom_i.memory[15'h7fff] = 8'h00;
        @(negedge clock);
        cartridge_enabled = 1;
        cartridge_launch = 1;
        reset = 0;
        repeat (2) @(posedge clock);
        @(negedge clock); cartridge_launch = 0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (bin_fifo_pop && stream_index < 23)
                stream_index <= stream_index + 1;
            if (bin_loader_done)
                cartridge_enabled <= 0;
            if (io_write && address == 16'hff70 && write_data == 8'ha5) begin
                if (!dut.all_ram || !dut.mmu_enable || dut.mmu[1] != 8'h3b)
                    $fatal(1, "Banked loader did not retain its all-RAM map");
                if (dut.ram_i.memory_low[16'hb040] != 8'h86 ||
                    dut.ram_i.memory_high[16'hb040] != 8'ha5)
                    $fatal(1, "Banked loader physical placement mismatch");
                $display("PASS: generic banked loader placed data and reached entry");
                $finish;
            end
            if (cycles == 1000000)
                $fatal(1, "Banked BIN loader timeout pc=%04h stream=%0d", pc, stream_index);
        end
    end
endmodule

`default_nettype wire
