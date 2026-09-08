`timescale 1ns/1ps
`default_nettype none

// Synchronous GIME IRQ/FIRQ pending and enable logic. Each event is latched
// independently for IRQ and FIRQ; reading the corresponding status register
// reports and acknowledges all pending sources, as on the CoCo 3 GIME.
module coco3_gime_interrupt (
    input  wire       clock,
    input  wire       reset,
    input  wire       irq_master_enable,
    input  wire       firq_master_enable,
    input  wire [5:0] irq_enable,
    input  wire [5:0] firq_enable,
    input  wire [5:0] event_pulse,
    input  wire       irq_ack,
    input  wire       firq_ack,
    input  wire       legacy_irq,
    input  wire       legacy_firq,
    output reg  [5:0] irq_status,
    output reg  [5:0] firq_status,
    output wire       cpu_irq,
    output wire       cpu_firq
);
    always @(posedge clock) begin
        if (reset) begin
            irq_status <= 6'b000000;
            firq_status <= 6'b000000;
        end else begin
            if (irq_ack)
                irq_status <= 6'b000000;
            else
                irq_status <= irq_status | event_pulse;

            if (firq_ack)
                firq_status <= 6'b000000;
            else
                firq_status <= firq_status | event_pulse;
        end
    end

    // INIT0 IEN/FEN select the GIME interrupt system in place of the legacy
    // PIA/cartridge paths, matching the routing in CoCo3FPGA 4.1.
    assign cpu_irq = irq_master_enable
        ? |(irq_status & irq_enable) : legacy_irq;
    assign cpu_firq = firq_master_enable
        ? |(firq_status & firq_enable) : legacy_firq;
endmodule

`default_nettype wire
