`timescale 1ns/1ps
`default_nettype none

// Project-owned, SD-loaded CoCo ROM-Pak storage.  A raw .CCC image is an
// 8 KiB $C000-$DFFF ROM.  The CPU port deliberately has the same synchronous
// read timing as coco3_disk_rom and the former diagnostic cartridge; the
// manager port writes the image before it asserts the CART launch edge.
module coco3_sd_cartridge (
    input  wire        clock,
    input  wire [12:0] cpu_address,
    output reg  [7:0]  cpu_data,
    input  wire [12:0] manager_address,
    input  wire [7:0]  manager_data,
    input  wire        manager_write
);
    (* ram_style = "block" *) reg [7:0] memory [0:8191];

    always @(posedge clock) begin
        if (manager_write)
            memory[manager_address] <= manager_data;
        cpu_data <= memory[cpu_address];
    end
endmodule

`default_nettype wire
