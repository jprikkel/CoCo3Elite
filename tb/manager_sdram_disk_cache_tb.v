`timescale 1ns/1ps
`default_nettype none

module manager_sdram_disk_cache_tb;
    reg memory_clock = 1'b0;
    reg cache_clock = 1'b0;
    reg reset = 1'b1;
    reg cache_write = 1'b0;
    reg [17:0] cache_write_address = 0;
    reg [7:0] cache_write_data = 0;
    reg sector_request_toggle = 1'b0;
    reg [17:0] sector_base_address = 0;
    reg [7:0] sector_read_address = 0;
    wire [7:0] sector_read_data;
    wire sector_done_toggle, ready;
    wire [31:0] debug_status;
    wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n;
    wire sdram_cas_n, sdram_we_n;
    wire [1:0] sdram_dqm;
    wire [12:0] sdram_address;
    wire [1:0] sdram_bank;
    wire [15:0] sdram_data;

    always #4 memory_clock = ~memory_clock;
    always #20 cache_clock = ~cache_clock;

    manager_sdram_disk_cache #(
        .POWERUP_CLOCKS(4), .REFRESH_CLOCKS(200),
        .WRITE_FIFO_LOG2(4)
    ) dut (
        .memory_clock(memory_clock), .cache_clock(cache_clock), .reset(reset),
        .cache_write(cache_write),
        .cache_write_address(cache_write_address),
        .cache_write_data(cache_write_data),
        .sector_request_toggle(sector_request_toggle),
        .sector_base_address(sector_base_address),
        .sector_read_address(sector_read_address),
        .sector_read_data(sector_read_data),
        .sector_done_toggle(sector_done_toggle), .ready(ready),
        .debug_status(debug_status),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dqm(sdram_dqm), .sdram_address(sdram_address),
        .sdram_bank(sdram_bank), .sdram_data(sdram_data)
    );

    // Minimal BL1/CAS2 SDRAM model for the controller's used address range.
    reg [15:0] memory [0:131071];
    reg [12:0] active_row [0:3];
    reg [2:0] read_valid_pipeline = 0;
    reg [16:0] read_address_pipeline [0:2];
    reg [15:0] model_data = 0;
    reg model_drive = 1'b0;
    integer model_index;
    integer command_writes = 0;
    integer command_reads = 0;
    wire read_command = !sdram_cs_n && sdram_ras_n &&
                        !sdram_cas_n && sdram_we_n;
    wire write_command = !sdram_cs_n && sdram_ras_n &&
                         !sdram_cas_n && !sdram_we_n;
    wire activate_command = !sdram_cs_n && !sdram_ras_n &&
                            sdram_cas_n && sdram_we_n;
    wire [16:0] model_word_address =
        {active_row[sdram_bank][5:0], sdram_bank, sdram_address[8:0]};
    assign sdram_data = model_drive ? model_data : 16'hzzzz;

    always @(negedge memory_clock) begin
        model_drive <= 1'b0;
        read_valid_pipeline <= {read_valid_pipeline[1:0], read_command};
        read_address_pipeline[2] <= read_address_pipeline[1];
        read_address_pipeline[1] <= read_address_pipeline[0];
        if (activate_command)
            active_row[sdram_bank] <= sdram_address;
        if (read_command) begin
            read_address_pipeline[0] <= model_word_address;
            command_reads <= command_reads + 1;
        end
        // Data from a READ observed two half-cycles earlier is stable before
        // the following controller rising edge, where the DUT captures it.
        if (read_valid_pipeline[1]) begin
            model_data <= memory[read_address_pipeline[1]];
            model_drive <= 1'b1;
        end
        if (write_command) begin
            if (!sdram_dqm[0])
                memory[model_word_address][7:0] <= sdram_data[7:0];
            if (!sdram_dqm[1])
                memory[model_word_address][15:8] <= sdram_data[15:8];
            command_writes <= command_writes + 1;
        end
    end

    task write_byte;
        input [17:0] address_value;
        input [7:0] data_value;
        begin
            @(negedge cache_clock);
            cache_write_address = address_value;
            cache_write_data = data_value;
            cache_write = 1'b1;
            @(negedge cache_clock);
            cache_write = 1'b0;
        end
    endtask

    integer byte_index;
    reg [7:0] expected;
    initial begin
        for (model_index = 0; model_index < 131072;
             model_index = model_index + 1)
            memory[model_index] = 16'h0000;
        repeat (5) @(negedge memory_clock);
        reset = 1'b0;
        wait (ready);

        for (byte_index = 0; byte_index < 256; byte_index = byte_index + 1)
            write_byte(18'h01200 + byte_index,
                       (byte_index[7:0] ^ 8'hA5));

        wait (dut.write_fifo_count == 0 && dut.state == 5'd5);
        sector_base_address = 18'h01200;
        @(negedge cache_clock);
        sector_request_toggle = ~sector_request_toggle;
        wait (sector_done_toggle == sector_request_toggle);
        repeat (2) @(posedge cache_clock);

        for (byte_index = 0; byte_index < 256; byte_index = byte_index + 1) begin
            sector_read_address = byte_index[7:0];
            #1;
            expected = byte_index[7:0] ^ 8'hA5;
            if (sector_read_data !== expected)
                $fatal(1, "Sector byte %0d is %02h expected %02h",
                       byte_index, sector_read_data, expected);
        end
        if (command_writes != 256)
            $fatal(1, "Observed %0d SDRAM writes, expected 256",
                   command_writes);
        if (command_reads != 128)
            $fatal(1, "Observed %0d SDRAM reads, expected 128",
                   command_reads);
        if (debug_status[31:24] != 0)
            $fatal(1, "Write FIFO dropped %0d bytes",
                   debug_status[31:24]);

        $display("PASS: SDRAM disk cache preserves 256 byte writes");
        $display("PASS: requested sector is prefetched before completion");
        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "SDRAM disk-cache test timeout state=%0d fifo=%0d reads=%0d writes=%0d",
               dut.state, dut.write_fifo_count, command_reads, command_writes);
    end
endmodule

`default_nettype wire
