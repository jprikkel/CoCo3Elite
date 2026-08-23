`default_nettype none

module test_pattern (
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire       video_enable,
    output reg  [7:0] red,
    output reg  [7:0] green,
    output reg  [7:0] blue
);
    wire border = (x < 4) || (x >= 636) || (y < 4) || (y >= 476);
    wire grid = ((x[5:0] == 0) || (y[5:0] == 0));
    wire checker = x[5] ^ y[5];

    always @* begin
        red   = 8'h00;
        green = 8'h00;
        blue  = 8'h00;

        if (video_enable) begin
            case (x[9:7])
                3'd0: begin red = 8'hff; green = 8'h00; blue = 8'h00; end
                3'd1: begin red = 8'hff; green = 8'hff; blue = 8'h00; end
                3'd2: begin red = 8'h00; green = 8'hff; blue = 8'h00; end
                3'd3: begin red = 8'h00; green = 8'hff; blue = 8'hff; end
                3'd4: begin red = 8'h00; green = 8'h00; blue = 8'hff; end
                default: begin red = 8'hff; green = 8'h00; blue = 8'hff; end
            endcase

            if (y >= 10'd320) begin
                red   = checker ? {x[6:0], 1'b0} : 8'h20;
                green = checker ? {y[6:0], 1'b0} : 8'h20;
                blue  = checker ? 8'hff : {x[6:0], 1'b0};
            end
            if (grid) begin
                red   = 8'hff;
                green = 8'hff;
                blue  = 8'hff;
            end
            if (border) begin
                red   = 8'hff;
                green = 8'hff;
                blue  = 8'hff;
            end
        end
    end
endmodule

`default_nettype wire
