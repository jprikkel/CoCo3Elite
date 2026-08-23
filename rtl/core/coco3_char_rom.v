`timescale 1ns/1ps
`default_nettype none

// Portable replacement for the Quartus COCO3GEN single-port ROM.
module COCO3GEN (
    input  wire [10:0] address,
    input  wire        clock,
    output reg  [7:0]  q
);
    (* rom_style = "block" *) reg [7:0] memory [0:2047];

    initial $readmemh("rtl/core/coco3gen.mem", memory);

    always @(posedge clock)
        q <= memory[address];
endmodule

`default_nettype wire
