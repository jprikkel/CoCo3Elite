`timescale 1ns/1ps
`default_nettype none

module coco3_sdram_ram_tb;
    reg memory_clock = 1'b0;
    reg video_clock = 1'b0;
    reg reset = 1'b1;
    reg [16:0] cpu_address = 0;
    reg [7:0] cpu_write_data = 0;
    reg cpu_read_enable = 1'b0;
    reg cpu_write_enable = 1'b0;
    reg [19:0] video_address = 0;
    reg video_blank = 1'b0;
    reg video_churn = 1'b0;
    wire [7:0] cpu_read_data;
    wire [15:0] video_read_data;
    wire ready;
    wire [31:0] debug_status;
    wire sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n;
    wire sdram_cas_n, sdram_we_n;
    wire [1:0] sdram_dqm;
    wire [12:0] sdram_address;
    wire [1:0] sdram_bank;
    wire [15:0] sdram_data;

    reg [19:0] refresh_video_address = 0;
    integer refresh_video_divider = 0;
    integer refresh_line_clock = 0;
    reg refresh_video_blank = 1'b0;
    integer aligned_refresh_commands = 0;
    wire refresh_video_ready;
    wire [31:0] refresh_video_debug_status;
    wire refresh_sdram_clk, refresh_sdram_cke, refresh_sdram_cs_n;
    wire refresh_sdram_ras_n, refresh_sdram_cas_n, refresh_sdram_we_n;
    wire [1:0] refresh_sdram_dqm;
    wire [12:0] refresh_sdram_address;
    wire [1:0] refresh_sdram_bank;
    wire [15:0] refresh_sdram_data;

    integer video_divider = 0;
    integer issued_writes = 0;
    integer refresh_commands = 0;
    integer expected_index;
    reg [16:0] expected_address [0:11];
    reg [7:0] expected_data [0:11];

    always #4 memory_clock = ~memory_clock;
    always #20 video_clock = ~video_clock;

    coco3_sdram_ram #(
        .POWERUP_CLOCKS(4),
        .CLEAR_WORDS(1),
        .REFRESH_CLOCKS(20),
        .WRITE_FIFO_LOG2(4)
    ) dut (
        .memory_clock(memory_clock), .video_clock(video_clock), .reset(reset),
        .cpu_address(cpu_address), .cpu_write_data(cpu_write_data),
        .cpu_read_enable(cpu_read_enable),
        .cpu_write_enable(cpu_write_enable),
        .cpu_read_data(cpu_read_data),
        .video_address(video_address), .video_blank(video_blank),
        .video_read_data(video_read_data),
        .ready(ready), .debug_status(debug_status),
        .sdram_clk(sdram_clk), .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n), .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n), .sdram_we_n(sdram_we_n),
        .sdram_dqm(sdram_dqm), .sdram_address(sdram_address),
        .sdram_bank(sdram_bank), .sdram_data(sdram_data)
    );

    // A second controller models NEW_SRAM's fastest real cadence: one video
    // word per ten 126 MHz clocks during active display, followed by a blank
    // interval in which accumulated refresh debt can be serviced safely.
    coco3_sdram_ram #(
        .POWERUP_CLOCKS(4),
        .CLEAR_WORDS(1),
        .REFRESH_CLOCKS(40),
        .WRITE_FIFO_LOG2(4)
    ) refresh_dut (
        .memory_clock(memory_clock), .video_clock(video_clock), .reset(reset),
        .cpu_address(17'd0), .cpu_write_data(8'd0),
        .cpu_read_enable(1'b0), .cpu_write_enable(1'b0),
        .cpu_read_data(),
        .video_address(refresh_video_address),
        .video_blank(refresh_video_blank), .video_read_data(),
        .ready(refresh_video_ready), .debug_status(refresh_video_debug_status),
        .sdram_clk(refresh_sdram_clk), .sdram_cke(refresh_sdram_cke),
        .sdram_cs_n(refresh_sdram_cs_n),
        .sdram_ras_n(refresh_sdram_ras_n),
        .sdram_cas_n(refresh_sdram_cas_n),
        .sdram_we_n(refresh_sdram_we_n),
        .sdram_dqm(refresh_sdram_dqm),
        .sdram_address(refresh_sdram_address),
        .sdram_bank(refresh_sdram_bank), .sdram_data(refresh_sdram_data)
    );

    always @(posedge memory_clock) begin
        if (refresh_video_ready) begin
            if (refresh_line_clock == 159) begin
                refresh_line_clock <= 0;
                refresh_video_blank <= 1'b0;
            end else begin
                refresh_line_clock <= refresh_line_clock + 1;
                if (refresh_line_clock == 99)
                    refresh_video_blank <= 1'b1;
            end
            if (!refresh_video_blank) begin
                if (refresh_video_divider == 9) begin
                    refresh_video_divider <= 0;
                    refresh_video_address <= refresh_video_address + 1'b1;
                end else begin
                    refresh_video_divider <= refresh_video_divider + 1;
                end
            end else begin
                refresh_video_divider <= 0;
            end
            if (!refresh_sdram_ras_n && !refresh_sdram_cas_n &&
                refresh_sdram_we_n)
                aligned_refresh_commands <= aligned_refresh_commands + 1;
        end

        if (video_churn) begin
            if (video_divider == 2) begin
                video_divider <= 0;
                video_address <= video_address + 1'b1;
            end else begin
                video_divider <= video_divider + 1;
            end
        end

        if (ready && !sdram_ras_n && !sdram_cas_n && sdram_we_n)
            refresh_commands <= refresh_commands + 1;

        if (ready && dut.state == 5'd10 && dut.request_write &&
            dut.request_owner == 2'd3) begin
            if (issued_writes >= 12)
                $fatal(1, "Unexpected extra CPU SDRAM write");
            if (dut.request_word[15:0] !==
                expected_address[issued_writes][16:1])
                $fatal(1, "Write %0d address %h expected %h",
                       issued_writes, dut.request_word[15:0],
                       expected_address[issued_writes][16:1]);
            if (dut.request_write_data !==
                {expected_data[issued_writes], expected_data[issued_writes]})
                $fatal(1, "Write %0d data %h expected %h",
                       issued_writes, dut.request_write_data,
                       {expected_data[issued_writes],
                        expected_data[issued_writes]});
            issued_writes <= issued_writes + 1;
        end
    end

    task pulse_cpu_write;
        input [16:0] address_value;
        input [7:0] data_value;
        begin
            @(negedge memory_clock);
            cpu_address = address_value;
            cpu_write_data = data_value;
            cpu_write_enable = 1'b1;
            repeat (5) @(negedge memory_clock);
            cpu_write_enable = 1'b0;
            repeat (5) @(negedge memory_clock);
        end
    endtask

    initial begin
        for (expected_index = 0; expected_index < 12;
             expected_index = expected_index + 1) begin
            expected_address[expected_index] =
                17'h0120 + expected_index;
            expected_data[expected_index] = 8'h80 + expected_index;
        end

        repeat (4) @(negedge memory_clock);
        reset = 1'b0;
        wait (ready);

        // Exercise a complete 6809-style write burst while video addresses
        // churn independently in the pixel domain. SDRAM must preserve every
        // write and the BRAM video shadow must receive the same bytes.
        video_churn = 1'b1;
        for (expected_index = 0; expected_index < 12;
             expected_index = expected_index + 1)
            pulse_cpu_write(17'h0120 + expected_index,
                            8'h80 + expected_index);

        repeat (80) @(negedge memory_clock);
        video_churn = 1'b0;
        repeat (500) @(negedge memory_clock);

        if (issued_writes != 12)
            $fatal(1, "Only %0d of 12 writes reached SDRAM", issued_writes);
        if (debug_status[31:24] != 0)
            $fatal(1, "Write FIFO dropped %0d writes", debug_status[31:24]);
        if (debug_status[23:16] < 2)
            $fatal(1, "Write FIFO was not exercised: high-water %0d",
                   debug_status[23:16]);
        if (refresh_commands < 4)
            $fatal(1, "Only %0d refresh commands were issued",
                   refresh_commands);
        if (aligned_refresh_commands < 4)
            $fatal(1, "Only %0d aligned refresh commands were issued",
                   aligned_refresh_commands);
        if (refresh_video_debug_status[15:8] != 0)
            $fatal(1, "Aligned refresh missed %0d video deadlines",
                   refresh_video_debug_status[15:8]);

        video_address = 20'h00090;
        @(posedge video_clock); #1;
        if (video_read_data !== 16'h8180)
            $fatal(1, "Video shadow word 0090 is %h expected 8180",
                   video_read_data);
        video_address = 20'h00095;
        @(posedge video_clock); #1;
        if (video_read_data !== 16'h8b8a)
            $fatal(1, "Video shadow word 0095 is %h expected 8b8a",
                   video_read_data);

        $display("PASS: SDRAM preserves queued writes and aligns refresh without video deadline misses");
        $display("PASS: BRAM video shadow remains coherent with CPU writes");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT state=%0d ready=%0d issued=%0d fifo=%0d video_pending=%0d lookahead=%0d issue=%0d capture=%0d target=%0d pipe=%b refresh_state=%0d refresh_ready=%0d refresh_miss=%0d",
                 dut.state, ready, issued_writes, dut.cpu_write_fifo_count,
                 dut.video_pending, dut.video_lookahead_pending,
                 dut.video_read_issue_count, dut.video_read_capture_count,
                 dut.video_read_target_count, dut.video_read_valid_pipeline,
                 refresh_dut.state, refresh_video_ready,
                 refresh_video_debug_status[15:8]);
        $fatal(1, "SDRAM controller test timeout");
    end
endmodule

`default_nettype wire
