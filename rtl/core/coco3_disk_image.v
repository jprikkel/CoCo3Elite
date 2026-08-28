`timescale 1ns/1ps
`default_nettype none

// Read-only 35-track Disk BASIC image: 35 * 18 * 256 = 161,280 bytes.
module coco3_disk_image #(
    parameter IMAGE_FILE = "build/disks/intruders.mem"
) (
    input  wire        clock,
    input  wire [17:0] address,
    output reg  [7:0]  data
);
    reg [7:0] memory [0:161279];

    initial $readmemh(IMAGE_FILE, memory);

    always @(posedge clock)
        if (address < 18'd161280)
            data <= memory[address];
        else
            data <= 8'hFF;
endmodule

`default_nettype wire
