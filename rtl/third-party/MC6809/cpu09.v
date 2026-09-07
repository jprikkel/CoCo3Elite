`timescale 1ns/1ps
`default_nettype none

// Compatibility wrapper for the CoCo3Elite bus.  The cycle-accurate core
// consumes the externally generated E and Q phases of a 6809E.
module cpu09 (
    input wire clk, rst,
    output wire vma, lic_out, ifetch, opfetch, ba, bs,
    output wire [15:0] addr,
    output wire rw,
    output wire [7:0] data_out,
    input wire [7:0] data_in,
    input wire irq, firq, nmi, halt, hold
);
    reg [1:0] phase = 2'b00;
    reg e = 1'b0;
    reg q = 1'b0;
    wire avma, busy, lic;
    wire rnw;
    wire [7:0] dout;

    always @(negedge clk) begin
        case (phase)
            2'b00: e <= 1'b0;
            2'b01: q <= 1'b1;
            2'b10: e <= 1'b1;
            2'b11: q <= 1'b0;
        endcase
        if (!hold)
            phase <= phase + 2'b01;
    end

    mc6809i core (
        .D(data_in), .DOut(dout), .ADDR(addr), .RnW(rnw), .E(e), .Q(q),
        .BS(bs), .BA(ba), .nIRQ(!irq), .nFIRQ(!firq), .nNMI(!nmi),
        .AVMA(avma), .BUSY(busy), .LIC(lic), .nHALT(!halt),
        .nRESET(!rst), .nDMABREQ(1'b1), .RegData()
    );

    assign data_out = dout;
    assign rw = rnw;
    // The surrounding CoCo bus expects a one-clock enable, while the 6809E
    // holds each address and R/W value across four E/Q phases.  Phase 1 is
    // the service clock immediately following falling E; qualifying VMA here
    // prevents RAM and I/O peripherals from consuming one CPU access four
    // times.  BA suppresses accesses while the CPU has released the bus.
    assign vma = !ba && phase == 2'b01;
    assign lic_out = lic;
    assign ifetch = 1'b0;
    assign opfetch = 1'b0;
endmodule
`default_nettype wire
