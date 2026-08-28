`timescale 1ns/1ps

module sd_spi_init_tb;
    reg clock = 0;
    reg reset = 1;
    reg miso = 1;
    wire cs_n, sck, mosi;
    wire [7:0] status, detail;
    reg [7:0] observed = 0;
    integer bit_index = 0;
    integer byte_index = 0;

    sd_spi_init #(.HALF_PERIOD(2)) dut (
        .clock(clock), .reset(reset), .miso(miso),
        .cs_n(cs_n), .sck(sck), .mosi(mosi),
        .status(status), .detail(detail)
    );

    always #5 clock = ~clock;

    always @(posedge sck) begin
        observed = {observed[6:0], mosi};
        if (bit_index == 7) begin
            if (byte_index < 10 && observed !== 8'hff) begin
                $display("FAIL: startup byte %0d was %02x", byte_index, observed);
                $finish;
            end
            if (byte_index == 10 && observed !== 8'h40) begin
                $display("FAIL: CMD0 command byte was %02x", observed); $finish;
            end
            if (byte_index >= 11 && byte_index <= 14 && observed !== 8'h00) begin
                $display("FAIL: CMD0 argument byte %0d was %02x", byte_index-11, observed); $finish;
            end
            if (byte_index == 15) begin
                if (observed !== 8'h95) begin
                    $display("FAIL: CMD0 CRC byte was %02x", observed); $finish;
                end
                $display("PASS: startup clocks and CMD0 bytes are correct");
                $finish;
            end
            bit_index = 0;
            byte_index = byte_index + 1;
        end else begin
            bit_index = bit_index + 1;
        end
    end

    initial begin
        #40 reset = 0;
        #20000 $display("FAIL: timeout");
        $finish;
    end
endmodule
