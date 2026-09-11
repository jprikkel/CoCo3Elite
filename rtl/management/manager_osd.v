`timescale 1ns/1ps
`default_nettype none

// Character-cell display owned by the management firmware.  The MMIO block
// supplies 48x20 ASCII cells; this renderer deliberately knows nothing about
// filesystems or menu policy so a richer Ultimate-style UI can reuse the same
// hardware interface later.
module manager_osd (
    input  wire        clock,
    input  wire        reset,
    input  wire        active,
    input  wire [9:0]  screen_x,
    input  wire [9:0]  screen_y,
    input  wire [4:0]  selected_row,
    output wire [9:0]  char_address,
    input  wire [7:0]  char_data,
    output reg  [7:0]  red,
    output reg  [7:0]  green,
    output reg  [7:0]  blue
);
    localparam X0 = 10'd128;
    localparam Y0 = 10'd80;
    localparam COLS = 10'd48;
    localparam ROWS = 10'd20;

    wire inside = screen_x >= X0 && screen_x < X0 + (COLS << 3) &&
                  screen_y >= Y0 && screen_y < Y0 + (ROWS << 4);
    wire [9:0] local_x = screen_x - X0;
    wire [9:0] local_y = screen_y - Y0;
    wire [5:0] column = local_x[8:3];
    wire [4:0] row = local_y[8:4];
    assign char_address = ({5'b0,row} << 5) + ({5'b0,row} << 4) +
                          {4'b0,column};

    // The CoCo 3 character ROM is indexed by a seven-bit character code.
    // The firmware stores ASCII, so retain all seven bits; truncating to six
    // turned A-Z into character slots 1-26 and produced garbled menu text.
    wire [10:0] font_address = {char_data[6:0], local_y[3:0]};
    wire [7:0] font_bits;
    reg inside_d, active_d, selected_d;
    reg [2:0] bit_index_d;

    COCO3GEN font_i (.address(font_address), .clock(clock), .q(font_bits));

    always @(posedge clock) begin
        if (reset) begin
            inside_d <= 1'b0;
            active_d <= 1'b0;
            selected_d <= 1'b0;
            bit_index_d <= 3'd0;
        end else begin
            inside_d <= inside;
            active_d <= active;
            selected_d <= row == selected_row;
            bit_index_d <= 3'd7 - local_x[2:0];
        end
    end

    always @* begin
        red = 8'h00;
        green = 8'h00;
        blue = 8'h00;
        if (active_d && inside_d) begin
            if (selected_d) begin
                red = 8'h18;
                green = 8'hb8;
                blue = 8'he8;
                if (font_bits[bit_index_d]) begin
                    red = 8'h00;
                    green = 8'h18;
                    blue = 8'h28;
                end
            end else begin
                red = 8'h08;
                green = 8'h18;
                blue = 8'h38;
                if (font_bits[bit_index_d]) begin
                    red = 8'he8;
                    green = 8'hf0;
                    blue = 8'hff;
                end
            end
        end
    end
endmodule

`default_nettype wire
