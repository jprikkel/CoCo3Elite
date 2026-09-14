`timescale 1ns/1ps
`default_nettype none

// Character-cell display owned by the management firmware.  The MMIO block
// supplies 72x28 cells. ASCII uses the CoCo font; project-owned glyphs provide
// browser icons and continuous panel lines without spending columns on
// textual [DIR], [CCC], and [BIN] tags.
module manager_osd (
    input  wire        clock,
    input  wire        reset,
    input  wire        active,
    input  wire [9:0]  screen_x,
    input  wire [9:0]  screen_y,
    input  wire [4:0]  selected_row,
    output wire [10:0] char_address,
    input  wire [7:0]  char_data,
    output reg  [7:0]  red,
    output reg  [7:0]  green,
    output reg  [7:0]  blue
);
    localparam X0 = 10'd32;
    localparam Y0 = 10'd16;
    localparam COLS = 10'd72;
    localparam ROWS = 10'd28;
    localparam LIST_RIGHT = 7'd46;

    wire inside = screen_x >= X0 && screen_x < X0 + (COLS << 3) &&
                  screen_y >= Y0 && screen_y < Y0 + (ROWS << 4);
    wire [9:0] local_x = screen_x - X0;
    wire [9:0] local_y = screen_y - Y0;
    wire [6:0] column = local_x[9:3];
    wire [4:0] row = local_y[8:4];
    // Seventy-two columns are not a power of two, so map the visible cell to
    // the same packed row-major address used by the management firmware.
    assign char_address = row * 11'd72 + column;

    // The CoCo 3 character ROM is indexed by a seven-bit character code.
    // The firmware stores ASCII, so retain all seven bits; truncating to six
    // turned A-Z into character slots 1-26 and produced garbled menu text.
    wire [10:0] font_address = {char_data[6:0], local_y[3:0]};
    wire [7:0] font_bits;
    reg inside_d, active_d, selected_d, icon_d;
    reg [2:0] bit_index_d;
    reg [7:0] icon_bits_d;

    function [7:0] custom_row;
        input [6:0] glyph;
        input [3:0] y;
        begin
            custom_row = 8'h00;
            case (glyph)
                7'h00: case (y) // parent-directory arrow
                    4'd3: custom_row=8'h10; 4'd4: custom_row=8'h38;
                    4'd5: custom_row=8'h7c; 4'd6: custom_row=8'hfe;
                    4'd7,4'd8,4'd9,4'd10,4'd11: custom_row=8'h10;
                    default: custom_row=8'h00;
                endcase
                7'h01: case (y) // folder
                    4'd3: custom_row=8'h38; 4'd4: custom_row=8'h7c;
                    4'd5: custom_row=8'h82;
                    4'd6,4'd7,4'd8,4'd9,4'd10,4'd11: custom_row=8'h81;
                    4'd12: custom_row=8'hff;
                    default: custom_row=8'h00;
                endcase
                7'h02: case (y) // 5.25-inch disk
                    4'd2,4'd13: custom_row=8'h7e;
                    4'd3,4'd4: custom_row=8'h5a;
                    4'd5: custom_row=8'h42;
                    4'd6,4'd7,4'd8: custom_row=8'h7e;
                    4'd9,4'd10,4'd11: custom_row=8'h66;
                    4'd12: custom_row=8'h42;
                    default: custom_row=8'h00;
                endcase
                7'h03: case (y) // ROM cartridge and edge pins
                    4'd3,4'd10: custom_row=8'h7e;
                    4'd4,4'd5,4'd8,4'd9: custom_row=8'h42;
                    4'd6,4'd7: custom_row=8'h5a;
                    4'd11: custom_row=8'h24; 4'd12: custom_row=8'h5a;
                    default: custom_row=8'h00;
                endcase
                7'h04: case (y) // executable cylinder
                    4'd3,4'd6,4'd10,4'd12: custom_row=8'h3c;
                    4'd4,4'd5,4'd7,4'd8,4'd9,4'd11: custom_row=8'h42;
                    default: custom_row=8'h00;
                endcase
                7'h10: custom_row = (y==4'd7 || y==4'd8) ? 8'hff : 8'h00; // horizontal
                7'h11: custom_row = 8'h18;                                // vertical
                7'h12: custom_row = y<4'd7 ? 8'h00 :
                                      (y<4'd9 ? 8'h1f : 8'h18);           // top left
                7'h13: custom_row = y<4'd7 ? 8'h00 :
                                      (y<4'd9 ? 8'hf8 : 8'h18);           // top right
                7'h14: custom_row = y>4'd8 ? 8'h00 :
                                      (y>4'd6 ? 8'h1f : 8'h18);           // bottom left
                7'h15: custom_row = y>4'd8 ? 8'h00 :
                                      (y>4'd6 ? 8'hf8 : 8'h18);           // bottom right
                7'h16: custom_row = (y==4'd7 || y==4'd8) ? 8'h1f : 8'h18; // tee right
                7'h17: custom_row = (y==4'd7 || y==4'd8) ? 8'hf8 : 8'h18; // tee left
                7'h18: custom_row = y<4'd7 ? 8'h00 :
                                      (y<4'd9 ? 8'hff : 8'h18);           // tee down
                7'h19: custom_row = y>4'd8 ? 8'h00 :
                                      (y>4'd6 ? 8'hff : 8'h18);           // tee up
                default: custom_row=8'h00;
            endcase
        end
    endfunction

    COCO3GEN font_i (.address(font_address), .clock(clock), .q(font_bits));
    wire [7:0] glyph_bits = icon_d ? icon_bits_d : font_bits;

    always @(posedge clock) begin
        if (reset) begin
            inside_d <= 1'b0;
            active_d <= 1'b0;
            selected_d <= 1'b0;
            icon_d <= 1'b0;
            bit_index_d <= 3'd0;
            icon_bits_d <= 8'h00;
        end else begin
            inside_d <= inside;
            active_d <= active;
            // Match the mockup: the highlight fills only the file-list pane,
            // while details on the right retain the dark background.
            selected_d <= row == selected_row && column >= 1 && column <= LIST_RIGHT;
            icon_d <= char_data[7];
            icon_bits_d <= custom_row(char_data[6:0], local_y[3:0]);
            bit_index_d <= 3'd7 - local_x[2:0];
        end
    end

    always @* begin
        red = 8'h00;
        green = 8'h00;
        blue = 8'h00;
        if (active_d && inside_d) begin
            if (selected_d) begin
                red = 8'h00;
                green = 8'ha8;
                blue = 8'hb8;
                if (glyph_bits[bit_index_d]) begin
                    red = 8'hff;
                    green = 8'hff;
                    blue = 8'hf0;
                end
            end else begin
                red = 8'h02;
                green = 8'h02;
                blue = 8'h00;
                if (glyph_bits[bit_index_d]) begin
                    red = 8'hff;
                    green = 8'hd0;
                    blue = 8'h70;
                end
            end
        end
    end
endmodule

`default_nettype wire
