`timescale 1ns/1ps
`default_nettype none

// Repository-owned 6809 diagnostic program mapped at $F000-$FFFF.
module coco3_diagnostic_rom (
    input  wire        clock,
    input  wire [11:0] address,
    output reg  [7:0]  data
);
    (* rom_style = "block" *) reg [7:0] memory [0:4095];

    initial $readmemh("rtl/core/coco3_diagnostic.mem", memory);

    always @(posedge clock)
        data <= memory[address];
endmodule

`default_nettype wire
