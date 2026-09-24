`timescale 1ns/1ps
module uart_rx_tb;
    reg clock = 0;
    reg reset = 1;
    reg rx = 1;
    wire [7:0] data;
    wire valid, framing_error;
    integer valid_count = 0;

    always #5 clock = ~clock;
    uart_rx #(.CLKS_PER_BIT(10)) dut(
        .clock(clock), .reset(reset), .clks_per_bit(16'd10),
        .rx(rx), .data(data),
        .data_valid(valid), .framing_error(framing_error));

    task send_byte(input [7:0] value, input good_stop);
        integer bit_number;
        begin
            rx = 0; repeat (10) @(posedge clock);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                rx = value[bit_number]; repeat (10) @(posedge clock);
            end
            rx = good_stop; repeat (10) @(posedge clock);
            rx = 1; repeat (12) @(posedge clock);
        end
    endtask

    always @(posedge clock) begin
        if (valid) begin
            valid_count = valid_count + 1;
            if (data !== 8'hA5) $fatal(1, "wrong UART byte %02x", data);
        end
    end

    initial begin
        repeat (4) @(posedge clock); reset = 0;
        repeat (4) @(posedge clock);
        send_byte(8'hA5, 1'b1);
        if (valid_count != 1) $fatal(1, "valid byte not received");
        send_byte(8'h3C, 1'b0);
        if (valid_count != 1) $fatal(1, "bad stop bit was accepted");
        $display("PASS: UART RX data and framing");
        $finish;
    end
endmodule
