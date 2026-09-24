`timescale 1ns/1ps
`default_nettype none

// Small 8-N-1 receiver for the onboard CH340N.  The input is synchronized
// before the start bit is qualified; data_valid pulses for one clock after a
// complete byte with a valid stop bit.  Framing errors are reported separately
// so the management firmware can discard a damaged command.
module uart_rx #(
    parameter integer CLKS_PER_BIT = 55
) (
    input  wire       clock,
    input  wire       reset,
    input  wire [15:0] clks_per_bit,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        data_valid,
    output reg        framing_error
);
    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0] rx_sync;
    reg [1:0] state;
    reg [15:0] clock_count;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clock) begin
        rx_sync <= {rx_sync[0], rx};
        data_valid <= 1'b0;
        framing_error <= 1'b0;

        if (reset) begin
            rx_sync <= 2'b11;
            state <= IDLE;
            clock_count <= 0;
            bit_index <= 0;
            shift <= 0;
            data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    clock_count <= 0;
                    bit_index <= 0;
                    if (!rx_sync[1]) state <= START;
                end
                START: begin
                    if (clock_count == (clks_per_bit >> 1) - 1'b1) begin
                        clock_count <= 0;
                        // Reject a short low-going glitch before receiving.
                        state <= rx_sync[1] ? IDLE : DATA;
                    end else clock_count <= clock_count + 1'b1;
                end
                DATA: begin
                    if (clock_count == clks_per_bit - 1'b1) begin
                        clock_count <= 0;
                        shift[bit_index] <= rx_sync[1];
                        if (bit_index == 3'd7) state <= STOP;
                        else bit_index <= bit_index + 1'b1;
                    end else clock_count <= clock_count + 1'b1;
                end
                STOP: begin
                    if (clock_count == clks_per_bit - 1'b1) begin
                        clock_count <= 0;
                        state <= IDLE;
                        if (rx_sync[1]) begin
                            data <= shift;
                            data_valid <= 1'b1;
                        end else framing_error <= 1'b1;
                    end else clock_count <= clock_count + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
