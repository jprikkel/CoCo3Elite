`timescale 1ns/1ps
`default_nettype none

// Streaming CRT presentation filter. Controls are ports so the management
// subsystem can change them at runtime without rebuilding the FPGA image.
// Geometry is a streaming rounded-bezel/vignette approximation; true barrel
// coordinate remapping requires a framebuffer and is intentionally separate.
module crt_filter (
    input wire pixel_clk, input wire reset, input wire enable,
    input wire in_hsync, input wire in_vsync, input wire in_video_enable,
    input wire [7:0] in_red, input wire [7:0] in_green, input wire [7:0] in_blue,
    input wire [4:0] mask_layout, input wire [7:0] mask_intensity,
    input wire [2:0] bloom_size, input wire [7:0] bloom_threshold,
    input wire [6:0] corner_radius, input wire [6:0] vignette_size,
    input wire [7:0] vignette_strength,
    input wire [7:0] black_level, input wire [7:0] white_level,
    output reg out_hsync, output reg out_vsync, output reg out_video_enable,
    output reg [7:0] out_red, output reg [7:0] out_green, output reg [7:0] out_blue
);
    reg [9:0] x;
    reg [9:0] y;
    reg previous_hsync, previous_vsync, line_had_active;
    reg [7:0] previous_red, previous_green, previous_blue;
    reg [1:0] mask_level;
    reg [9:0] edge_x, edge_y, edge_distance;
    reg corner_blank;
    reg [8:0] corrected_red, corrected_green, corrected_blue;
    reg [8:0] bloom_red, bloom_green, bloom_blue;
    reg [7:0] mask_drop, mask_gain, vignette_gain;
    reg [15:0] scaled_red, scaled_green, scaled_blue;
    reg [15:0] vignette_drop;
    wire previous_bright = previous_red >= bloom_threshold ||
                           previous_green >= bloom_threshold ||
                           previous_blue >= bloom_threshold;

    function [1:0] phosphor_level;
        input [4:0] layout;
        input [9:0] px;
        input [9:0] py;
        begin
            case (layout)
                0:  phosphor_level = 2'd3;
                1:  phosphor_level = px[0] ? 2'd1 : 2'd3;
                2:  phosphor_level = py[0] ? 2'd1 : 2'd3;
                3:  phosphor_level = px[0] ^ py[0] ? 2'd1 : 2'd3;
                4:  phosphor_level = (px % 3 == 0) ? 2'd3 : 2'd1;
                5:  phosphor_level = (px % 3 == 1) ? 2'd3 : 2'd1;
                6:  phosphor_level = (px % 3 == 2) ? 2'd3 : 2'd1;
                7:  phosphor_level = (py % 3 == 0) ? 2'd3 : 2'd1;
                8:  phosphor_level = ((px + py) % 3 == 0) ? 2'd3 : 2'd1;
                9:  phosphor_level = ((px + (py << 1)) % 3 == 0) ? 2'd3 : 2'd1;
                10: phosphor_level = px[1:0] == 0 ? 2'd3 : 2'd1;
                11: phosphor_level = py[1:0] == 0 ? 2'd3 : 2'd1;
                12: phosphor_level = px[1] ^ py[1] ? 2'd1 : 2'd3;
                13: phosphor_level = (&{px[0],py[0]}) ? 2'd0 : 2'd3;
                14: phosphor_level = (px[1:0] == py[1:0]) ? 2'd3 : 2'd1;
                15: phosphor_level = (px[2:0] == 0) ? 2'd3 : 2'd2;
                16: phosphor_level = (py[2:0] == 0) ? 2'd3 : 2'd2;
                17: phosphor_level = (px[2:0] == py[2:0]) ? 2'd3 : 2'd2;
                18: phosphor_level = (px[0] && py[0]) ? 2'd1 : 2'd3;
                19: phosphor_level = (px[0] || py[0]) ? 2'd2 : 2'd3;
                20: phosphor_level = (px[1:0] == 2'd3) ? 2'd0 : 2'd3;
                21: phosphor_level = (py[1:0] == 2'd3) ? 2'd0 : 2'd3;
                22: phosphor_level = ((px + py) & 3) == 0 ? 2'd3 : 2'd2;
                default: phosphor_level = ((px - py) & 3) == 0 ? 2'd3 : 2'd2;
            endcase
        end
    endfunction

    always @(posedge pixel_clk) begin
        if (reset) begin
            x <= 0; y <= 0; previous_hsync <= 1; previous_vsync <= 1;
            line_had_active <= 0; previous_red <= 0; previous_green <= 0;
            previous_blue <= 0; out_hsync <= 1; out_vsync <= 1;
            out_video_enable <= 0; out_red <= 0; out_green <= 0; out_blue <= 0;
        end else begin
            previous_hsync <= in_hsync;
            previous_vsync <= in_vsync;
            if (previous_vsync && !in_vsync) y <= 0;
            if (previous_hsync && !in_hsync) begin
                if (line_had_active) y <= y + 1'b1;
                line_had_active <= 0;
            end
            if (in_video_enable) begin
                line_had_active <= 1;
                x <= x + 1'b1;
            end else x <= 0;

            previous_red <= in_red;
            previous_green <= in_green;
            previous_blue <= in_blue;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;
            out_video_enable <= in_video_enable;

            if (!enable || !in_video_enable) begin
                out_red <= in_red; out_green <= in_green; out_blue <= in_blue;
            end else if (corner_blank) begin
                out_red <= 0; out_green <= 0; out_blue <= 0;
            end else begin
                out_red <= scaled_red[15:8];
                out_green <= scaled_green[15:8];
                out_blue <= scaled_blue[15:8];
            end
        end
    end

    always @* begin
        mask_level = phosphor_level(mask_layout, x, y);
        edge_x = (x < (10'd639 - x)) ? x : (10'd639 - x);
        edge_y = (y < (10'd479 - y)) ? y : (10'd479 - y);
        edge_distance = edge_x < edge_y ? edge_x : edge_y;
        corner_blank = edge_x < corner_radius && edge_y < corner_radius &&
                       (edge_x + edge_y) < corner_radius;

        corrected_red = in_red > black_level ? in_red - black_level : 0;
        corrected_green = in_green > black_level ? in_green - black_level : 0;
        corrected_blue = in_blue > black_level ? in_blue - black_level : 0;
        if (corrected_red > white_level) corrected_red = white_level;
        if (corrected_green > white_level) corrected_green = white_level;
        if (corrected_blue > white_level) corrected_blue = white_level;

        bloom_red = corrected_red; bloom_green = corrected_green; bloom_blue = corrected_blue;
        if (previous_bright && bloom_size != 0) begin
            case (bloom_size)
                3'd1: begin
                    bloom_red = corrected_red + (previous_red >> 3);
                    bloom_green = corrected_green + (previous_green >> 3);
                    bloom_blue = corrected_blue + (previous_blue >> 3);
                end
                3'd2: begin
                    bloom_red = corrected_red + (previous_red >> 2);
                    bloom_green = corrected_green + (previous_green >> 2);
                    bloom_blue = corrected_blue + (previous_blue >> 2);
                end
                3'd3: begin
                    bloom_red = corrected_red + (previous_red >> 1);
                    bloom_green = corrected_green + (previous_green >> 1);
                    bloom_blue = corrected_blue + (previous_blue >> 1);
                end
                default: begin
                    bloom_red = corrected_red + previous_red;
                    bloom_green = corrected_green + previous_green;
                    bloom_blue = corrected_blue + previous_blue;
                end
            endcase
        end
        if (bloom_red > 255) bloom_red = 255;
        if (bloom_green > 255) bloom_green = 255;
        if (bloom_blue > 255) bloom_blue = 255;

        case (mask_level)
            0: mask_drop = mask_intensity;
            1: mask_drop = mask_intensity - (mask_intensity >> 2);
            2: mask_drop = mask_intensity >> 1;
            default: mask_drop = 0;
        endcase
        mask_gain = 8'hff - mask_drop;
        if (edge_distance < vignette_size && vignette_size != 0) begin
            vignette_drop = (vignette_size - edge_distance) * vignette_strength;
            vignette_gain = 8'hff - (vignette_drop / vignette_size);
        end else vignette_gain = 8'hff;

        scaled_red = bloom_red * mask_gain;
        scaled_red = (scaled_red[15:8] * vignette_gain);
        scaled_green = bloom_green * mask_gain;
        scaled_green = (scaled_green[15:8] * vignette_gain);
        scaled_blue = bloom_blue * mask_gain;
        scaled_blue = (scaled_blue[15:8] * vignette_gain);
    end
endmodule

`default_nettype wire
