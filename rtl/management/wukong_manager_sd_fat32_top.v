`timescale 1ns/1ps
`default_nettype none
module wukong_manager_sd_fat32_top (
    input wire clk_50mhz, output wire uart_tx, output wire sd_cs_n,
    output wire sd_sck, output wire sd_mosi, input wire sd_miso
);
    reg [7:0] startup_count = 0;
    wire reset = !(&startup_count);
    always @(posedge clk_50mhz) if (!(&startup_count)) startup_count <= startup_count + 1'b1;
    ultraembedded_manager_sd_fat32 manager_i (
        .clock(clk_50mhz), .reset(reset), .uart_tx(uart_tx), .sd_cs_n(sd_cs_n),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );
endmodule
`default_nettype wire
