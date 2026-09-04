`timescale 1ns/1ps

// Directed regression for the short non-border streak seen at the upper-left
// of legacy PMODE screens.  The setup mirrors PALTEST.BAS: legacy graphics,
// color set 0, non-border video RAM data, and the normal black border.
module gime_border_tb;
    reg pixel_clk = 1'b0;
    reg reset_n = 1'b0;
    wire [8:0] color;
    wire hsync, vsync, hblank, vblank, video_active;
    wire [19:0] ram_address;
    integer samples = 0;
    integer failures = 0;

    always #20 pixel_clk = ~pixel_clk; // 25 MHz

    COCO3VIDEO dut (
        .PIX_CLK(pixel_clk), .RESET_N(reset_n), .COLOR(color),
        .HSYNC(hsync), .SYNC_FLAG(), .VSYNC(vsync),
        .HBLANKING(hblank), .VBLANKING(vblank),
        .RAM_ADDRESS(ram_address), .RAM_DATA(16'hffff),
        .VIDEO_ACTIVE(video_active),
        .COCO(1'b1), .V(3'b110), .BP(1'b1), .VERT(7'd0),
        .VID_CONT(4'b0000), .CSS(1'b0), .LPF(2'b00),
        .VERT_FIN_SCRL(4'd0), .HLPR(1'b0), .LPR(3'b000),
        .HRES(4'b0000), .CRES(2'b00), .HVEN(1'b0),
        .HOR_OFFSET(7'd0), .SCRN_START_HSB(2'b00),
        .SCRN_START_MSB(8'h00), .SCRN_START_LSB(8'h00),
        .BLINK(1'b0), .SWITCH5(1'b0)
    );

    // Sample where the downstream RGB mapper samples the registered COLOR.
    // During the visible top border every active pixel must be logical border
    // color 16; framebuffer colors here reproduce the hardware streak.
    always @(posedge pixel_clk) begin
        if (reset_n && dut.LINE < 10'd32 && video_active) begin
            samples = samples + 1;
            if (color !== 9'h100) begin
                failures = failures + 1;
                if (failures <= 20)
                    $display("BORDER LEAK line=%0d pixel=%0d color=%03h cc=%03h hb=%0d vb=%0d hblank=%0d vblank=%0d",
                        dut.LINE, dut.PIXEL_COUNT, color, dut.CCOLOR,
                        dut.HBORDER, dut.VBORDER, hblank, vblank);
            end
        end
    end

    initial begin
        repeat (8) @(posedge pixel_clk);
        reset_n = 1'b1;
        wait (dut.LINE == 10'd32);
        @(posedge pixel_clk);
        $display("BORDER samples=%0d leaks=%0d", samples, failures);
        if (failures != 0)
            $fatal(1, "Legacy graphics data leaked into the visible top border");
        if (samples < 1000)
            $fatal(1, "Top-border sampling window was unexpectedly short");
        $display("PASS: legacy graphics top border is uniform");
        $finish;
    end
endmodule
