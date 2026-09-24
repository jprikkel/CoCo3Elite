`timescale 1ns/1ps
`default_nettype none

module video_frame_capture_tb;
    reg clock = 0;
    reg reset = 1;
    reg [9:0] x = 0;
    reg [9:0] y = 0;
    reg [23:0] rgb = 0;
    reg request_toggle = 0;
    reg [5:0] request_stripe = 0;
    reg [3:0] read_address = 0;
    wire [7:0] read_data;
    wire done_toggle, busy;
    always #5 clock = ~clock;

    video_frame_capture #(
        .SOURCE_WIDTH(8), .SOURCE_HEIGHT(4), .STRIPE_HEIGHT(2),
        .ADDRESS_WIDTH(4), .STRIPE_INDEX_WIDTH(6)
    ) dut (
        .clock(clock), .reset(reset), .screen_x(x), .screen_y(y), .rgb(rgb),
        .request_toggle(request_toggle), .request_stripe(request_stripe),
        .done_toggle(done_toggle), .busy(busy),
        .read_address(read_address), .read_data(read_data)
    );

    task pixel;
        input [9:0] px;
        input [9:0] py;
        reg [7:0] red_value, green_value, blue_value;
        begin
            x = px; y = py;
            red_value = px * 32;
            green_value = py * 64;
            blue_value = (px ^ py) * 32;
            rgb = {red_value, green_value, blue_value};
            @(posedge clock); #1;
        end
    endtask

    function [7:0] expected_pixel;
        input integer source_x;
        input integer source_y;
        reg [7:0] red_value, green_value, blue_value;
        begin
            red_value = source_x * 32;
            green_value = source_y * 64;
            blue_value = (source_x ^ source_y) * 32;
            expected_pixel = {red_value[7:5], green_value[7:5],
                              blue_value[7:6]};
        end
    endfunction

    integer px, py;
    reg [7:0] expected;
    initial begin
        repeat (3) @(posedge clock);
        reset = 0;
        // Request away from the frame origin; capture must wait for x=0,y=0.
        x = 3; y = 2; request_stripe = 1; request_toggle = 1;
        @(posedge clock); #1;
        if (busy) $fatal(1, "capture started before frame origin");

        for (py = 0; py < 4; py = py + 1)
            for (px = 0; px < 8; px = px + 1)
                pixel(px, py);

        if (busy || done_toggle !== 1'b1)
            $fatal(1, "capture did not finish at final sample");

        for (py = 0; py < 2; py = py + 1) begin
            for (px = 0; px < 8; px = px + 1) begin
                read_address = py * 8 + px;
                @(posedge clock); #1;
                expected = expected_pixel(px, py + 2);
                if (read_data !== expected)
                    $fatal(1, "pixel %0d mismatch: %02x != %02x",
                           py * 8 + px, read_data, expected);
            end
        end
        $display("PASS: full-width RGB332 stripe capture");
        $finish;
    end
endmodule

`default_nettype wire
