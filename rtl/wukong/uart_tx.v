`default_nettype none

// Minimal 8-N-1 transmitter for the Wukong diagnostic console.
module uart_tx #(
    parameter integer CLKS_PER_BIT = 219
) (
    input  wire       clock,
    input  wire       reset,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output reg        busy
);
    reg [15:0] clock_count;
    reg [3:0] bit_index;
    reg [9:0] shift;

    always @(posedge clock) begin
        if (reset) begin
            tx <= 1'b1;
            busy <= 1'b0;
            clock_count <= 16'd0;
            bit_index <= 4'd0;
            shift <= 10'h3ff;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                shift <= {1'b1, data, 1'b0};
                tx <= 1'b0;
                busy <= 1'b1;
                clock_count <= 16'd0;
                bit_index <= 4'd0;
            end
        end else if (clock_count == CLKS_PER_BIT - 1) begin
            clock_count <= 16'd0;
            if (bit_index == 4'd9) begin
                tx <= 1'b1;
                busy <= 1'b0;
            end else begin
                bit_index <= bit_index + 1'b1;
                shift <= {1'b1, shift[9:1]};
                tx <= shift[1];
            end
        end else begin
            clock_count <= clock_count + 1'b1;
        end
    end
endmodule

`default_nettype wire
