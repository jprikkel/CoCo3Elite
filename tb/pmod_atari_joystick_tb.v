`timescale 1ns/1ps

module pmod_atari_joystick_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg [5:0] contacts_n = 6'b111111;
    wire up, down, left, right, button1, button2;

    always #5 clock = !clock;

    pmod_atari_joystick dut (
        .clock(clock), .reset(reset),
        .up_n(contacts_n[0]), .down_n(contacts_n[1]),
        .left_n(contacts_n[2]), .right_n(contacts_n[3]),
        .button1_n(contacts_n[4]), .button2_n(contacts_n[5]),
        .up(up), .down(down), .left(left), .right(right),
        .button1(button1), .button2(button2)
    );

    task settle;
        begin
            repeat (3) @(posedge clock);
            #1;
        end
    endtask

    initial begin
        settle;
        reset = 1'b0;
        settle;
        if ({button2,button1,right,left,down,up} !== 6'b000000) begin
            $display("FAIL: idle contacts are not released");
            $fatal;
        end

        contacts_n = 6'b101010;
        settle;
        if ({button2,button1,right,left,down,up} !== 6'b010101) begin
            $display("FAIL: active-low contacts were not synchronized");
            $fatal;
        end

        contacts_n = 6'b010101;
        settle;
        if ({button2,button1,right,left,down,up} !== 6'b101010) begin
            $display("FAIL: button 2 or direction mapping is incorrect");
            $fatal;
        end

        reset = 1'b1;
        @(posedge clock); #1;
        if ({button2,button1,right,left,down,up} !== 6'b000000) begin
            $display("FAIL: reset did not release all contacts");
            $fatal;
        end

        $display("PASS: J10 Atari joystick inputs and second button");
        $finish;
    end
endmodule
