`timescale 1ns/1ps
`default_nettype none

// Character-cell display owned by the management firmware.  The MMIO block
// supplies 72x28 cells. ASCII uses a dedicated UI font; project-owned glyphs
// provide browser icons and continuous panel lines without spending columns
// on textual [DIR], [CCC], and [BIN] tags. The emulated CoCo font is separate.
module manager_osd (
    input  wire        clock,
    input  wire        reset,
    input  wire        active,
    input  wire [9:0]  screen_x,
    input  wire [9:0]  screen_y,
    input  wire [4:0]  selected_row,
    input  wire        narrow_selection,
    input  wire        option_selection,
    input  wire [1:0]  font_style,
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
    localparam SETUP_LIST_RIGHT = 7'd24;

    wire inside = screen_x >= X0 && screen_x < X0 + (COLS << 3) &&
                  screen_y >= Y0 && screen_y < Y0 + (ROWS << 4);
    wire [9:0] local_x = screen_x - X0;
    wire [9:0] local_y = screen_y - Y0;
    wire [6:0] column = local_x[9:3];
    wire [4:0] row = local_y[8:4];
    // Seventy-two columns are not a power of two, so map the visible cell to
    // the same packed row-major address used by the management firmware.
    assign char_address = row * 11'd72 + column;

    // The management font ROM is indexed by a seven-bit ASCII character code.
    wire [12:0] font_address = {font_style, char_data[6:0], local_y[3:0]};
    wire [7:0] font_bits;
    reg inside_d, active_d, selected_d, icon_d;
    reg [6:0] glyph_code_d;
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
                7'h10: custom_row = (y>=4'd7 && y<=4'd9) ? 8'hff : 8'h00; // horizontal
                7'h11: custom_row = 8'h38;                                // pane vertical
                7'h12: case (y) // rounded top left
                    4'd3: custom_row=8'h07; 4'd4: custom_row=8'h0e;
                    4'd5: custom_row=8'h1c; 4'd6: custom_row=8'h38;
                    4'd7,4'd8,4'd9: custom_row=8'h3f;
                    default: custom_row=(y>4'd9)?8'h38:8'h00;
                endcase
                7'h13: case (y) // rounded top right
                    4'd3: custom_row=8'he0; 4'd4: custom_row=8'h70;
                    4'd5: custom_row=8'h38; 4'd6: custom_row=8'h1c;
                    4'd7,4'd8,4'd9: custom_row=8'hfc;
                    default: custom_row=(y>4'd9)?8'h1c:8'h00;
                endcase
                7'h14: case (y) // rounded bottom left
                    4'd7,4'd8,4'd9: custom_row=8'h3f;
                    4'd10: custom_row=8'h38; 4'd11: custom_row=8'h1c;
                    4'd12: custom_row=8'h0e; 4'd13: custom_row=8'h07;
                    default: custom_row=(y<4'd7)?8'h38:8'h00;
                endcase
                7'h15: case (y) // rounded bottom right
                    4'd7,4'd8,4'd9: custom_row=8'hfc;
                    4'd10: custom_row=8'h1c; 4'd11: custom_row=8'h38;
                    4'd12: custom_row=8'h70; 4'd13: custom_row=8'he0;
                    default: custom_row=(y<4'd7)?8'h1c:8'h00;
                endcase
                7'h16: custom_row = (y>=4'd7 && y<=4'd9) ? 8'h3f : 8'h38; // tee right
                7'h17: custom_row = (y>=4'd7 && y<=4'd9) ? 8'hfc : 8'h1c; // tee left
                7'h18: custom_row = y<4'd7 ? 8'h00 :
                                      (y<=4'd9 ? 8'hff : 8'h38);          // tee down
                7'h19: custom_row = y>4'd9 ? 8'h00 :
                                      (y>=4'd7 ? 8'hff : 8'h38);          // tee up
                7'h1a: custom_row = 8'h38;                                // left frame
                7'h1b: custom_row = 8'h1c;                                // right frame
                7'h1c: custom_row = (y>=4'd7 && y<=4'd9) ? 8'h3f : 8'h00; // left rule cap
                7'h1d: custom_row = (y>=4'd7 && y<=4'd9) ? 8'hfc : 8'h00; // right rule cap
                7'h1e,7'h1f,7'h20: case (y) // three-pixel RGB logo slash
                    4'd2,4'd3: custom_row=8'h07;
                    4'd4,4'd5: custom_row=8'h0e;
                    4'd6,4'd7: custom_row=8'h1c;
                    4'd8,4'd9: custom_row=8'h38;
                    4'd10,4'd11: custom_row=8'h70;
                    4'd12,4'd13: custom_row=8'he0;
                    default: custom_row=8'h00;
                endcase
                7'h21: case (y) // left setting arrow
                    4'd5,4'd10: custom_row=8'h10;
                    4'd6,4'd9: custom_row=8'h30;
                    4'd7,4'd8: custom_row=8'h70;
                    default: custom_row=8'h00;
                endcase
                7'h22: case (y) // right setting arrow
                    4'd5,4'd10: custom_row=8'h08;
                    4'd6,4'd9: custom_row=8'h0c;
                    4'd7,4'd8: custom_row=8'h0e;
                    default: custom_row=8'h00;
                endcase
                default: custom_row=8'h00;
            endcase
        end
    endfunction

    manager_font_rom font_i (.address(font_address), .clock(clock), .q(font_bits));
    wire [7:0] glyph_bits = icon_d ? icon_bits_d : font_bits;

    always @(posedge clock) begin
        if (reset) begin
            inside_d <= 1'b0;
            active_d <= 1'b0;
            selected_d <= 1'b0;
            icon_d <= 1'b0;
            glyph_code_d <= 7'h00;
            bit_index_d <= 3'd0;
            icon_bits_d <= 8'h00;
        end else begin
            inside_d <= inside;
            active_d <= active;
            // The selected entry is reverse video across only the file-list
            // pane; details on the right retain the dark background.
            selected_d <= row == selected_row &&
                          column >= (option_selection ? 7'd27 : 7'd1) &&
                          column <= (option_selection ? 7'd70 :
                                     (narrow_selection ? SETUP_LIST_RIGHT : LIST_RIGHT));
            icon_d <= char_data[7];
            glyph_code_d <= char_data[6:0];
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
                red = 8'hff;
                green = 8'hd0;
                blue = 8'h70;
                if (glyph_bits[bit_index_d]) begin
                    red = 8'h00;
                    green = 8'h00;
                    blue = 8'h00;
                end
            end else begin
                red = 8'h02;
                green = 8'h02;
                blue = 8'h00;
                if (glyph_bits[bit_index_d]) begin
                    case (glyph_code_d)
                        7'h1e: begin red=8'hff; green=8'h28; blue=8'h20; end
                        7'h1f: begin red=8'h20; green=8'he8; blue=8'h48; end
                        7'h20: begin red=8'h30; green=8'h70; blue=8'hff; end
                        default: begin red=8'hff; green=8'hd0; blue=8'h70; end
                    endcase
                end
            end
        end
    end
endmodule

`default_nettype wire
