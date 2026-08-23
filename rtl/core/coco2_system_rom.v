`timescale 1ns/1ps
`default_nettype none

// Combined Extended BASIC ($8000-$9FFF) and Color BASIC ($A000-$BFFF).
module coco2_system_rom (
    input wire clock,
    input wire [13:0] address,
    output reg [7:0] data
);
    (* rom_style = "block" *) reg [7:0] memory [0:16383];
    initial $readmemh("build/roms/coco2.mem", memory);
    always @(posedge clock) data <= memory[address];
endmodule

`default_nettype wire
