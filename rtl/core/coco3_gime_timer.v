`timescale 1ns/1ps
`default_nettype none

// GIME programmable timer and the text blink phase driven by its expiry.
module coco3_gime_timer #(
    parameter integer FAST_DIVIDE = 7
) (
    input wire clock, input wire reset, input wire hsync,
    input wire fast_select,
    input wire write_msb, input wire write_lsb,
    input wire [7:0] write_data,
    output reg [3:0] timer_msb, output reg [7:0] timer_lsb,
    output reg blink
);
    reg timer_enable;
    reg [12:0] timer_count;
    reg previous_hsync;
    integer fast_count;
    wire slow_tick = previous_hsync && !hsync;
    wire fast_tick = fast_count == FAST_DIVIDE-1;
    wire timer_tick = fast_select ? fast_tick : slow_tick;

    always @(posedge clock) begin
        if (reset) begin
            timer_msb <= 4'h0; timer_lsb <= 8'h00;
            timer_enable <= 1'b0; timer_count <= 13'h1fff;
            blink <= 1'b1; previous_hsync <= 1'b1; fast_count <= 0;
        end else begin
            previous_hsync <= hsync;
            if (fast_tick) fast_count <= 0; else fast_count <= fast_count + 1;
            if (write_lsb) timer_lsb <= write_data;
            if (write_msb) begin
                timer_msb <= write_data[3:0];
                timer_enable <= 1'b1;
                timer_count <= 13'h1fff;
            end else if (timer_tick && timer_enable) begin
                if (timer_count == 13'h0000) begin
                    blink <= ~blink;
                    timer_count <= 13'h1fff;
                end else if (timer_count == 13'h1fff) begin
                    timer_count <= {1'b0,timer_msb,timer_lsb} - 1'b1;
                end else begin
                    timer_count <= timer_count - 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
