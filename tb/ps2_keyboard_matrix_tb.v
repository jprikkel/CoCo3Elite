`timescale 1ns/1ps
`default_nettype none

module ps2_keyboard_matrix_tb;
    reg system_clock = 0;
    reg slow_clock = 0;
    reg reset_n = 0;
    reg ps2_clk = 1;
    reg ps2_data = 1;
    reg [7:0] columns = 8'hFF;
    wire [55:0] keys;
    wire forced_shift;
    wire shift_override;
    wire keyboard_reset;
    wire keyboard_f12;
    wire [7:0] rows;
    integer parity;

    always #20 system_clock = ~system_clock;
    always #80 slow_clock = ~slow_clock;

    COCOKEY keyboard_i (
        .RESET_N(reset_n), .CLK50MHZ(system_clock), .SLO_CLK(slow_clock),
        .PS2_CLK(ps2_clk), .PS2_DATA(ps2_data), .KEY(keys),
        .SHIFT(forced_shift), .SHIFT_OVERRIDE(shift_override),
        .F12(keyboard_f12),
        .RESET(keyboard_reset)
    );

    coco3_keyboard_matrix matrix_i (
        .keys(keys), .forced_shift(forced_shift),
        .shift_override(shift_override), .columns(columns), .rows(rows)
    );

    task send_bit;
        input value;
        begin
            ps2_data = value;
            #4000 ps2_clk = 0;
            #4000 ps2_clk = 1;
            #4000;
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer bit_number;
        begin
            parity = ~^value;
            send_bit(0);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                send_bit(value[bit_number]);
            send_bit(parity[0]);
            send_bit(1);
            ps2_data = 1;
            ps2_clk = 1;
            #20000;
        end
    endtask

    initial begin
        #1000 reset_n = 1;
        repeat (80) @(negedge slow_clock);

        // Set-2 scan code 1C is the A key: matrix row 0, column 1.
        send_byte(8'h1C);
        #20000;
        if (!keys[1]) begin
            $display("FAIL: A key press was not decoded");
            $finish;
        end
        columns = 8'hFD;
        #1000;
        if (rows[0] !== 1'b0) begin
            $display("FAIL: A key did not pull matrix row 0 low");
            $finish;
        end

        send_byte(8'hF0);
        send_byte(8'h1C);
        #20000;
        if (keys[1] || rows[0] !== 1'b1) begin
            $display("FAIL: A key release was not decoded");
            $finish;
        end

        // F12 is reserved for the management UI and must not leak an @ key
        // into the CoCo matrix.
        send_byte(8'h07);
        #20000;
        if (!keyboard_f12 || keys[0]) begin
            $display("FAIL: F12 was not isolated as the management hotkey");
            $finish;
        end
        send_byte(8'hF0);
        send_byte(8'h07);
        #20000;
        if (keyboard_f12) begin
            $display("FAIL: F12 release was not decoded");
            $finish;
        end

        $display("PASS: PS/2 matrix scan and isolated F12 management hotkey");
        $finish;
    end
endmodule

`default_nettype wire
