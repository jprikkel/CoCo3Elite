`timescale 1ns/1ps
`default_nettype none

// 128 KiB base CoCo 3 memory. The CPU currently accesses the lower 64 KiB;
// later GIME/SAM translation will supply the seventeenth physical address bit.
module coco3_128k_ram #(
    parameter [7:0] INIT_VALUE = 8'h20
) (
    input  wire        clock,
    input  wire [16:0] cpu_address,
    input  wire [7:0]  cpu_write_data,
    input  wire        cpu_write_enable,
    output reg  [7:0]  cpu_read_data,
    input  wire [19:0] video_address,
    output reg  [15:0] video_read_data
);
    (* ram_style = "block" *) reg [7:0] memory_low  [0:65535];
    (* ram_style = "block" *) reg [7:0] memory_high [0:65535];
    reg [7:0] cpu_low_data;
    reg [7:0] cpu_high_data;
    integer i;

    initial begin
        for (i = 0; i < 65536; i = i + 1)
            begin
                memory_low[i]  = INIT_VALUE;
                memory_high[i] = INIT_VALUE;
            end
    end

    always @(posedge clock) begin
        cpu_low_data <= memory_low[cpu_address[16:1]];
        if (cpu_write_enable && !cpu_address[0])
            memory_low[cpu_address[16:1]] <= cpu_write_data;
    end

    always @(posedge clock) begin
        cpu_high_data <= memory_high[cpu_address[16:1]];
        if (cpu_write_enable && cpu_address[0])
            memory_high[cpu_address[16:1]] <= cpu_write_data;
    end

    always @(posedge clock) begin
        video_read_data[7:0]  <= memory_low[video_address[15:0]];
        video_read_data[15:8] <= memory_high[video_address[15:0]];
    end

    always @*
        cpu_read_data = cpu_address[0] ? cpu_high_data : cpu_low_data;
endmodule

`default_nettype wire
