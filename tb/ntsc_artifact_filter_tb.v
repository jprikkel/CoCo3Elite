`timescale 1ns/1ps
`default_nettype none

module ntsc_artifact_filter_tb;
    reg clock = 0;
    reg reset = 1;
    reg enable = 0;
    reg phase_reverse = 0;
    reg hsync = 1;
    reg vsync = 1;
    reg active = 0;
    reg on_pixel = 0;
    reg [7:0] red = 0;
    reg [7:0] green = 0;
    reg [7:0] blue = 0;
    wire out_hsync, out_vsync, out_active;
    wire [7:0] out_red, out_green, out_blue;
    integer colored_count = 0;
    integer white_count = 0;

    ntsc_artifact_filter dut (
        .pixel_clk(clock), .reset(reset), .enable(enable),
        .phase_reverse(phase_reverse), .in_hsync(hsync), .in_vsync(vsync),
        .in_video_enable(active), .in_on_pixel(on_pixel),
        .in_red(red), .in_green(green), .in_blue(blue),
        .out_hsync(out_hsync), .out_vsync(out_vsync),
        .out_video_enable(out_active), .out_red(out_red),
        .out_green(out_green), .out_blue(out_blue)
    );

    always #5 clock = ~clock;

    task drive_pixel;
        input bit_value;
        begin
            on_pixel = bit_value;
            if (bit_value) begin red = 8'hff; green = 8'hff; blue = 8'hff; end
            else begin red = 0; green = 0; blue = 0; end
            @(posedge clock); #1;
            if (out_active && ({out_red,out_green,out_blue} == 24'h2858d8 ||
                               {out_red,out_green,out_blue} == 24'hd86820))
                colored_count = colored_count + 1;
            if (out_active && {out_red,out_green,out_blue} == 24'hffffff)
                white_count = white_count + 1;
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(posedge clock);
        reset = 0;
        active = 1;
        enable = 1;

        // Alternating logical pixels, each repeated for two 25 MHz clocks,
        // must produce artifact colors.
        for (i = 0; i < 8; i = i + 1) begin
            drive_pixel(i[0]);
            drive_pixel(i[0]);
        end
        repeat (5) drive_pixel(0);
        if (colored_count == 0) begin
            $display("FAIL: alternating detail did not produce artifact color");
            $fatal(1);
        end

        // A broad white run must retain a white interior.
        colored_count = 0;
        white_count = 0;
        repeat (8) drive_pixel(1);
        repeat (5) drive_pixel(0);
        if (white_count == 0) begin
            $display("FAIL: solid white area had no preserved white interior");
            $fatal(1);
        end

        // With the filter disabled, source RGB passes through unchanged.
        enable = 0;
        red = 8'h12; green = 8'h34; blue = 8'h56; on_pixel = 1;
        repeat (7) @(posedge clock);
        #1;
        if ({out_red,out_green,out_blue} != 24'h123456) begin
            $display("FAIL: disabled filter changed source RGB");
            $fatal(1);
        end

        $display("PASS: NTSC artifact filter");
        $finish;
    end
endmodule

`default_nettype wire
