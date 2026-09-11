`timescale 1ns/1ps
module usb_host_spi_tb;
    reg clk = 0;
    always #10 clk = !clk;
    reg reset = 1, valid = 0, wr = 0;
    reg [7:0] addr = 0;
    reg [31:0] wdata = 0;
    reg [3:0] strb = 4'hf;
    wire [31:0] rdata;
    wire ack, irq, cs_n, sck, mosi, reset_n, vbus;
    reg miso = 1, int_n = 1, oc_n = 1;
    usb_host_spi dut (
        .clk(clk), .reset(reset), .bus_valid(valid), .bus_write(wr),
        .bus_addr(addr), .bus_wdata(wdata), .bus_wstrb(strb),
        .bus_rdata(rdata), .bus_ack(ack), .irq(irq), .usb_cs_n(cs_n),
        .usb_sck(sck), .usb_mosi(mosi), .usb_miso(miso),
        .usb_int_n(int_n), .usb_reset_n(reset_n), .usb_vbus_en(vbus),
        .usb_overcurrent_n(oc_n)
    );
    task check;
        input condition;
        input [511:0] message;
        begin
            if (condition !== 1'b1) $fatal(1, "FAIL: %0s", message);
        end
    endtask
    task access;
        input writing;
        input [7:0] offset;
        input [31:0] value;
        output [31:0] result;
        integer guard;
        begin
            @(negedge clk);
            valid = 1; wr = writing; addr = offset; wdata = value;
            guard = 0;
            @(posedge clk); #1;
            while (!ack && guard < 10) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            check(ack, "bus timeout");
            result = rdata;
            @(negedge clk); valid = 0;
            @(posedge clk); #1;
            check(!ack, "ack must be one cycle");
        end
    endtask
    reg [31:0] tmp, status, before_us, after_us;
    task write_reg;
        input [7:0] offset;
        input [31:0] value;
        begin access(1, offset, value, tmp); end
    endtask
    task wait_byte;
        integer guard;
        begin
            status = 1; guard = 0;
            while (status[0] && guard < 1000) begin
                access(0, 8'h04, 0, status); guard = guard + 1;
            end
            check(!status[0] && status[1], "byte completion");
        end
    endtask

    // Independent SPI mode-0 slave: shift output on falling edges and capture
    // input on rising edges. Model command response + payload under one CS.
    reg [7:0] responses [0:255];
    reg [7:0] received [0:255];
    reg [7:0] captured;
    integer nbits = 0, nbytes = 0, rising_edges = 0, cs_edges = 0;
    always @(negedge cs_n) begin
        nbits = 0; nbytes = 0; captured = 0;
        miso = responses[0][7];
        cs_edges = cs_edges + 1;
    end
    always @(posedge sck) if (!cs_n) begin
        rising_edges = rising_edges + 1;
        captured = {captured[6:0], mosi};
        nbits = nbits + 1;
        if (nbits == 8) begin
            received[nbytes] = captured;
            nbytes = nbytes + 1;
            nbits = 0;
        end
    end
    always @(negedge sck) if (!cs_n)
        miso = responses[nbytes][7-nbits];

    integer i, old_edges, old_cs;
    initial begin
        for (i = 0; i < 256; i = i + 1) responses[i] = i ^ 8'ha5;
        responses[0] = 8'h80; responses[1] = 8'h13;
        repeat (5) @(posedge clk);
        #1; check(cs_n && !sck && !vbus && !reset_n, "safe reset outputs");
        @(negedge clk); reset = 0;
        repeat (5) @(posedge clk);
        access(0, 0, 0, tmp); check(tmp == 32'h55425331, "ABI ID");
        // Held valid must not create repeated acks or restart operations.
        @(negedge clk); valid = 1; wr = 0; addr = 0;
        @(posedge clk); #1; check(ack, "first held request ack");
        repeat (5) begin @(posedge clk); #1; check(!ack, "duplicate ack"); end
        @(negedge clk); valid = 0;
        @(posedge clk);

        write_reg(8'h10, 8'h90);
        access(0, 4, 0, status); check(status[2] && !status[0], "reject unselected TX");
        write_reg(4, 4);
        write_reg(8'h0c, 0);
        access(0, 8'h0c, 0, tmp); check(tmp == 25, "invalid divider unchanged");
        access(0, 4, 0, status); check(status[2], "invalid divider flagged");
        write_reg(4, 4);
        write_reg(8'h0c, 4);
        write_reg(8, 3); // release reset and select, power stays off
        old_cs = cs_edges; old_edges = rising_edges;
        write_reg(8'h10, 8'h90);
        write_reg(8'h10, 8'hff); // rejected while busy
        write_reg(8, 2); // cannot truncate transaction accidentally
        write_reg(8'h0c, 100); // divider locked during byte
        wait_byte;
        check(status[2], "busy collision flagged");
        access(0, 8'h10, 0, tmp); check(tmp == 8'h80, "command full duplex RX");
        check(received[0] == 8'h90 && nbytes == 1, "SPI command captured MSB first");
        check(!cs_n && cs_edges == old_cs, "CS retained after command");
        access(0, 8'h0c, 0, tmp); check(tmp == 4, "busy divider unchanged");
        write_reg(4, 6);
        write_reg(8'h10, 0);
        wait_byte;
        access(0, 8'h10, 0, tmp); check(tmp == 8'h13, "revision response");
        check(received[1] == 0 && nbytes == 2, "payload under same CS");
        check(rising_edges - old_edges == 16, "exactly eight SPI clocks per byte");
        check(!sck && !status[2], "idle mode zero, error cleared");
        write_reg(8, 2);

        // FIFO-sized full-duplex burst, retaining CS for all 64 bytes.
        write_reg(8, 3);
        old_cs = cs_edges;
        for (i = 0; i < 64; i = i + 1) begin
            write_reg(8'h10, i ^ 8'h5a);
            wait_byte;
            access(0, 8'h10, 0, tmp);
            check(tmp == responses[i], "64-byte RX burst");
            check(received[i] == (i ^ 8'h5a), "64-byte TX burst");
            check(!cs_n && cs_edges == old_cs, "CS retained throughout burst");
        end
        write_reg(8, 2);

        // Alternate data patterns and divider values (including default rate).
        for (i = 4; i <= 25; i = i + 7) begin
            write_reg(8'h0c, i);
            write_reg(8, 3);
            write_reg(8'h10, 8'ha5);
            wait_byte;
            check(received[0] == 8'ha5, "alternate TX pattern");
            access(0, 8'h10, 0, tmp); check(tmp == 8'h80, "RX across dividers");
            write_reg(8, 2);
        end

        strb = 1; write_reg(8, 0); strb = 15;
        check(reset_n, "partial write has no side effect");
        access(0, 8'h11, 0, tmp);
        access(0, 4, 0, status); check(status[2], "misaligned access flagged");
        write_reg(4, 6);

        write_reg(8, 6); // enable level interrupt
        @(negedge clk); int_n = 0;
        repeat (4) @(posedge clk);
        #1; check(irq, "synchronized interrupt");
        write_reg(4, 8); check(irq, "IRQ is a level, not W1C");
        @(negedge clk); int_n = 1;
        repeat (4) @(posedge clk);
        #1; check(!irq, "interrupt released");
        write_reg(8, 14); check(vbus, "explicit power enable");
        @(negedge clk); oc_n = 0;
        repeat (5) @(posedge clk);
        #1; check(!vbus && irq, "overcurrent cutoff and interrupt");
        write_reg(4, 16);
        access(0, 4, 0, status); check(status[4] && status[5], "live fault cannot clear");
        write_reg(8, 14); check(!vbus, "cannot repower under fault");
        @(negedge clk); oc_n = 1;
        repeat (5) @(posedge clk);
        write_reg(8, 14); check(!vbus, "fault remains latched after recovery");
        write_reg(4, 20);
        write_reg(8, 14); check(vbus, "explicit clear and reenable");

        write_reg(8, 15);
        write_reg(8'h10, 8'h55);
        repeat (30) @(posedge clk);
        write_reg(8, 32'h80000000);
        check(cs_n && !sck && !vbus && !reset_n, "mid-byte abort safe");
        access(0, 4, 0, status); check(!status[0] && !status[1], "abort clears busy and done");

        access(0, 8'h14, 0, before_us);
        repeat (500) @(posedge clk);
        access(0, 8'h14, 0, after_us);
        check(after_us - before_us >= 10 && after_us - before_us <= 11, "microsecond timer");
        write_reg(8, 3); write_reg(8'h10, 8'hff);
        repeat (30) @(posedge clk);
        @(negedge clk); reset = 1;
        repeat (3) @(posedge clk);
        #1; check(cs_n && !sck && !vbus && !reset_n, "reset during transfer");
        $display("PASS: usb_host_spi_tb");
        $finish;
    end
    initial begin #1000000; $fatal(1, "FAIL: test timeout"); end
endmodule
