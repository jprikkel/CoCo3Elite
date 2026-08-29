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
    integer black_count = 0;
    integer blue_count = 0;
    integer orange_count = 0;

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
            if (out_active && {out_red,out_green,out_blue} == 24'h000000)
                black_count = black_count + 1;
            if (out_active && {out_red,out_green,out_blue} == 24'h2858d8)
                blue_count = blue_count + 1;
            if (out_active && {out_red,out_green,out_blue} == 24'hd86820)
                orange_count = orange_count + 1;
        end
    endtask

    task start_line;
        begin
            active = 0;
            repeat (6) drive_pixel(0);
            active = 1;
            colored_count = 0;
            white_count = 0;
            black_count = 0;
            blue_count = 0;
            orange_count = 0;
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(posedge clock);
        reset = 0;
        enable = 1;

        // 00 -> black.
        start_line();
        repeat (12) drive_pixel(0);
        if (black_count == 0) begin
            $display("FAIL: 00 pair did not decode to black");
            $fatal(1);
        end

        // 11 -> white.
        start_line();
        repeat (12) drive_pixel(1);
        if (white_count == 0) begin
            $display("FAIL: 11 pair did not decode to white");
            $fatal(1);
        end

        // 01 -> artifact color A (blue). Each logical pixel is driven twice.
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(0);
            repeat (2) drive_pixel(1);
        end
        if (blue_count == 0) begin
            $display("FAIL: 01 pair did not decode to artifact color A");
            $fatal(1);
        end

        // 10 -> artifact color B (orange/red).
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(1);
            repeat (2) drive_pixel(0);
        end
        if (orange_count == 0) begin
            $display("FAIL: 10 pair did not decode to artifact color B");
            $fatal(1);
        end

        // Phase reversal exchanges A and B.
        phase_reverse = 1;
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(0);
            repeat (2) drive_pixel(1);
        end
        if (orange_count == 0) begin
            $display("FAIL: phase reversal did not exchange A and B");
            $fatal(1);
        end
        phase_reverse = 0;

        // With the filter disabled, source RGB passes through unchanged.
        enable = 0;
        active = 1;
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
