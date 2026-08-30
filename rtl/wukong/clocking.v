`default_nettype none

module wukong_clocking (
    input  wire clk_50mhz,
    output wire pixel_clk,
    output wire serial_clk,
    output wire locked,
    output wire video_reset
);
    wire clk_in;
    wire clk_feedback;
    wire clk_feedback_buffered;
    wire pixel_clk_unbuffered;
    wire serial_clk_unbuffered;
    wire mmcm_locked;

    reg [7:0] startup_count = 8'h00;
    reg [1:0] lock_sync = 2'b00;

    IBUF clk_ibuf_i (.I(clk_50mhz), .O(clk_in));

`ifdef HDMI_LIBRARY_TEST
    // 50 MHz / 5 * 63 = 630 MHz VCO. HDMI VIC 1 uses an exact 25.2 MHz
    // pixel clock and the hdl-util serializer requires an exact 5x clock.
    localparam integer MMCM_DIVCLK = 5;
    localparam real    MMCM_MULT   = 63.000;
    localparam real    PIXEL_DIV   = 25.000;
    localparam integer SERIAL_DIV  = 5;
`else
    // Existing, hardware-proven CoCo video clocking.
    localparam integer MMCM_DIVCLK = 1;
    localparam real    MMCM_MULT   = 15.000;
    localparam real    PIXEL_DIV   = 30.000;
    localparam integer SERIAL_DIV  = 6;
`endif

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        .DIVCLK_DIVIDE(MMCM_DIVCLK),
        .CLKFBOUT_MULT_F(MMCM_MULT),
        .CLKOUT0_DIVIDE_F(PIXEL_DIV),
        .CLKOUT1_DIVIDE(SERIAL_DIV),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKIN1   (clk_in),
        .RST      (1'b0),
        .PWRDWN   (1'b0),
        .CLKFBIN  (clk_feedback_buffered),
        .CLKFBOUT (clk_feedback),
        .CLKOUT0  (pixel_clk_unbuffered),
        .CLKOUT1  (serial_clk_unbuffered),
        .LOCKED   (mmcm_locked)
    );

    BUFG feedback_bufg_i (.I(clk_feedback), .O(clk_feedback_buffered));
    BUFG pixel_bufg_i    (.I(pixel_clk_unbuffered), .O(pixel_clk));
    BUFG serial_bufg_i   (.I(serial_clk_unbuffered), .O(serial_clk));

    // Synchronize lock into the pixel domain and hold reset for 256 pixels.
    always @(posedge pixel_clk or negedge mmcm_locked) begin
        if (!mmcm_locked) begin
            lock_sync     <= 2'b00;
            startup_count <= 8'h00;
        end else begin
            lock_sync <= {lock_sync[0], 1'b1};
            if (!lock_sync[1])
                startup_count <= 8'h00;
            else if (!(&startup_count))
                startup_count <= startup_count + 1'b1;
        end
    end

    assign locked      = lock_sync[1];
    assign video_reset = !(&startup_count);
endmodule

`default_nettype wire
