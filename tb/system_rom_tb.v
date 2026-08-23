`timescale 1ns/1ps
`default_nettype none

module system_rom_tb;
    reg         clock = 1'b0;
    reg  [14:0] address = 15'h0000;
    wire [7:0]  data;

    always #5 clock = ~clock;

    coco3_system_rom dut (
        .clock   (clock),
        .address (address),
        .data    (data)
    );

    task expect_byte;
        input [14:0] test_address;
        input [7:0] expected;
        begin
            address = test_address;
            @(posedge clock);
            #1;
            if (data !== expected) begin
                $display("FAIL: ROM[%04h] expected %02h, got %02h",
                         test_address + 16'h8000, expected, data);
                $finish;
            end
        end
    endtask

    initial begin
        // CoCo 3 reset vectors are supplied by the reconstructed vector page.
        expect_byte(15'h7FFE, 8'h8C);
        expect_byte(15'h7FFF, 8'h1B);

        // The reset target must contain executable code, not an empty byte.
        address = 15'h0C1B;
        @(posedge clock);
        #1;
        if (data === 8'h00 || data === 8'hFF || (^data) === 1'bx) begin
            $display("FAIL: reset target $8C1B is not populated: %02h", data);
            $finish;
        end

        $display("PASS: system ROM reset vector $8C1B and reset target are valid");
        $finish;
    end
endmodule

`default_nettype wire
