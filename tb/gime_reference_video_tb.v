`timescale 1ns/1ps
`default_nettype none

// Native-video conformance tests derived from Sock Master's GIME notes:
// https://www.6809.org.uk/twilight/sock/gime.html
//
// The renderer emits two transport lines per CoCo scanline. Consequently the
// documented 192/200/225 active line counts appear here as 384/400/450.
module gime_reference_video_tb;
    reg pixel_clock = 1'b0;
    reg reset_n = 1'b0;
    reg [1:0] lpf = 2'b11;
    reg [2:0] lpr = 3'b000;
    reg [3:0] hres = 4'h0;
    reg hven = 1'b0;
    reg [6:0] horizontal_offset = 7'h00;
    reg [7:0] start_msb = 8'hE0;
    reg [7:0] start_lsb = 8'h40;
    wire hsync;
    wire vblank;
    wire [19:0] ram_address;
    integer failures = 0;
    integer active_lines;
    integer mode;
    integer expected_stride;
    integer saw_wrap;
    reg [20:0] infinite_row_address;
    reg infinite_blank_seen;

    always #2 pixel_clock = ~pixel_clock;

    COCO3VIDEO dut (
        .PIX_CLK(pixel_clock), .RESET_N(reset_n), .COLOR(),
        .HSYNC(hsync), .SYNC_FLAG(), .VSYNC(), .HBLANKING(),
        .VBLANKING(vblank), .RAM_ADDRESS(ram_address),
        .RAM_DATA(16'hA55A), .VIDEO_ACTIVE(),
        .COCO(1'b0), .V(3'b000), .BP(1'b1), .VERT(7'h00),
        .VID_CONT(4'h0), .CSS(1'b0), .LPF(lpf),
        .VERT_FIN_SCRL(4'h0), .HLPR(1'b0), .LPR(lpr),
        .HRES(hres), .CRES(2'b10), .HVEN(hven),
        .HOR_OFFSET(horizontal_offset), .SCRN_START_HSB(2'b00),
        .SCRN_START_MSB(start_msb), .SCRN_START_LSB(start_lsb),
        .BLINK(1'b0), .SWITCH5(1'b0)
    );

    task apply_reset;
        begin
            reset_n = 1'b0;
            repeat (5) @(negedge pixel_clock);
            reset_n = 1'b1;
        end
    endtask

    task wait_for_line;
        input integer target;
        begin
            while (dut.LINE !== target[9:0]) begin
                @(negedge hsync);
                #1;
            end
        end
    endtask

    task wait_for_frame_start;
        begin
            while (dut.LINE == 10'd0) begin
                @(negedge hsync);
                #1;
            end
            while (dut.LINE != 10'd0) begin
                @(negedge hsync);
                #1;
            end
        end
    endtask

    task count_active_frame;
        output integer count;
        integer line_index;
        begin
            wait_for_frame_start();
            count = vblank ? 0 : 1; // line zero
            for (line_index = 1; line_index < 525; line_index = line_index + 1) begin
                @(negedge hsync);
                #1;
                if (!vblank)
                    count = count + 1;
            end
        end
    endtask

    initial begin
        // FF99 HRES selects exactly 16,20,32,40,64,80,128,160 bytes/row.
        force dut.ROW_ADD = 21'h12340;
        hven = 1'b0;
        for (mode = 0; mode < 8; mode = mode + 1) begin
            hres = mode[3:0];
            case (mode)
                0: expected_stride = 16;
                1: expected_stride = 20;
                2: expected_stride = 32;
                3: expected_stride = 40;
                4: expected_stride = 64;
                5: expected_stride = 80;
                6: expected_stride = 128;
                default: expected_stride = 160;
            endcase
            #1;
            if (dut.SCREEN_OFF !== 21'h12340 + expected_stride) begin
                $display("FAIL HRES=%0d stride expected=%0d got=%0d",
                         mode, expected_stride, dut.SCREEN_OFF - 21'h12340);
                failures = failures + 1;
            end
        end

        // FF9F.HVEN fixes the virtual row stride at 256 bytes.
        hven = 1'b1;
        for (mode = 0; mode < 8; mode = mode + 1) begin
            hres = mode[3:0];
            #1;
            if (dut.SCREEN_OFF !== 21'h12440) begin
                $display("FAIL HVEN stride HRES=%0d expected=256 got=%0d",
                         mode, dut.SCREEN_OFF - 21'h12340);
                failures = failures + 1;
            end
        end
        release dut.ROW_ADD;

        // FF98 LPR decoding, including both encodings of one line and the
        // special infinite graphics-row setting used by Boink.
        hven = 1'b0;
        for (mode = 0; mode < 8; mode = mode + 1) begin
            lpr = mode[2:0];
            #1;
            case (mode)
                0, 1: expected_stride = 0;  // last row-line index for height 1
                2: expected_stride = 1;
                3: expected_stride = 7;
                4: expected_stride = 8;
                5: expected_stride = 9;
                6: expected_stride = 10;
                default: expected_stride = 15;
            endcase
            if (dut.LINES_ROW !== expected_stride[3:0]) begin
                $display("FAIL LPR=%0d decoded last index expected=%0d got=%0d",
                         mode, expected_stride, dut.LINES_ROW);
                failures = failures + 1;
            end
        end

        // Conventional LPF modes must expose the documented active height.
        lpr = 3'b000;
        hres = 4'h7;
        lpf = 2'b00;
        apply_reset();
        count_active_frame(active_lines);
        if (active_lines != 384) begin
            $display("FAIL LPF=00 expected 384 doubled lines got=%0d", active_lines);
            failures = failures + 1;
        end

        lpf = 2'b01;
        apply_reset();
        count_active_frame(active_lines);
        if (active_lines != 400) begin
            $display("FAIL LPF=01 expected 400 doubled lines got=%0d", active_lines);
            failures = failures + 1;
        end

        lpf = 2'b11;
        apply_reset();
        count_active_frame(active_lines);
        if (active_lines != 450) begin
            $display("FAIL LPF=11 expected 450 doubled lines got=%0d", active_lines);
            failures = failures + 1;
        end

        // In graphics LPR=111, every active scanline repeats one memory row.
        lpr = 3'b111;
        lpf = 2'b11;
        apply_reset();
        wait_for_frame_start();
        infinite_row_address = dut.ROW_ADD;
        active_lines = vblank ? 0 : 1;
        if (!vblank && (dut.ROW_ADD !== infinite_row_address || dut.VLPR !== 0)) begin
            $display("FAIL infinite LPR initial row state");
            failures = failures + 1;
        end
        for (mode = 1; mode < 450; mode = mode + 1) begin
            @(negedge hsync); #1;
            if (!vblank) begin
                active_lines = active_lines + 1;
                if (dut.ROW_ADD !== infinite_row_address || dut.VLPR !== 0) begin
                    if (failures < 8)
                        $display("FAIL infinite LPR advanced line=%0d row=%h vlpr=%0d",
                                 dut.LINE, dut.ROW_ADD, dut.VLPR);
                    failures = failures + 1;
                end
            end
        end
        if (active_lines != 450) begin
            $display("FAIL infinite LPR sampled active lines=%0d", active_lines);
            failures = failures + 1;
        end

        // LPF=10 selected during vertical border means zero active lines.
        lpr = 3'b000;
        lpf = 2'b11;
        apply_reset();
        wait_for_line(480);
        if (!vblank) begin
            $display("FAIL test setup: line 480 was not in vertical blanking");
            failures = failures + 1;
        end
        lpf = 2'b10;
        count_active_frame(active_lines);
        if (active_lines != 0) begin
            $display("FAIL LPF=10 selected in border expected zero lines got=%0d",
                     active_lines);
            failures = failures + 1;
        end

        // LPF=10 selected while graphics are active means infinite display;
        // the active state must not be retriggered at a conventional boundary.
        lpf = 2'b11;
        apply_reset();
        wait_for_line(100);
        if (vblank) begin
            $display("FAIL test setup: line 100 was not active");
            failures = failures + 1;
        end
        lpf = 2'b10;
        saw_wrap = 0;
        infinite_blank_seen = 1'b0;
        while (!(saw_wrap && dut.LINE == 10'd100)) begin
            @(negedge hsync); #1;
            if (dut.LINE == 10'd0)
                saw_wrap = 1;
            if (vblank) begin
                if (!infinite_blank_seen)
                    $display("FAIL LPF=10 active selection blanked at line=%0d",
                             dut.LINE);
                infinite_blank_seen = 1'b1;
            end
        end
        if (infinite_blank_seen)
            failures = failures + 1;

        if (failures != 0)
            $fatal(1, "GIME video reference mismatches=%0d", failures);
        $display("PASS: GIME LPF, LPR, HRES, and HVEN reference behavior");
        $finish;
    end

    initial begin
        #30000000;
        $fatal(1, "GIME video reference test timeout");
    end
endmodule

`default_nettype wire
