`timescale 1ns/1ps
`default_nettype none

// Read-only 8 KiB diagnostic cartridge mapped at $C000-$DFFF.
module coco3_diagnostic_cartridge (
    input  wire        clock,
    input  wire [12:0] address,
    output reg  [7:0]  data
);
    reg [7:0] memory [0:8191];

    initial $readmemh("build/roms/diagnostic_cart.mem", memory);

    always @(posedge clock)
        data <= memory[address];
endmodule

`default_nettype wire
