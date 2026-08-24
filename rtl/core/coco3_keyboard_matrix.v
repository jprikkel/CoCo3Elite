`timescale 1ns/1ps
`default_nettype none

// Convert the decoded 56-key CoCo key vector into the seven active-low rows
// returned by PIA0 port A. PIA0 port B selects one or more active-low columns.
module coco3_keyboard_matrix (
    input  wire [55:0] keys,
    input  wire        forced_shift,
    input  wire        shift_override,
    input  wire [7:0]  columns,
    output wire [7:0]  rows
);
    genvar row;
    genvar column;
    wire [7:0] pressed [0:6];

    generate
        for (row = 0; row < 7; row = row + 1) begin : row_gen
            for (column = 0; column < 8; column = column + 1) begin : column_gen
                if (row == 6 && column == 7) begin
                    assign pressed[row][column] =
                        (keys[55] && !shift_override) || forced_shift;
                end else begin
                    assign pressed[row][column] = keys[(row * 8) + column];
                end
            end

            assign rows[row] = ~(|((~columns) & pressed[row]));
        end
    endgenerate

    // Joystick comparator input is inactive until joystick hardware is added.
    assign rows[7] = 1'b1;
endmodule

`default_nettype wire
