`timescale 1ns/1ps
`default_nettype none

module coco3_hybrid_512k_ram_tb;
    reg memory_clock = 0;
    reg video_clock = 0;
    reg reset = 1;
    reg [18:0] cpu_address = 0;
    reg [7:0] cpu_write_data = 0;
    reg cpu_read_enable = 0;
    reg cpu_write_enable = 0;
    wire [7:0] cpu_read_data;
    wire cpu_wait;
    reg [19:0] video_address = 20'h30000;
    reg video_blank = 1;
    reg gime_drive = 0;
    reg gime_reset_n = 0;
    wire [19:0] gime_address;
    wire gime_hblank, gime_vblank, gime_vsync;
    wire [19:0] active_video_address = gime_drive ? gime_address : video_address;
    wire active_video_blank = gime_drive ? (gime_hblank || gime_vblank) : video_blank;
    wire [15:0] video_read_data;
    wire video_cache_miss;
    wire ready;
    wire [31:0] debug_status;
    reg disk_cache_write = 0;
    reg [19:0] disk_cache_write_address = 0;
    reg [7:0] disk_cache_write_data = 0;
    wire disk_cache_write_ready, disk_cache_write_idle;
    reg disk_sector_request_toggle = 0;
    reg [19:0] disk_sector_base_address = 0;
    reg [7:0] disk_sector_read_address = 0;
    wire [7:0] disk_sector_read_data;
    wire disk_sector_done_toggle;
    wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n;
    wire sdram_cas_n, sdram_we_n;
    wire [1:0] sdram_dqm;
    wire [12:0] sdram_address;
    wire [1:0] sdram_bank;
    wire [15:0] sdram_data;

    always #6.667 memory_clock = ~memory_clock;
    always #20 video_clock = ~video_clock;

    coco3_hybrid_512k_ram #(
        .POWERUP_CLOCKS(4), .REFRESH_CLOCKS(500)
    ) dut (
        .memory_clock(memory_clock), .video_clock(video_clock), .reset(reset),
        .cpu_address(cpu_address), .cpu_write_data(cpu_write_data),
        .cpu_read_enable(cpu_read_enable),
        .cpu_write_enable(cpu_write_enable), .cpu_read_data(cpu_read_data),
        .cpu_wait(cpu_wait), .video_address(active_video_address),
        .video_blank(active_video_blank), .video_read_data(video_read_data),
        .video_frame_sync(gime_drive && !gime_vsync),
        .video_frame_start_address(20'h28000),
        .video_cache_miss(video_cache_miss),
        .ready(ready), .debug_status(debug_status),
        .disk_cache_write(disk_cache_write),
        .disk_cache_write_address(disk_cache_write_address),
        .disk_cache_write_data(disk_cache_write_data),
        .disk_cache_write_ready(disk_cache_write_ready),
        .disk_cache_write_idle(disk_cache_write_idle),
        .disk_sector_request_toggle(disk_sector_request_toggle),
        .disk_sector_base_address(disk_sector_base_address),
        .disk_sector_read_address(disk_sector_read_address),
        .disk_sector_read_data(disk_sector_read_data),
        .disk_sector_done_toggle(disk_sector_done_toggle),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dqm(sdram_dqm), .sdram_address(sdram_address),
        .sdram_bank(sdram_bank), .sdram_data(sdram_data)
    );

    COCO3VIDEO gime (
        .PIX_CLK(video_clock), .RESET_N(gime_reset_n), .COLOR(),
        .HSYNC(), .SYNC_FLAG(), .VSYNC(gime_vsync), .HBLANKING(gime_hblank),
        .VBLANKING(gime_vblank), .RAM_ADDRESS(gime_address),
        .RAM_DATA(video_read_data), .VIDEO_ACTIVE(),
        .COCO(1'b0), .V(3'b000), .BP(1'b1), .VERT(7'h00),
        .VID_CONT(4'h0), .CSS(1'b0), .LPF(2'b11),
        .VERT_FIN_SCRL(4'h0), .HLPR(1'b0), .LPR(3'b000),
        .HRES(4'h7), .CRES(2'b10), .HVEN(1'b0),
        .HOR_OFFSET(7'h00), .SCRN_START_HSB(2'b00),
        .SCRN_START_MSB(8'ha0), .SCRN_START_LSB(8'h00),
        .BLINK(1'b0), .SWITCH5(1'b0)
    );

    reg [15:0] memory [0:1048575];
    reg [12:0] active_row [0:3];
    reg [2:0] read_valid_pipeline = 0;
    reg [23:0] read_address_pipeline [0:2];
    reg [15:0] model_data = 0;
    reg model_drive = 0;
    integer model_index;
    integer command_reads = 0;
    integer command_writes = 0;
    wire read_command = !sdram_cs_n && sdram_ras_n &&
                        !sdram_cas_n && sdram_we_n;
    wire write_command = !sdram_cs_n && sdram_ras_n &&
                         !sdram_cas_n && !sdram_we_n;
    wire activate_command = !sdram_cs_n && !sdram_ras_n &&
                            sdram_cas_n && sdram_we_n;
    wire [23:0] model_word_address =
        {active_row[sdram_bank], sdram_bank, sdram_address[8:0]};
    assign sdram_data = model_drive ? model_data : 16'hzzzz;

    always @(negedge memory_clock) begin
        model_drive <= 0;
        read_valid_pipeline <= {read_valid_pipeline[1:0], read_command};
        read_address_pipeline[2] <= read_address_pipeline[1];
        read_address_pipeline[1] <= read_address_pipeline[0];
        if (activate_command)
            active_row[sdram_bank] <= sdram_address;
        if (read_command) begin
            read_address_pipeline[0] <= model_word_address;
            command_reads <= command_reads + 1;
        end
        if (read_valid_pipeline[1]) begin
            model_data <= memory[read_address_pipeline[1]];
            model_drive <= 1;
        end
        if (write_command) begin
            if (!sdram_dqm[0])
                memory[model_word_address][7:0] <= sdram_data[7:0];
            if (!sdram_dqm[1])
                memory[model_word_address][15:8] <= sdram_data[15:8];
            command_writes <= command_writes + 1;
        end
    end

    task cpu_write;
        input [18:0] address_value;
        input [7:0] data_value;
        begin
            @(negedge video_clock);
            cpu_address = address_value;
            cpu_write_data = data_value;
            cpu_write_enable = 1;
            @(negedge video_clock);
            cpu_write_enable = 0;
            wait (!cpu_wait);
        end
    endtask

    task disk_write_byte;
        input [19:0] address_value;
        input [7:0] data_value;
        begin
            @(negedge video_clock);
            while (!disk_cache_write_ready)
                @(negedge video_clock);
            disk_cache_write_address = address_value;
            disk_cache_write_data = data_value;
            disk_cache_write = 1;
            @(negedge video_clock);
            disk_cache_write = 0;
        end
    endtask

    task cpu_read;
        input [18:0] address_value;
        input [7:0] expected;
        begin
            @(negedge video_clock);
            cpu_address = address_value;
            cpu_read_enable = 1;
            #1;
            if (address_value[18:17] != 2'b11 && !cpu_wait)
                $fatal(1, "Upper-memory read did not assert CPU wait");
            wait (!cpu_wait);
            @(posedge video_clock);
            #1;
            if (cpu_read_data !== expected)
                $fatal(1, "CPU read %05h returned %02h expected %02h",
                       address_value, cpu_read_data, expected);
            @(negedge video_clock);
            cpu_read_enable = 0;
        end
    endtask

    integer reads_before;
    integer sector_byte;
    integer raster_line;
    integer raster_pixel;
    integer raster_line_misses;
    integer raster_total_misses;
    reg [19:0] raster_previous_address;
    integer gime_misses;
    integer gime_last_pixel;
    integer gime_last_line;
    integer gime_sample;
    integer gime_frame_misses;
    reg [9:0] previous_gime_line;
    reg [19:0] gime_previous_address;
    reg previous_video_request_toggle = 0;
    integer video_request_log_count = 0;
    always @(posedge video_clock) begin
        if (gime_drive && dut.video_request_toggle != previous_video_request_toggle) begin
            video_request_log_count = video_request_log_count + 1;
            if (video_request_log_count <= 10)
                $display("GIME FILL %0d line=%0d pixel=%0d blank=%b addr=%05h tag=%03h target=%b",
                         video_request_log_count, gime.LINE, gime.PIXEL_COUNT,
                         active_video_blank, gime_address, dut.video_fill_tag,
                         dut.video_fill_buffer);
        end
        previous_video_request_toggle = dut.video_request_toggle;
    end
    initial begin
        for (model_index = 0; model_index < 1048576;
             model_index = model_index + 1)
            memory[model_index] = 0;
        repeat (5) @(negedge memory_clock);
        reset = 0;
        wait (ready);

        // Hot $38 page remains entirely in BRAM.
        reads_before = command_reads;
        cpu_write(19'h70071, 8'h4a);
        cpu_read(19'h70071, 8'h4a);
        if (command_reads != reads_before)
            $fatal(1, "BRAM access generated an SDRAM read");

        // Distinct page $00 storage uses SDRAM and asserts a wait state.
        cpu_write(19'h01235, 8'ha5);
        cpu_read(19'h01235, 8'ha5);
        cpu_write(19'h01234, 8'h5a);
        cpu_read(19'h01234, 8'h5a);

        // Fill a complete aligned video buffer and verify first/last words.
        for (model_index = 0; model_index < 256; model_index = model_index + 1)
            memory[24'h080100 + model_index] =
                {model_index[7:0] ^ 8'hc3, model_index[7:0] ^ 8'h3c};
        video_address = 20'h00100;
        video_blank = 0;
        wait (dut.video_valid0 || dut.video_valid1);
        repeat (2) @(posedge video_clock);
        if (video_read_data !== 16'hc33c)
            $fatal(1, "First line-buffer word is %04h", video_read_data);
        // The restored arbitration schedule starts the adjacent block at
        // offset 192, leaving the earlier half-block request disabled.
        @(negedge video_clock);
        video_address = 20'h001c0;
        wait (dut.video_valid1 && dut.video_tag1 == 10'h002);
        if (video_cache_miss)
            $fatal(1, "Midpoint prefetch missed the current video word");
        @(negedge video_clock);
        video_address = 20'h001ff;
        repeat (2) @(posedge video_clock);
        if (video_read_data !== 16'h3cc3)
            $fatal(1, "Last line-buffer word is %04h", video_read_data);

        // A CPU write into a cached upper-memory scanline must update the
        // line buffer as well as SDRAM; otherwise animation leaves stale
        // pixels visible until an unrelated line replacement.
        @(negedge video_clock);
        video_address = 20'h00100;
        cpu_write(19'h00200, 8'ha6);
        repeat (2) @(posedge video_clock);
        if (video_read_data !== 16'hc3a6)
            $fatal(1, "Cached video write-through is %04h", video_read_data);
        if (command_reads < 258)
            $fatal(1, "Expected burst prefetch plus CPU reads, got %0d",
                   command_reads);
        if (debug_status[31:24] == 0)
            $fatal(1, "CPU SDRAM wait-state counter did not advance");

        // Disk bytes occupy a disjoint SDRAM address region and survive
        // concurrent upper-RAM traffic. The final 360 KiB sector probes the
        // wider disk address path that a 161 KiB cache would miss.
        for (model_index = 0; model_index < 256; model_index = model_index + 1)
            disk_write_byte(20'd368384 + model_index,
                            model_index[7:0] ^ 8'h5a);
        wait (disk_cache_write_idle);
        disk_sector_base_address = 20'd368384;
        disk_sector_request_toggle = ~disk_sector_request_toggle;
        wait (disk_sector_done_toggle == disk_sector_request_toggle);
        disk_sector_read_address = 8'd0;
        @(posedge video_clock);
        #1;
        if (disk_sector_read_data !== 8'h5a)
            $fatal(1, "Disk sector byte zero incorrect");
        disk_sector_read_address = 8'd255;
        @(posedge video_clock);
        #1;
        if (disk_sector_read_data !== 8'ha5)
            $fatal(1, "Disk byte255=%02h word=%04h writes=%0d fifo=%0d pending=%0d",
                   disk_sector_read_data, memory[24'd184319], command_writes,
                   dut.disk_fifo_count, dut.disk_source_pending);

        // Exercise the complete CoCo directory sector, including the eighth
        // character of a seven-letter filename.  The old boundary-only probe
        // could pass while a middle byte appeared as an extra DIR glyph.
        for (model_index = 0; model_index < 256; model_index = model_index + 1)
            disk_write_byte(20'd78848 + model_index,
                            model_index[7:0] ^ 8'h93);
        wait (disk_cache_write_idle);
        disk_sector_base_address = 20'd78848;
        disk_sector_request_toggle = ~disk_sector_request_toggle;
        wait (disk_sector_done_toggle == disk_sector_request_toggle);
        for (sector_byte = 0; sector_byte < 256; sector_byte = sector_byte + 1) begin
            @(negedge video_clock);
            disk_sector_read_address = sector_byte[7:0];
            @(posedge video_clock);
            #1;
            if (disk_sector_read_data !== (sector_byte[7:0] ^ 8'h93))
                $fatal(1, "Directory sector byte %0d=%02h expected %02h after read clock",
                        sector_byte, disk_sector_read_data,
                        sector_byte[7:0] ^ 8'h93);
        end
        cpu_read(19'h01235, 8'ha5);

        // Continuous 160-byte rows (the live Pac-Man HRES setting) reveal
        // whether regular row transitions alone can explain hardware misses.
        raster_total_misses = 0;
        raster_previous_address = 20'hfffff;
        video_blank = 1;
        video_address = 20'h28000;
        repeat (320) @(negedge video_clock);
        for (raster_line = 0; raster_line < 12; raster_line = raster_line + 1) begin
            raster_line_misses = 0;
            video_blank = 0;
            for (raster_pixel = 0; raster_pixel < 640; raster_pixel = raster_pixel + 1) begin
                @(negedge video_clock);
                video_address = 20'h28000 + raster_line * 80 + raster_pixel / 8;
                #1;
                if (video_address != raster_previous_address && video_cache_miss) begin
                    raster_line_misses = raster_line_misses + 1;
                    raster_total_misses = raster_total_misses + 1;
                end
                raster_previous_address = video_address;
            end
            video_blank = 1;
            repeat (160) @(negedge video_clock);
            $display("RASTER line=%0d misses=%0d", raster_line, raster_line_misses);
        end
        $display("RASTER total_misses=%0d", raster_total_misses);

        // Compare the real GIME fetch cadence/row transitions against the
        // hardware Q telemetry for the same FF98/FF99/FF9F settings.
        gime_drive = 1;
        gime_misses = 0;
        gime_frame_misses = 0;
        gime_last_pixel = 0;
        gime_last_line = 0;
        gime_previous_address = 20'hfffff;
        previous_gime_line = 0;
        repeat (5) @(negedge video_clock);
        gime_reset_n = 1;
        for (gime_sample = 0; gime_sample < 500000; gime_sample = gime_sample + 1) begin
            @(posedge video_clock);
            if (gime.LINE == 0 && previous_gime_line != 0) begin
                $display("GIME completed_frame_misses=%0d", gime_frame_misses);
                gime_frame_misses = 0;
            end
            if (!gime_hblank && !gime_vblank &&
                gime_address != gime_previous_address && video_cache_miss) begin
                gime_misses = gime_misses + 1;
                gime_frame_misses = gime_frame_misses + 1;
                gime_last_pixel = gime.PIXEL_COUNT;
                gime_last_line = gime.LINE;
                if (gime_misses <= 8)
                    $display("GIME MISS %0d line=%0d pixel=%0d prev=%05h addr=%05h tag0=%03h/%b tag1=%03h/%b pending=%b fill=%03h",
                             gime_misses, gime.LINE, gime.PIXEL_COUNT,
                             gime_previous_address, gime_address,
                             dut.video_tag0, dut.video_valid0,
                             dut.video_tag1, dut.video_valid1,
                             dut.video_fill_pending, dut.video_fill_tag);
            end
            gime_previous_address = gime_address;
            previous_gime_line = gime.LINE;
        end
        $display("GIME misses=%0d last_pixel=%0d last_line=%0d",
                 gime_misses, gime_last_pixel, gime_last_line);
        if (gime_misses >= 100)
            $fatal(1, "GIME blanking fetches displaced visible video: %0d misses",
                   gime_misses);
        if (gime_frame_misses != 0)
            $fatal(1, "Warm GIME frame still has %0d visible cache misses",
                   gime_frame_misses);
        $display("PASS: GIME blanking fetches do not thrash visible cache");

        $display("PASS: reset-map 128 KiB remains in BRAM");
        $display("PASS: upper 384 KiB CPU accesses wait for SDRAM");
        $display("PASS: upper video uses a 256-word burst-prefetch buffer");
        $display("PASS: upper framebuffer writes update the active line cache");
        $display("PASS: shared SDRAM disk cache reaches the 360 KiB boundary");
        $display("PASS: every directory sector byte survives SDRAM prefetch");
        $finish;
    end

    initial begin
        #25000000;
        $fatal(1, "Hybrid RAM timeout state=%0d cpu_pending=%0d video_pending=%0d",
               dut.state, dut.memory_cpu_pending, dut.memory_video_pending);
    end
endmodule

`default_nettype wire
