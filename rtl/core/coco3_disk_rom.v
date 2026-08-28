`timescale 1ns/1ps
`default_nettype none

// Standard 8 KiB Disk Extended Color BASIC 1.1 cartridge ROM. The cartridge
// window is $C000-$DFFF, so the CPU address maps directly to these 13 bits.
module coco3_disk_rom (
    input  wire        clock,
    input  wire [12:0] address,
    output reg  [7:0]  data
);
    reg [7:0] memory [0:8191];

    initial $readmemh("build/roms/disk11.mem", memory);

    always @(posedge clock)
        data <= memory[address];
endmodule

`default_nettype wire
