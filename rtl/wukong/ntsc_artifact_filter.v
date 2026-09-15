`timescale 1ns/1ps
`default_nettype none

// NTSC artifact decoding for the CoCo's 256-pixel, one-bit graphics modes.
// The source presents each logical pixel for two 25 MHz clocks. Decoder styles
// Thin and Classic use the original two-pixel decoder; MAME uses its six-pixel
// correction window and two-output lookup table; XRoar uses its phase-aware
// five-pixel LUT. Two pass starts with Thin and fills exactly one black output
// pixel between equal blue or orange artifact phases. White and wider gaps are
// never filled.
// Color selection remains independent of decoder style.
// All paths share a six-clock center delay so pixels and HDMI controls remain
// aligned when the style is changed live.
module ntsc_artifact_filter (
    input  wire       pixel_clk,
    input  wire       reset,
    input  wire       enable,
    input  wire [2:0] decoder_style,
    input  wire [1:0] color_set,
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
    reg [12:0] on_pipe;
    reg [6:0] enable_pipe;
    reg [6:0] active_pipe;
    reg [6:0] hsync_pipe;
    reg [6:0] vsync_pipe;
    reg [9:0] x_count;
    reg       was_active;
    reg [9:0] x_pipe [0:6];
    reg [7:0] red_pipe [0:6];
    reg [7:0] green_pipe [0:6];
    reg [7:0] blue_pipe [0:6];
    integer i;

    // Samples two clocks apart are adjacent 256-pixel source pixels. x[1]
    // selects the half of the legacy four-clock cell containing the center.
    wire pair_left  = x_pipe[6][1] ? on_pipe[8] : on_pipe[6];
    wire pair_right = x_pipe[6][1] ? on_pipe[6] : on_pipe[4];
    wire [1:0] artifact_pair = {pair_left, pair_right};
    wire [4:0] xroar_window = {on_pipe[10],on_pipe[8],on_pipe[6],
                               on_pipe[4],on_pipe[2]};
    reg [23:0] color_a, color_b;

    // MAME processes two logical pixels at a time. Its 128-entry correction
    // table address is a six-pixel window followed by the selected output
    // pixel. Select the same pair-relative window for either center parity.
    function [6:0] mame_table_address;
        input parity;
        input [12:0] samples;
        begin
            mame_table_address = parity
                ? {samples[12],samples[10],samples[8],samples[6],
                   samples[4],samples[2],1'b1}
                : {samples[10],samples[8],samples[6],samples[4],
                   samples[2],samples[0],1'b0};
        end
    endfunction

    wire [6:0] mame_address = mame_table_address(x_pipe[6][1],on_pipe);

    // MAME mc6847.cpp artifacter correction table (BSD-3-Clause). The seven
    // address bits are a six-pixel monochrome neighborhood and output select.
    function [3:0] mame_artifact_index;
        input [6:0] pattern;
        begin
            case (pattern)
                7'h00,7'h01,7'h02,7'h03,7'h04,7'h06,7'h25,7'h41,
                7'h43,7'h48,7'h4a,7'h65: mame_artifact_index=4'h0;
                7'h0c,7'h0e,7'h31,7'h33,7'h4c,7'h4e,7'h71,7'h73: mame_artifact_index=4'h1;
                7'h07,7'h27,7'h47,7'h60,7'h62,7'h64,7'h66,7'h67: mame_artifact_index=4'h2;
                7'h0d,7'h30,7'h32,7'h4d: mame_artifact_index=4'h3;
                7'h18,7'h19,7'h1a,7'h59: mame_artifact_index=4'h4;
                7'h08,7'h0a,7'h20,7'h22: mame_artifact_index=4'h5;
                7'h05,7'h11,7'h45,7'h51: mame_artifact_index=4'h6;
                7'h09,7'h0b,7'h49,7'h4b: mame_artifact_index=4'h7;
                7'h10,7'h12,7'h14,7'h16: mame_artifact_index=4'h8;
                7'h15,7'h17,7'h35,7'h37,7'h50,7'h52,7'h54,7'h55,
                7'h56,7'h57,7'h75,7'h77: mame_artifact_index=4'h9;
                7'h28,7'h29,7'h2a,7'h2b,7'h2c,7'h2e,7'h68,7'h69,
                7'h6a,7'h6b,7'h6c,7'h6e: mame_artifact_index=4'ha;
                7'h0f,7'h2f,7'h38,7'h39,7'h3a,7'h3b,7'h4f,7'h6f,
                7'h79,7'h7b: mame_artifact_index=4'hb;
                7'h1c,7'h1d,7'h1e,7'h5c,7'h5d,7'h5e,7'h70,7'h72,
                7'h74,7'h76: mame_artifact_index=4'hc;
                7'h21,7'h23,7'h24,7'h26,7'h61,7'h63: mame_artifact_index=4'hd;
                7'h13,7'h40,7'h42,7'h44,7'h46,7'h53: mame_artifact_index=4'he;
                default: mame_artifact_index=4'hf;
            endcase
        end
    endfunction

    // XRoar vo_render.c 5-bit cross-colour LUT (GPL-3.0-or-later), encoded
    // as indices into the same 16 blend colors.
    localparam [127:0] XROAR_PHASE0 = 128'hffbb9911bfaa20ddfcf499e6b3772600;
    localparam [127:0] XROAR_PHASE1 = 128'hffccaa22cf9910eefbf3aad5c4881500;
    function [3:0] xroar_artifact_index;
        input phase;
        input [4:0] pattern;
        begin
            if (phase)
                xroar_artifact_index = XROAR_PHASE1[pattern*4 +: 4];
            else
                xroar_artifact_index = XROAR_PHASE0[pattern*4 +: 4];
        end
    endfunction

    function [23:0] artifact_rgb;
        input [3:0] index;
        begin
            case (index)
                4'h0: artifact_rgb=24'h000000;
                4'h1: artifact_rgb=24'h280028;
                4'h2: artifact_rgb=24'h002800;
                4'h3: artifact_rgb=24'hffd2ff;
                4'h4: artifact_rgb=24'hd2ffd2;
                4'h5: artifact_rgb=24'hb43c1e;
                4'h6: artifact_rgb=24'h003278;
                4'h7: artifact_rgb=24'hff8c64;
                4'h8: artifact_rgb=24'h46c8ff;
                4'h9: artifact_rgb=24'h0080ff;
                4'ha: artifact_rgb=24'hff8000;
                4'hb: artifact_rgb=24'hfff0c8;
                4'hc: artifact_rgb=24'h64f0ff;
                4'hd: artifact_rgb=24'h3c0000;
                4'he: artifact_rgb=24'h00003c;
                default: artifact_rgb=24'hffffff;
            endcase
        end
    endfunction

    function [3:0] swap_artifact_phase;
        input [3:0] index;
        begin
            if (index == 4'h0 || index == 4'hf)
                swap_artifact_phase = index;
            else
                swap_artifact_phase = index[0] ? index + 1'b1
                                                : index - 1'b1;
        end
    endfunction

    wire [3:0] mame_index_unreversed = mame_artifact_index(mame_address);
    // MAME's reference phase is opposite the phase used by the CoCo pipeline:
    // exchange each artifact-color pair normally, and undo that exchange when
    // the user selects phase reversal.
    wire [3:0] mame_index = !phase_reverse
        ? swap_artifact_phase(mame_index_unreversed)
        : mame_index_unreversed;
    wire [3:0] xroar_index = xroar_artifact_index(
        x_pipe[6][1] ^ phase_reverse,xroar_window);

    // Return the Thin decoder's logical result for a source pixel: 0 is
    // black, 1/2 are the two artifact phases, and 3 is white. This permits a
    // second, centered pass without buffering a scanline.
    function [1:0] thin_code;
        input parity;
        input left_pixel;
        input center_pixel;
        input right_pixel;
        reg [1:0] pair;
        begin
            // Match artifact_pair above exactly. The pair selected for each
            // half-cell is phase dependent; reversing these branches makes a
            // second pass compare the opposite Thin colors.
            pair = parity ? {left_pixel,center_pixel}
                          : {center_pixel,right_pixel};
            if (!center_pixel)
                thin_code = 2'd0;
            else if (pair == 2'b01)
                thin_code = 2'd1;
            else if (pair == 2'b10)
                thin_code = 2'd2;
            else
                thin_code = 2'd3;
        end
    endfunction

    function [1:0] two_pass_code;
        input parity;
        input [6:0] pixels;
        reg [1:0] left1_code;
        reg [1:0] center_code;
        reg [1:0] right1_code;
        begin
            left1_code = thin_code(~parity,pixels[5],pixels[4],pixels[3]);
            center_code = thin_code(parity,pixels[4],pixels[3],pixels[2]);
            right1_code = thin_code(~parity,pixels[3],pixels[2],pixels[1]);

            // Fill exactly one black Thin-output pixel only when it is
            // immediately bounded by the same artifact phase. Codes 1 and 2
            // are the blue/orange chroma phases; white (3), mixed phases, and
            // gaps wider than one pixel are deliberately left unchanged.
            if (center_code == 2'd0 && left1_code == right1_code &&
                (left1_code == 2'd1 || left1_code == 2'd2))
                two_pass_code = left1_code;
            else
                two_pass_code = center_code;
        end
    endfunction

    wire [1:0] thin_center_code = thin_code(
        x_pipe[6][1],on_pipe[8],on_pipe[6],on_pipe[4]);
    wire [1:0] two_pass_result = two_pass_code(
        x_pipe[6][1],{on_pipe[12],on_pipe[10],on_pipe[8],on_pipe[6],
                      on_pipe[4],on_pipe[2],on_pipe[0]});
    wire two_pass_fill = thin_center_code == 2'd0 && two_pass_result != 2'd0;

    always @* begin
        case (color_set)
            2'd1: begin color_a=24'h20c8d8; color_b=24'hd83830; end
            2'd2: begin color_a=24'h38c858; color_b=24'hc838b8; end
            2'd3: begin color_a=24'h8058d8; color_b=24'ha8d838; end
            default: begin color_a=24'h2858d8; color_b=24'hd86820; end
        endcase
    end

    always @(posedge pixel_clk) begin
        if (reset) begin
            on_pipe <= 0;
            enable_pipe <= 0;
            active_pipe <= 0;
            hsync_pipe <= 7'b1111111;
            vsync_pipe <= 7'b1111111;
            x_count <= 0;
            was_active <= 0;
            for (i = 0; i < 7; i = i + 1) begin
                x_pipe[i] <= 0;
                red_pipe[i] <= 0;
                green_pipe[i] <= 0;
                blue_pipe[i] <= 0;
            end
        end else begin
            on_pipe <= {on_pipe[11:0], in_on_pixel && in_video_enable};
            enable_pipe <= {enable_pipe[5:0], enable};
            active_pipe <= {active_pipe[5:0], in_video_enable};
            hsync_pipe <= {hsync_pipe[5:0], in_hsync};
            vsync_pipe <= {vsync_pipe[5:0], in_vsync};

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
            for (i = 1; i < 7; i = i + 1) begin
                x_pipe[i] <= x_pipe[i-1];
                red_pipe[i] <= red_pipe[i-1];
                green_pipe[i] <= green_pipe[i-1];
                blue_pipe[i] <= blue_pipe[i-1];
            end
        end
    end

    always @* begin
        out_red = red_pipe[6];
        out_green = green_pipe[6];
        out_blue = blue_pipe[6];

        if (enable_pipe[6] && active_pipe[6]) begin
          if (decoder_style == 3'd3) begin
            {out_red,out_green,out_blue} = artifact_rgb(mame_index);
          end else if (decoder_style == 3'd4) begin
            {out_red,out_green,out_blue} = artifact_rgb(xroar_index);
          end else begin
            case (artifact_pair)
              2'b00: begin
                // Preserve the source RGB so enabling artifact processing does
                // not black out non-monochrome CoCo 3 video modes.
                out_red = red_pipe[6];
                out_green = green_pipe[6];
                out_blue = blue_pipe[6];
              end
              2'b11: begin
                out_red = 8'hff;
                out_green = 8'hff;
                out_blue = 8'hff;
              end
              2'b01: begin
                // Artifact color A (phase reversal exchanges A and B).
                if ((decoder_style != 3'd1 && decoder_style != 3'd5) ||
                    on_pipe[6]) begin
                    {out_red,out_green,out_blue} = phase_reverse ? color_b : color_a;
                end
              end
              2'b10: begin
                // Artifact color B.
                if ((decoder_style != 3'd1 && decoder_style != 3'd5) ||
                    on_pipe[6]) begin
                    {out_red,out_green,out_blue} = phase_reverse ? color_a : color_b;
                end
              end
              default: begin
                {out_red,out_green,out_blue} = color_a;
              end
            endcase
            if (decoder_style == 3'd5 && two_pass_fill) begin
                if (two_pass_result == 2'd1)
                    {out_red,out_green,out_blue} = phase_reverse ? color_b : color_a;
                else if (two_pass_result == 2'd2)
                    {out_red,out_green,out_blue} = phase_reverse ? color_a : color_b;
                else
                    {out_red,out_green,out_blue} = 24'hffffff;
            end
          end
        end
    end

    assign out_hsync = hsync_pipe[6];
    assign out_vsync = vsync_pipe[6];
    assign out_video_enable = active_pipe[6];
endmodule

`default_nettype wire
