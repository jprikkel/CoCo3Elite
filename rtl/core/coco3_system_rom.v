`timescale 1ns/1ps
`default_nettype none

// User-supplied 32 KiB CoCo 3 system ROM mapped at CPU $8000-$FFFF.
// scripts/prepare_coco3_rom.ps1 creates the ignored readmemh input.
module coco3_system_rom #(
    parameter INIT_FILE = "build/roms/coco3.mem"
) (
    input  wire        clock,
    input  wire [14:0] address,
    output reg  [7:0]  data
);
    (* rom_style = "block" *) reg [7:0] memory [0:32767];

    initial $readmemh(INIT_FILE, memory);

    always @(posedge clock)
        data <= memory[address];
endmodule

`default_nettype wire
