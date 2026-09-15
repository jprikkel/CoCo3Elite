`timescale 1ns/1ps
`default_nettype none

module ntsc_artifact_filter_tb;
    reg clock = 0;
    reg reset = 1;
    reg enable = 0;
    reg phase_reverse = 0;
    reg [2:0] decoder_style = 2;
    reg [1:0] color_set = 0;
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
    integer emulator_color_count = 0;
    integer classic_colored_count = 0;
    integer thin_gap_colored_count = 0;

    ntsc_artifact_filter dut (
        .pixel_clk(clock), .reset(reset), .enable(enable),
        .decoder_style(decoder_style), .color_set(color_set),
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
            if (out_active && ({out_red,out_green,out_blue} == 24'h0080ff ||
                               {out_red,out_green,out_blue} == 24'hff8000 ||
                               {out_red,out_green,out_blue} == 24'h46c8ff ||
                               {out_red,out_green,out_blue} == 24'hff8c64))
                emulator_color_count = emulator_color_count + 1;
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
            emulator_color_count = 0;
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(posedge clock);
        reset = 0;
        enable = 1;

        // Verify representative entries from the imported neighborhood
        // decoders directly. These catch LUT ordering or transcription errors
        // that a simple color-presence smoke test would miss.
        if (dut.mame_artifact_index(7'h05) != 4'h6 ||
            dut.mame_artifact_index(7'h2a) != 4'ha ||
            dut.mame_artifact_index(7'h7f) != 4'hf) begin
            $display("FAIL: MAME correction table mismatch");
            $fatal(1);
        end
        if (dut.xroar_artifact_index(1'b0,5'h04) != 4'h7 ||
            dut.xroar_artifact_index(1'b1,5'h04) != 4'h8 ||
            dut.xroar_artifact_index(1'b0,5'h1f) != 4'hf) begin
            $display("FAIL: XRoar phase-aware 5-pixel LUT mismatch");
            $fatal(1);
        end
        if (dut.artifact_rgb(4'h7) != 24'hff8c64 ||
            dut.artifact_rgb(4'hc) != 24'h64f0ff) begin
            $display("FAIL: emulator artifact blend-color table mismatch");
            $fatal(1);
        end
        if (dut.swap_artifact_phase(4'h9) != 4'ha ||
            dut.swap_artifact_phase(4'ha) != 4'h9 ||
            dut.swap_artifact_phase(4'h0) != 4'h0) begin
            $display("FAIL: MAME artifact phase exchange mismatch");
            $fatal(1);
        end

        // MAME's table address is not seven consecutive pixels. It is a
        // six-pixel window followed by a first/second-output selector.
        if (dut.mame_table_address(1'b0,13'h445) != 7'h56) begin
            $display("FAIL: MAME even-pixel address mismatch");
            $fatal(1);
        end
        if (dut.mame_table_address(1'b1,13'h544) != 7'h3b) begin
            $display("FAIL: MAME odd-pixel address mismatch");
            $fatal(1);
        end

        // Two pass fills exactly one black Thin-output pixel only when its
        // immediate neighbors have the same blue or orange artifact phase.
        if (dut.two_pass_code(1'b1,7'b0010100) != 2'd2 ||
            dut.two_pass_code(1'b0,7'b0010100) != 2'd1) begin
            $display("FAIL: two-pass same-color gap was not filled");
            $fatal(1);
        end
        if (dut.two_pass_code(1'b1,7'b0010000) != 2'd0) begin
            $display("FAIL: two-pass unmatched gap was filled");
            $fatal(1);
        end
        // White and mixed-phase neighbors never trigger Two-pass filling.
        if (dut.two_pass_code(1'b1,7'b0110110) != 2'd0 ||
            dut.two_pass_code(1'b0,7'b0110110) != 2'd0) begin
            $display("FAIL: two-pass filled a white/mixed-phase gap");
            $fatal(1);
        end

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
        classic_colored_count = colored_count;

        // Thin mode retains one source-pixel-wide transitions rather than
        // painting the decoded color over both halves of the artifact cell.
        decoder_style = 1;
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(0);
            repeat (2) drive_pixel(1);
        end
        if (colored_count == 0 || colored_count >= classic_colored_count) begin
            $display("FAIL: thin mode did not reduce artifact width (%0d vs %0d)",
                     colored_count, classic_colored_count);
            $fatal(1);
        end
        decoder_style = 2;

        // Exercise the complete delayed video path, not just the helper. A
        // repeated alternating source leaves black gaps in Thin; Two pass must
        // color more pixels while using the same input and pipeline timing.
        decoder_style = 1;
        start_line();
        for (i = 0; i < 6; i = i + 1) begin
            repeat (2) drive_pixel(0);
            repeat (2) drive_pixel(1);
        end
        repeat (8) drive_pixel(0);
        thin_gap_colored_count = colored_count;

        decoder_style = 5;
        start_line();
        for (i = 0; i < 6; i = i + 1) begin
            repeat (2) drive_pixel(0);
            repeat (2) drive_pixel(1);
        end
        repeat (8) drive_pixel(0);
        if (colored_count <= thin_gap_colored_count) begin
            $display("FAIL: two-pass pipeline did not close Thin gaps (%0d vs %0d)",
                     colored_count,thin_gap_colored_count);
            $fatal(1);
        end
        decoder_style = 2;

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

        // Alternate palettes change both phase colors.
        color_set = 1;
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(0); repeat (2) drive_pixel(1);
        end
        if (colored_count != 0 || blue_count != 0 || orange_count != 0) begin
            $display("FAIL: alternate artifact palette retained default colors");
            $fatal(1);
        end
        color_set = 0;

        // The MAME and XRoar models use their wider source neighborhoods and
        // the shared 16-entry blend-color table.
        decoder_style = 3;
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(0); repeat (2) drive_pixel(1);
        end
        if (emulator_color_count == 0) begin
            $display("FAIL: MAME neighborhood decoder was not selected");
            $fatal(1);
        end
        decoder_style = 4;
        start_line();
        for (i = 0; i < 4; i = i + 1) begin
            repeat (2) drive_pixel(1); repeat (2) drive_pixel(0);
        end
        if (emulator_color_count == 0) begin
            $display("FAIL: XRoar neighborhood decoder was not selected");
            $fatal(1);
        end
        decoder_style = 2;

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
