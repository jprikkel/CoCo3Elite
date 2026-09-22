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
    wire [15:0] video_read_data;
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
        .cpu_wait(cpu_wait), .video_address(video_address),
        .video_blank(video_blank), .video_read_data(video_read_data),
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
        // concurrent upper-RAM traffic. The final 720 KiB sector probes the
        // 20-bit disk address path that a 161 KiB cache would miss.
        for (model_index = 0; model_index < 256; model_index = model_index + 1)
            disk_write_byte(20'd737024 + model_index,
                            model_index[7:0] ^ 8'h5a);
        wait (disk_cache_write_idle);
        disk_sector_base_address = 20'd737024;
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
                   disk_sector_read_data, memory[24'd368639], command_writes,
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
                $fatal(1, "Directory sector byte %0d=%02h expected %02h",
                       sector_byte, disk_sector_read_data,
                       sector_byte[7:0] ^ 8'h93);
        end
        cpu_read(19'h01235, 8'ha5);

        $display("PASS: reset-map 128 KiB remains in BRAM");
        $display("PASS: upper 384 KiB CPU accesses wait for SDRAM");
        $display("PASS: upper video uses a 256-word burst-prefetch buffer");
        $display("PASS: upper framebuffer writes update the active line cache");
        $display("PASS: shared SDRAM disk cache reaches the 720 KiB boundary");
        $display("PASS: every directory sector byte survives SDRAM prefetch");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Hybrid RAM timeout state=%0d cpu_pending=%0d video_pending=%0d",
               dut.state, dut.memory_cpu_pending, dut.memory_video_pending);
    end
endmodule

`default_nettype wire
