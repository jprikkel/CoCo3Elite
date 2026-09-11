`timescale 1ns/1ps
`default_nettype none

// A card model sufficient for the diagnostic CMD17 transaction.  It first
// returns a valid sector-zero boot signature, then behaves as a removed card
// (MISO held high) when the reader performs its periodic re-probe.
module sd_spi_read_sector0_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b0;
    reg card_present = 1'b1;
    reg miso = 1'b1;
    wire cs_n, sck, mosi;
    wire [7:0] status, detail;
    integer response_index = 0;
    integer response_bit = 0;
    integer command_index = 0;
    integer transaction_count = 0;
    reg [7:0] observed = 8'h00;
    reg [7:0] current_response = 8'hff;
    integer observed_bits = 0;

    sd_spi_read_sector0 #(.HALF_PERIOD(2), .RETRY_CYCLES(3)) dut (
        .clock(clock), .reset(reset), .enable(enable), .miso(miso),
        .cs_n(cs_n), .sck(sck), .mosi(mosi),
        .status(status), .detail(detail)
    );

    always #5 clock = ~clock;

    function [7:0] response_byte;
        input integer index;
        begin
            if (!card_present) begin
                response_byte = 8'hff;
            end else if (index < 6) begin
                response_byte = 8'hff;       // CMD17 command bytes
            end else if (index == 6) begin
                response_byte = 8'h00;       // R1 accepted
            end else if (index == 7) begin
                response_byte = 8'hfe;       // data token
            end else if (index == 518) begin
                response_byte = 8'h55;       // sector byte 510
            end else if (index == 519) begin
                response_byte = 8'haa;       // sector byte 511
            end else begin
                response_byte = 8'h00;       // data and ignored CRC
            end
        end
    endfunction

    always @(negedge cs_n) begin
        response_index = 0;
        response_bit = 0;
        command_index = 0;
        observed = 8'h00;
        observed_bits = 0;
        transaction_count = transaction_count + 1;
        current_response = response_byte(0);
        miso = current_response[7];
    end

    // The controller samples MISO on SCK's rising edge, so present each
    // following card bit on the preceding falling edge.
    always @(negedge sck) begin
        if (!cs_n) begin
            if (response_bit == 7) begin
                response_index = response_index + 1;
                response_bit = 0;
                current_response = response_byte(response_index);
                miso = current_response[7];
            end else begin
                response_bit = response_bit + 1;
                current_response = response_byte(response_index);
                miso = current_response[7-response_bit];
            end
        end
    end

    always @(posedge sck) begin
        if (!cs_n && transaction_count == 1) begin
            observed = {observed[6:0], mosi};
            if (observed_bits == 7) begin
                case (command_index)
                    0: if (observed !== 8'h51) begin
                        $display("FAIL: CMD17 byte 0 was %02x", observed); $finish;
                    end
                    1, 2, 3, 4: if (observed !== 8'h00) begin
                        $display("FAIL: CMD17 argument byte %0d was %02x", command_index, observed); $finish;
                    end
                    5: if (observed !== 8'h01) begin
                        $display("FAIL: CMD17 CRC was %02x", observed); $finish;
                    end
                    default: begin end
                endcase
                command_index = command_index + 1;
                observed_bits = 0;
            end else begin
                observed_bits = observed_bits + 1;
            end
        end
    end

    initial begin
        #40 reset = 1'b0;
        enable = 1'b1;
        wait (status == 8'h81);
        if (detail !== 8'h00) begin
            $display("FAIL: valid-sector detail was %02x", detail); $finish;
        end
        if (command_index < 6) begin
            $display("FAIL: CMD17 bytes were not observed"); $finish;
        end
        card_present = 1'b0;
        wait (status == 8'he2);
        if (transaction_count < 2) begin
            $display("FAIL: reader did not re-probe after success"); $finish;
        end
        $display("PASS: CMD17 boot probe succeeds, repeats, and detects removal");
        #10 $finish;
    end

    initial begin
        #500000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

`default_nettype wire
