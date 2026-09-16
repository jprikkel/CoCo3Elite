`timescale 1ns/1ps
`default_nettype none

// FF92/FF93 conformance tests derived from:
// https://www.6809.org.uk/twilight/sock/gime.html
// Source bit order is timer, HBORD, VBORD, serial, keyboard, cartridge.
module gime_reference_interrupt_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg irq_master_enable = 1'b0;
    reg firq_master_enable = 1'b0;
    reg [5:0] irq_enable = 6'h00;
    reg [5:0] firq_enable = 6'h00;
    reg [5:0] event_pulse = 6'h00;
    reg irq_ack = 1'b0;
    reg firq_ack = 1'b0;
    reg legacy_irq = 1'b0;
    reg legacy_firq = 1'b0;
    wire [5:0] irq_status;
    wire [5:0] firq_status;
    wire cpu_irq;
    wire cpu_firq;
    integer source;
    integer failures = 0;

    always #5 clock = ~clock;

    coco3_gime_interrupt dut (
        .clock(clock), .reset(reset),
        .irq_master_enable(irq_master_enable),
        .firq_master_enable(firq_master_enable),
        .irq_enable(irq_enable), .firq_enable(firq_enable),
        .event_pulse(event_pulse), .irq_ack(irq_ack),
        .firq_ack(firq_ack), .legacy_irq(legacy_irq),
        .legacy_firq(legacy_firq), .irq_status(irq_status),
        .firq_status(firq_status), .cpu_irq(cpu_irq),
        .cpu_firq(cpu_firq)
    );

    task acknowledge_both;
        begin
            irq_ack = 1'b1;
            firq_ack = 1'b1;
            @(posedge clock); #1;
            irq_ack = 1'b0;
            firq_ack = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clock);
        #1 reset = 1'b0;
        irq_master_enable = 1'b1;
        firq_master_enable = 1'b1;

        // Verify every documented source occupies the same bit in FF92 and
        // FF93, latches even while masked, and asserts only when enabled.
        for (source = 0; source < 6; source = source + 1) begin
            irq_enable = 6'h00;
            firq_enable = 6'h00;
            event_pulse = 6'b000001 << source;
            @(posedge clock); #1;
            event_pulse = 6'h00;
            if (irq_status !== (6'b000001 << source) ||
                firq_status !== (6'b000001 << source)) begin
                $display("FAIL source bit %0d did not latch in FF92/FF93", source);
                failures = failures + 1;
            end
            if (cpu_irq || cpu_firq) begin
                $display("FAIL masked source bit %0d asserted CPU interrupt", source);
                failures = failures + 1;
            end

            irq_enable = 6'b000001 << source;
            firq_enable = 6'b000001 << source;
            #1;
            if (!cpu_irq || !cpu_firq) begin
                $display("FAIL enabled source bit %0d did not assert IRQ/FIRQ", source);
                failures = failures + 1;
            end

            // Reading FF92 acknowledges IRQ status only.
            irq_ack = 1'b1;
            @(posedge clock); #1;
            irq_ack = 1'b0;
            if (irq_status !== 6'h00 || cpu_irq) begin
                $display("FAIL FF92 acknowledge for source bit %0d", source);
                failures = failures + 1;
            end
            if (firq_status !== (6'b000001 << source) || !cpu_firq) begin
                $display("FAIL FF92 incorrectly acknowledged FF93 bit %0d", source);
                failures = failures + 1;
            end

            firq_ack = 1'b1;
            @(posedge clock); #1;
            firq_ack = 1'b0;
            if (firq_status !== 6'h00 || cpu_firq) begin
                $display("FAIL FF93 acknowledge for source bit %0d", source);
                failures = failures + 1;
            end
        end

        // Pending sources remain latched while the INIT0 master gates are
        // disabled, then become visible to the CPU when their master enables.
        acknowledge_both();
        irq_enable = 6'b111111;
        firq_enable = 6'b111111;
        irq_master_enable = 1'b0;
        firq_master_enable = 1'b0;
        event_pulse = 6'b101101;
        @(posedge clock); #1;
        event_pulse = 6'h00;
        if (cpu_irq || cpu_firq) begin
            $display("FAIL INIT0 master gates did not mask GIME sources");
            failures = failures + 1;
        end
        irq_master_enable = 1'b1;
        firq_master_enable = 1'b1;
        #1;
        if (!cpu_irq || !cpu_firq) begin
            $display("FAIL pending sources were lost behind INIT0 master gates");
            failures = failures + 1;
        end

        if (failures != 0)
            $fatal(1, "GIME interrupt reference mismatches=%0d", failures);
        $display("PASS: all six GIME sources latch, mask, route, and acknowledge");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clock);
        $fatal(1, "GIME interrupt reference test timeout");
    end
endmodule

`default_nettype wire
