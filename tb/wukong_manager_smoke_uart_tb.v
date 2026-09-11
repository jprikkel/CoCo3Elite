`timescale 1ns/1ps
`default_nettype none

module wukong_manager_smoke_uart_tb;
    reg clock = 1'b0;
    wire uart_tx;
    integer index;
    reg [7:0] received;

    wukong_manager_smoke_top #(.UART_CLKS_PER_BIT(2)) dut (
        .clk_50mhz(clock), .uart_tx(uart_tx)
    );

    always #10 clock = ~clock;

    function [7:0] expected_byte;
        input integer character_index;
        begin
            case (character_index)
                0: expected_byte = "R";
                1: expected_byte = "V";
                2: expected_byte = "3";
                3: expected_byte = "2";
                4: expected_byte = " ";
                5: expected_byte = "O";
                6: expected_byte = "K";
                7: expected_byte = 8'h0d;
                default: expected_byte = 8'h0a;
            endcase
        end
    endfunction

    task receive_uart_byte;
        integer bit_index;
        begin
            @(negedge uart_tx);
            repeat (3) @(posedge clock); // center of first data bit
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                received[bit_index] = uart_tx;
                repeat (2) @(posedge clock);
            end
            // The loop stops at the center of data bit 7. Advance through
            // the remaining half-bit to the center of the stop bit before
            // accepting the next falling edge as another start bit.
            repeat (2) @(posedge clock);
            if (uart_tx !== 1'b1) begin
                $display("FAIL: UART stop bit was low at character %0d", index);
                $finish;
            end
        end
    endtask

    initial begin
        for (index = 0; index < 9; index = index + 1) begin
            receive_uart_byte;
            if (received !== expected_byte(index)) begin
                $display("FAIL: UART character %0d was %02x, expected %02x",
                         index, received, expected_byte(index));
                $finish;
            end
        end
        $display("PASS: Wukong manager smoke UART emitted RV32 OK banner");
        #40 $finish;
    end

    initial begin
        #50000;
        $display("FAIL: Wukong manager smoke UART timeout");
        $finish;
    end
endmodule

`default_nettype wire
