`timescale 1ns/1ps
`default_nettype none

module manager_disk_geometry_tb;
    reg clock = 0;
    reg reset = 1;
    reg [7:0] track = 0, sector = 1, byte_address = 0;
    reg side = 0;
    wire [7:0] fdc_data;
    always #20 clock = ~clock;

    manager_sd_mmio #(.DISK_CACHE_BYTES(737280)) dut (
        .clock(clock), .memory_clock(clock), .reset(reset),
        .uart_rx(1'b1), .sd_miso(1'b1),
        .fdc_drive(2'd0), .fdc_side(side),
        .fdc_track(track), .fdc_sector(sector),
        .fdc_last_type1(8'b0), .fdc_debug_word(32'b0),
        .fdc_completed_debug_word(32'b0),
        .fdc_read_complete_toggle(1'b0),
        .fdc_write_complete_toggle(1'b0),
        .fdc_request_toggle(1'b0),
        .fdc_buffer_address(byte_address), .fdc_buffer_data(fdc_data),
        .fdc_write_strobe(1'b0), .fdc_write_data(8'b0),
        .menu_key_state(10'b0), .osd_char_address(11'b0),
        .osd_preview_read_address(12'b0),
        .debug_cpu_pc(16'b0), .debug_gime_init0(8'b0),
        .debug_gime_init1(8'b0), .debug_video_mode(8'b0),
        .debug_video_resolution(8'b0),
        .video_capture_read_data(8'b0),
        .video_capture_done_toggle(1'b0), .video_capture_busy(1'b0),
        .bin_fifo_pop(1'b0), .bin_loader_done(1'b0),
        .bin_cancel(1'b0),
        .shared_disk_write_ready(1'b1),
        .shared_disk_write_idle(1'b1),
        .shared_disk_sector_read_data(8'hc7),
        .shared_disk_sector_done_toggle(1'b0),
        .shared_disk_ready(1'b1)
    );

    task check_last_sector;
        input [19:0] image_size;
        input [7:0] last_track;
        input last_side;
        begin
            @(negedge clock);
            dut.disk_cache_image_bytes = image_size;
            dut.disk_cache_ready = 1;
            track = last_track;
            side = last_side;
            sector = 18;
            byte_address = 255;
            #1;
            if (!dut.disk_cache_fdc_valid ||
                dut.disk_cache_fdc_address !== image_size - 1'b1 ||
                fdc_data !== 8'hc7)
                $fatal(1, "Geometry %0d track %0d side %0d address %0d",
                       image_size, last_track, last_side,
                       dut.disk_cache_fdc_address);
            track = last_track + 1'b1;
            #1;
            if (dut.disk_cache_fdc_valid)
                $fatal(1, "Accepted track after end of %0d-byte image",
                       image_size);
        end
    endtask

    initial begin
        repeat (3) @(negedge clock);
        reset = 0;
        check_last_sector(20'd161280, 8'd34, 1'b0);
        side = 1'b1;
        track = 8'd0;
        #1;
        if (dut.disk_cache_fdc_valid)
            $fatal(1, "Accepted side 1 of a single-sided 161280-byte image");
        check_last_sector(20'd368640, 8'd39, 1'b1);
        check_last_sector(20'd737280, 8'd79, 1'b1);
        $display("PASS: 35-track, 40-track double-sided, and 80-track double-sided image geometry");
        $finish;
    end
endmodule

`default_nettype wire
