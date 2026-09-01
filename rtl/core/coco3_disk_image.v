`timescale 1ns/1ps
`default_nettype none

// Read-only raw Disk BASIC image.
(* keep_hierarchy = "yes" *) module coco3_disk_image #(
    parameter IMAGE_FILE = "build/disks/intruders.mem",
    parameter integer IMAGE_BYTES = 161280,
    parameter ROM_STYLE = "block"
) (
    input  wire        clock,
    input  wire [18:0] address,
    output reg  [7:0]  data
);
    // Prevent Vivado from cascading separately initialized disk ROMs into one
    // chain; that optimization produces invalid cross-instance ADDR15 wiring
    // in Vivado 2025.2.
    (* rom_style = ROM_STYLE, cascade_height = 1 *)
    reg [7:0] memory [0:IMAGE_BYTES-1];

    initial $readmemh(IMAGE_FILE, memory);

    always @(posedge clock)
        if (address < IMAGE_BYTES)
            data <= memory[address];
        else
            data <= 8'hFF;
endmodule

`default_nettype wire
