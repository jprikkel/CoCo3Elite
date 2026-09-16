`timescale 1ns/1ps
`default_nettype none

// GIME timer conformance tests derived from Sock Master's register notes:
// https://www.6809.org.uk/twilight/sock/gime.html
//
// The project targets the 1987 GIME timing rule (programmed value + 1).
// FF95 stores the low byte without restarting; FF94 stores the high nibble
// and restarts.  A programmed value of zero stops the timer.
module gime_reference_timer_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg hsync = 1'b1;
    reg fast_select = 1'b1;
    reg write_msb = 1'b0;
    reg write_lsb = 1'b0;
    reg [7:0] write_data = 8'h00;
    wire [3:0] timer_msb;
    wire [7:0] timer_lsb;
    wire blink;
    wire expire_pulse;
    integer failures = 0;
    reg initial_blink;
    reg [12:0] count_before_low_write;

    always #5 clock = ~clock;

    coco3_gime_timer #(.FAST_DIVIDE(2)) dut (
        .clock(clock), .reset(reset), .hsync(hsync),
        .fast_select(fast_select), .write_msb(write_msb),
        .write_lsb(write_lsb), .write_data(write_data),
        .timer_msb(timer_msb), .timer_lsb(timer_lsb),
        .blink(blink), .expire_pulse(expire_pulse)
    );

    task apply_reset;
        begin
            reset = 1'b1;
            hsync = 1'b1;
            write_msb = 1'b0;
            write_lsb = 1'b0;
            repeat (3) @(posedge clock);
            #1 reset = 1'b0;
        end
    endtask

    task write_low;
        input [7:0] value;
        begin
            @(negedge clock);
            write_data = value;
            write_lsb = 1'b1;
            @(posedge clock);
            #1 write_lsb = 1'b0;
        end
    endtask

    task write_high;
        input [3:0] value;
        begin
            @(negedge clock);
            write_data = {4'h0, value};
            write_msb = 1'b1;
            @(posedge clock);
            #1 write_msb = 1'b0;
        end
    endtask

    task program_timer;
        input [11:0] value;
        begin
            write_low(value[7:0]);
            write_high(value[11:8]);
            if ({timer_msb, timer_lsb} !== value) begin
                $display("FAIL timer readback expected=%03h got=%03h",
                         value, {timer_msb, timer_lsb});
                failures = failures + 1;
            end
        end
    endtask

    // Advance exactly one internally selected fast timer tick.
    task fast_tick;
        begin
            while (!dut.fast_tick)
                @(negedge clock);
            @(posedge clock);
            #1;
        end
    endtask

    // Present one falling HSYNC edge. A rising edge is deliberately separate
    // so the test can inspect the one-clock expire pulse.
    task slow_falling_edge;
        begin
            if (!hsync) begin
                @(negedge clock); hsync = 1'b1;
                @(posedge clock); #1;
            end
            @(negedge clock); hsync = 1'b0;
            @(posedge clock); #1;
        end
    endtask

    task slow_rising_edge;
        begin
            @(negedge clock); hsync = 1'b1;
            @(posedge clock); #1;
        end
    endtask

    initial begin
        apply_reset();

        // 1987 GIME: value 1 expires after two selected ticks, not one.
        fast_select = 1'b1;
        initial_blink = blink;
        program_timer(12'h001);
        fast_tick();
        if (expire_pulse) begin
            $display("FAIL value 1 expired before its second tick");
            failures = failures + 1;
        end
        fast_tick();
        if (!expire_pulse || blink === initial_blink) begin
            $display("FAIL value 1 did not expire/toggle blink on tick 2");
            failures = failures + 1;
        end
        fast_tick();
        if (expire_pulse) begin
            $display("FAIL expiry pulse lasted or repeated on the reload tick");
            failures = failures + 1;
        end
        fast_tick();
        if (!expire_pulse) begin
            $display("FAIL periodic reload did not preserve value+1 timing");
            failures = failures + 1;
        end

        // FF95 updates the latch but must not restart the active countdown.
        apply_reset();
        program_timer(12'h002);
        fast_tick();
        count_before_low_write = dut.timer_count;
        while (dut.fast_tick)
            @(negedge clock);
        write_low(8'h09);
        if (dut.timer_count !== count_before_low_write) begin
            $display("FAIL FF95 write restarted or advanced the timer");
            failures = failures + 1;
        end
        fast_tick();
        if (expire_pulse) begin
            $display("FAIL FF95 write shortened the in-progress countdown");
            failures = failures + 1;
        end
        fast_tick();
        if (!expire_pulse) begin
            $display("FAIL FF95 write restarted the in-progress countdown");
            failures = failures + 1;
        end

        // Slow mode advances only on falling HSYNC edges.
        apply_reset();
        fast_select = 1'b0;
        program_timer(12'h001);
        repeat (6) @(posedge clock);
        if (expire_pulse) begin
            $display("FAIL slow timer advanced without falling HSYNC");
            failures = failures + 1;
        end
        slow_falling_edge();
        if (expire_pulse) begin
            $display("FAIL slow value 1 expired on first HSYNC edge");
            failures = failures + 1;
        end
        slow_rising_edge();
        slow_falling_edge();
        if (!expire_pulse) begin
            $display("FAIL slow timer did not expire on second falling HSYNC");
            failures = failures + 1;
        end

        // The documented zero value disables the timer completely.
        apply_reset();
        fast_select = 1'b1;
        initial_blink = blink;
        program_timer(12'h000);
        if (dut.timer_enable !== 1'b0) begin
            $display("FAIL programmed zero did not stop the timer");
            failures = failures + 1;
        end
        repeat (12) fast_tick();
        if (expire_pulse || blink !== initial_blink) begin
            $display("FAIL stopped timer expired or changed blink");
            failures = failures + 1;
        end

        if (failures != 0)
            $fatal(1, "GIME timer reference mismatches=%0d", failures);
        $display("PASS: GIME timer write, reload, source, and stop behavior");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clock);
        $fatal(1, "GIME timer reference test timeout");
    end
endmodule

`default_nettype wire
