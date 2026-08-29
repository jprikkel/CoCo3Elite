`timescale 1ns/1ps
`default_nettype none

// Digital approximation of the NTSC color artifacts produced by the CoCo's
// 256-pixel, one-bit graphics modes. The source presents each logical pixel
// for two 25 MHz clocks. A five-sample window distinguishes narrow detail
// from solid white areas; narrow white detail is colored according to its
// half-resolution subcarrier phase while broad areas retain their source RGB.
//
// All video/control outputs are delayed by two pixel clocks so the center of
// the neighborhood and the HDMI control signals remain aligned.
module ntsc_artifact_filter (
    input  wire       pixel_clk,
    input  wire       reset,
    input  wire       enable,
    input  wire       phase_reverse,
    input  wire       in_hsync,
    input  wire       in_vsync,
    input  wire       in_video_enable,
    input  wire       in_on_pixel,
    input  wire [7:0] in_red,
    input  wire [7:0] in_green,
    input  wire [7:0] in_blue,
    output wire       out_hsync,
    output wire       out_vsync,
    output wire       out_video_enable,
    output reg  [7:0] out_red,
    output reg  [7:0] out_green,
    output reg  [7:0] out_blue
);
    reg [4:0] on_pipe;
    reg [4:0] enable_pipe;
    reg [4:0] active_pipe;
    reg [4:0] hsync_pipe;
    reg [4:0] vsync_pipe;
    reg [9:0] x_count;
    reg       was_active;
    reg [9:0] x_pipe [0:4];
    reg [7:0] red_pipe [0:4];
    reg [7:0] green_pipe [0:4];
    reg [7:0] blue_pipe [0:4];
    integer i;

    wire window_is_solid = &on_pipe;
    wire artifact_phase = x_pipe[2][1] ^ phase_reverse;

    always @(posedge pixel_clk) begin
        if (reset) begin
            on_pipe <= 0;
            enable_pipe <= 0;
            active_pipe <= 0;
            hsync_pipe <= 5'b11111;
            vsync_pipe <= 5'b11111;
            x_count <= 0;
            was_active <= 0;
            for (i = 0; i < 5; i = i + 1) begin
                x_pipe[i] <= 0;
                red_pipe[i] <= 0;
                green_pipe[i] <= 0;
                blue_pipe[i] <= 0;
            end
        end else begin
            on_pipe <= {on_pipe[3:0], in_on_pixel && in_video_enable};
            enable_pipe <= {enable_pipe[3:0], enable};
            active_pipe <= {active_pipe[3:0], in_video_enable};
            hsync_pipe <= {hsync_pipe[3:0], in_hsync};
            vsync_pipe <= {vsync_pipe[3:0], in_vsync};

            if (!in_video_enable) begin
                x_count <= 0;
                was_active <= 0;
            end else if (!was_active) begin
                x_count <= 0;
                was_active <= 1;
            end else begin
                x_count <= x_count + 1'b1;
            end

            x_pipe[0] <= x_count;
            red_pipe[0] <= in_red;
            green_pipe[0] <= in_green;
            blue_pipe[0] <= in_blue;
            for (i = 1; i < 5; i = i + 1) begin
                x_pipe[i] <= x_pipe[i-1];
                red_pipe[i] <= red_pipe[i-1];
                green_pipe[i] <= green_pipe[i-1];
                blue_pipe[i] <= blue_pipe[i-1];
            end
        end
    end

    always @* begin
        out_red = red_pipe[2];
        out_green = green_pipe[2];
        out_blue = blue_pipe[2];

        if (enable_pipe[2] && active_pipe[2] && on_pipe[2] &&
            !window_is_solid) begin
            if (artifact_phase) begin
                // Blue artifact phase.
                out_red = 8'h28;
                out_green = 8'h58;
                out_blue = 8'hd8;
            end else begin
                // Orange/red artifact phase.
                out_red = 8'hd8;
                out_green = 8'h68;
                out_blue = 8'h20;
            end
        end
    end

    assign out_hsync = hsync_pipe[2];
    assign out_vsync = vsync_pipe[2];
    assign out_video_enable = active_pipe[2];
endmodule

`default_nettype wire
