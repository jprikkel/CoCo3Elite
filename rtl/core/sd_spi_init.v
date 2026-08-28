`timescale 1ns/1ps
`default_nettype none

// Read-only SD-card SPI-mode initializer.  Status is exposed at $FF60 and the
// most recent R1 response at $FF61.  SPI remains at initialization speed; the
// FAT32 reader will raise the clock after this checkpoint is proven.
module sd_spi_init #(
    parameter HALF_PERIOD = 7'd64
) (
    input  wire       clock,
    input  wire       reset,
    input  wire       miso,
    output reg        cs_n,
    output reg        sck,
    output reg        mosi,
    output reg [7:0]  status,
    output reg [7:0]  detail
);
    localparam ST_CLOCKS = 4'd0, ST_CMD0 = 4'd1, ST_CMD8 = 4'd2,
               ST_CMD55 = 4'd3, ST_ACMD41 = 4'd4, ST_CMD58 = 4'd5,
               ST_CMD58_OCR = 4'd6, ST_READY = 4'd7, ST_ERROR = 4'd8;
    reg [3:0] state;
    reg [3:0] byte_number;
    reg [4:0] response_tries;
    reg [3:0] idle_bytes;
    reg [7:0] tx_byte;
    reg [7:0] rx_byte;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [6:0] divider;
    reg [3:0] bit_count;
    reg transfer;
    reg start_byte;
    reg byte_done;
    reg [15:0] acmd_tries;

    function [7:0] command_byte;
        input [3:0] command_state;
        input [2:0] index;
        begin
            case (index)
                0: case (command_state)
                    ST_CMD0: command_byte = 8'h40;
                    ST_CMD8: command_byte = 8'h48;
                    ST_CMD55: command_byte = 8'h77;
                    ST_ACMD41: command_byte = 8'h69;
                    default: command_byte = 8'h7A;
                endcase
                1: command_byte = (command_state == ST_ACMD41) ? 8'h40 : 8'h00;
                2,3: command_byte = 8'h00;
                4: command_byte = (command_state == ST_CMD8) ? 8'h01 : 8'h00;
                default: command_byte = (command_state == ST_CMD0) ? 8'h95 :
                                        (command_state == ST_CMD8) ? 8'h87 : 8'h01;
            endcase
        end
    endfunction

    always @(posedge clock) begin
        byte_done <= 1'b0;
        if (reset) begin
            sck <= 1'b0; mosi <= 1'b1; divider <= 0; bit_count <= 0;
            transfer <= 1'b0; rx_byte <= 8'hFF;
            tx_shift <= 8'hFF; rx_shift <= 8'h00;
        end else if (start_byte && !transfer) begin
            transfer <= 1'b1; divider <= 0; bit_count <= 0;
            tx_shift <= tx_byte; rx_shift <= 8'h00;
            sck <= 1'b0; mosi <= tx_byte[7];
        end else if (transfer) begin
            if (divider == HALF_PERIOD-1) begin
                divider <= 0;
                if (!sck) begin
                    sck <= 1'b1;
                    rx_shift <= {rx_shift[6:0], miso};
                end else begin
                    sck <= 1'b0;
                    if (bit_count == 7) begin
                        transfer <= 1'b0; rx_byte <= rx_shift;
                        byte_done <= 1'b1; mosi <= 1'b1;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        tx_shift <= {tx_shift[6:0], 1'b1};
                        mosi <= tx_shift[6];
                    end
                end
            end else divider <= divider + 1'b1;
        end
    end

    always @(posedge clock) begin
        start_byte <= 1'b0;
        if (reset) begin
            state <= ST_CLOCKS; status <= 8'h01; detail <= 8'hFF;
            cs_n <= 1'b1; idle_bytes <= 0; byte_number <= 0;
            response_tries <= 0; acmd_tries <= 0; tx_byte <= 8'hFF;
        end else if (!transfer && !start_byte) begin
            if (state == ST_CLOCKS) begin
                if (idle_bytes == 10) begin
                    state <= ST_CMD0; status <= 8'h02; byte_number <= 0;
                    response_tries <= 0; cs_n <= 1'b0;
                end else begin
                    tx_byte <= 8'hFF; start_byte <= 1'b1;
                    idle_bytes <= idle_bytes + 1'b1;
                end
            end else if (state < ST_READY) begin
                if (state == ST_CMD58_OCR) begin
                    // CMD58 returns four OCR bytes after R1. Clock all four
                    // out before releasing CS and handing SPI to CMD17.
                    if (byte_number < 4) begin
                        tx_byte <= 8'hFF;
                        start_byte <= 1'b1;
                        byte_number <= byte_number + 1'b1;
                    end else if (byte_done) begin
                        state <= ST_READY;
                        status <= 8'h80;
                        detail <= 8'h00;
                        cs_n <= 1'b1;
                    end
                end else if (byte_number < 6) begin
                    tx_byte <= command_byte(state, byte_number[2:0]);
                    start_byte <= 1'b1; byte_number <= byte_number + 1'b1;
                end else if (byte_done && rx_byte[7] == 1'b0) begin
                    detail <= rx_byte;
                    if (state == ST_CMD0 && rx_byte == 8'h01) begin
                        // ACMD41 with HCS works for the SDHC/SDXC cards used
                        // by this project. CMD8/R7 parsing is added with FAT32.
                        state <= ST_CMD55; status <= 8'h04;
                    end else if (state == ST_CMD55 && rx_byte <= 8'h01) begin
                        state <= ST_ACMD41; status <= 8'h05;
                    end else if (state == ST_ACMD41 && rx_byte == 8'h00) begin
                        state <= ST_CMD58; status <= 8'h06;
                    end else if (state == ST_ACMD41 && rx_byte == 8'h01 && acmd_tries != 16'hFFFF) begin
                        state <= ST_CMD55; acmd_tries <= acmd_tries + 1'b1;
                    end else if (state == ST_CMD58 && rx_byte == 8'h00) begin
                        state <= ST_CMD58_OCR;
                        byte_number <= 0;
                    end else begin
                        state <= ST_ERROR; status <= 8'hE1; cs_n <= 1'b1;
                    end
                    byte_number <= 0; response_tries <= 0;
                end else if (response_tries == 31) begin
                    state <= ST_ERROR; status <= 8'hE2; detail <= rx_byte;
                    cs_n <= 1'b1;
                end else begin
                    tx_byte <= 8'hFF; start_byte <= 1'b1;
                    response_tries <= response_tries + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
