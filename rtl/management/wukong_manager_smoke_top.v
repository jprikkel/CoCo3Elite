`default_nettype none

// Standalone Wukong image for the first UltraEmbedded manager test. It uses
// only the board oscillator and CH340N FPGA-to-PC UART pin; it does not drive
// HDMI, SD, PS/2, or any CoCo hardware.
module wukong_manager_smoke_top #(
    parameter integer UART_CLKS_PER_BIT = 434
) (
    input  wire clk_50mhz,
    output wire uart_tx
);
    reg [7:0] startup_count = 8'd0;
    wire reset = !(&startup_count);
    wire boot_done;
    wire magic_seen;
    wire [31:0] magic_value;
    reg [3:0] banner_index;
    reg banner_done;
    reg [7:0] uart_data;
    reg uart_start;
    wire uart_busy;

    always @(posedge clk_50mhz) begin
        if (!(&startup_count))
            startup_count <= startup_count + 1'b1;
    end

    ultraembedded_manager_smoke manager_i (
        .clock(clk_50mhz), .reset(reset), .boot_done(boot_done),
        .magic_seen(magic_seen), .magic_value(magic_value)
    );

    function [7:0] banner_byte;
        input [3:0] index;
        begin
            case (index)
                0: banner_byte = "R";
                1: banner_byte = "V";
                2: banner_byte = "3";
                3: banner_byte = "2";
                4: banner_byte = " ";
                5: banner_byte = "O";
                6: banner_byte = "K";
                7: banner_byte = 8'h0d;
                default: banner_byte = 8'h0a;
            endcase
        end
    endfunction

    always @(posedge clk_50mhz) begin
        if (reset) begin
            banner_index <= 0;
            banner_done <= 1'b0;
            uart_data <= 0;
            uart_start <= 1'b0;
        end else begin
            uart_start <= 1'b0;
            // uart_tx raises busy on the clock after it observes start. Also
            // gate on the previous start pulse so this controller cannot
            // launch a second character during that one-cycle latency.
            if (magic_seen && !banner_done && !uart_busy && !uart_start) begin
                uart_data <= banner_byte(banner_index);
                uart_start <= 1'b1;
                if (banner_index == 8)
                    banner_done <= 1'b1;
                else
                    banner_index <= banner_index + 1'b1;
            end
        end
    end

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_i (
        .clock(clk_50mhz), .reset(reset), .data(uart_data),
        .start(uart_start), .tx(uart_tx), .busy(uart_busy)
    );

    wire _unused = boot_done & magic_value[0];
endmodule

`default_nettype wire
