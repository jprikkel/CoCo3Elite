`timescale 1ns/1ps
`default_nettype none

// Captures one full-width stripe of the final HDMI image.  Firmware holds the
// 6809 in HALT and requests all eight 640x60 stripes in order, allowing a
// tear-free 640x480 snapshot without reserving an entire frame in block RAM.
// RGB332 keeps every output pixel while limiting the stripe buffer to 38,400
// bytes. Capture begins at a frame origin so each stripe has stable timing.
module video_frame_capture #(
    parameter integer SOURCE_WIDTH = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer STRIPE_HEIGHT = 60,
    parameter integer ADDRESS_WIDTH = 16
) (
    input wire clock,
    input wire reset,
    input wire [9:0] screen_x,
    input wire [9:0] screen_y,
    input wire [23:0] rgb,
    input wire request_toggle,
    input wire [2:0] request_stripe,
    output reg done_toggle,
    output reg busy,
    input wire [ADDRESS_WIDTH-1:0] read_address,
    output reg [7:0] read_data
);
    localparam integer STRIPE_BYTES = SOURCE_WIDTH * STRIPE_HEIGHT;
    (* ram_style = "block" *) reg [7:0] pixels [0:STRIPE_BYTES-1];
    reg request_seen;
    reg capture_pending;
    reg [2:0] pending_stripe;
    reg [2:0] active_stripe;

    wire in_source = screen_x < SOURCE_WIDTH && screen_y < SOURCE_HEIGHT;
    wire starting_capture = capture_pending && screen_x == 0 && screen_y == 0;
    wire [2:0] capture_stripe = starting_capture ? pending_stripe : active_stripe;
    wire [9:0] stripe_start = capture_stripe * STRIPE_HEIGHT;
    wire in_stripe = screen_y >= stripe_start &&
                     screen_y < stripe_start + STRIPE_HEIGHT;
    wire capture_pixel = (busy || starting_capture) && in_source && in_stripe;
    wire [9:0] stripe_row = screen_y - stripe_start;
    wire [ADDRESS_WIDTH-1:0] write_address =
        stripe_row * SOURCE_WIDTH + screen_x;
    wire last_pixel = screen_x == SOURCE_WIDTH - 1 &&
                      screen_y == stripe_start + STRIPE_HEIGHT - 1;
    wire [7:0] rgb332 = {rgb[23:21], rgb[15:13], rgb[7:6]};

    always @(posedge clock) begin
        read_data <= pixels[read_address];
        if (reset) begin
            request_seen <= request_toggle;
            capture_pending <= 1'b0;
            pending_stripe <= 3'b0;
            active_stripe <= 3'b0;
            done_toggle <= 1'b0;
            busy <= 1'b0;
        end else begin
            if (request_toggle != request_seen) begin
                request_seen <= request_toggle;
                capture_pending <= 1'b1;
                pending_stripe <= request_stripe;
            end

            if (starting_capture) begin
                capture_pending <= 1'b0;
                active_stripe <= pending_stripe;
                busy <= 1'b1;
            end

            if (capture_pixel) begin
                pixels[write_address] <= rgb332;
                if (last_pixel) begin
                    busy <= 1'b0;
                    done_toggle <= ~done_toggle;
                end
            end
        end
    end
endmodule

`default_nettype wire
