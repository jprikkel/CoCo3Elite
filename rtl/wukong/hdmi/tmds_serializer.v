`default_nettype none

module tmds_serializer (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [9:0] parallel_data,
    output wire       serial_data
);
    wire shift1;
    wire shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1)
    ) master_i (
        .OQ       (serial_data),
        .CLK      (serial_clk),
        .CLKDIV   (pixel_clk),
        .D1       (parallel_data[0]),
        .D2       (parallel_data[1]),
        .D3       (parallel_data[2]),
        .D4       (parallel_data[3]),
        .D5       (parallel_data[4]),
        .D6       (parallel_data[5]),
        .D7       (parallel_data[6]),
        .D8       (parallel_data[7]),
        .OCE      (1'b1),
        .RST      (reset),
        .SHIFTIN1 (shift1),
        .SHIFTIN2 (shift2),
        .T1       (1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .TBYTEIN  (1'b0), .TCE(1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .SERDES_MODE("SLAVE"),
        .TRISTATE_WIDTH(1)
    ) slave_i (
        .CLK       (serial_clk),
        .CLKDIV    (pixel_clk),
        .D1        (1'b0),
        .D2        (1'b0),
        .D3        (parallel_data[8]),
        .D4        (parallel_data[9]),
        .D5        (1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
        .OCE       (1'b1),
        .RST       (reset),
        .SHIFTOUT1 (shift1),
        .SHIFTOUT2 (shift2),
        .SHIFTIN1  (1'b0),
        .SHIFTIN2  (1'b0),
        .T1        (1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0),
        .TBYTEIN   (1'b0), .TCE(1'b0)
    );
endmodule

`default_nettype wire
