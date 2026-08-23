`default_nettype none

// 640x480 progressive timing at a 25.000 MHz pixel clock (~59.52 Hz).
module video_timing (
    input  wire       pixel_clk,
    input  wire       reset,
    output reg  [9:0] x,
    output reg  [9:0] y,
    output wire       hsync,
    output wire       vsync,
    output wire       video_enable
);
    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 16;
    localparam integer H_SYNC   = 96;
    localparam integer H_TOTAL  = 800;
    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT  = 10;
    localparam integer V_SYNC   = 2;
    localparam integer V_TOTAL  = 525;

    always @(posedge pixel_clk) begin
        if (reset) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 10'd0;
            if (y == V_TOTAL - 1)
                y <= 10'd0;
            else
                y <= y + 1'b1;
        end else begin
            x <= x + 1'b1;
        end
    end

    assign video_enable = (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync = !((x >= H_ACTIVE + H_FRONT) &&
                     (x <  H_ACTIVE + H_FRONT + H_SYNC));
    assign vsync = !((y >= V_ACTIVE + V_FRONT) &&
                     (y <  V_ACTIVE + V_FRONT + V_SYNC));
endmodule

`default_nettype wire
