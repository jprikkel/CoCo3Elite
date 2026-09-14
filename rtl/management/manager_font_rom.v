`timescale 1ns/1ps
`default_nettype none

// Dedicated 8x16 management-overlay font. Keeping this ROM separate from
// COCO3GEN lets the F12 interface use a polished UI typeface without changing
// the character generator seen by CoCo software.
module manager_font_rom (
    input  wire [10:0] address,
    input  wire        clock,
    output reg  [7:0]  q
);
    reg [7:0] memory [0:2047];

    initial $readmemh("rtl/management/manager_font.mem", memory);

    always @(posedge clock)
        q <= memory[address];
endmodule

`default_nettype wire
