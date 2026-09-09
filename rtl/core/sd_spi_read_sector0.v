`timescale 1ns/1ps
`default_nettype none

// First post-initialization storage checkpoint. Reads SDHC logical sector 0
// with CMD17 and validates its 55 AA signature. The FAT32 mount state machine
// will reuse this byte engine once physical block reads are proven on J13.
module sd_spi_read_sector0 #(
    parameter HALF_PERIOD = 7'd8,
    // With no card-detect signal on the Pmod, periodically repeat this
    // harmless read-only probe.  At the 25.2 MHz pixel clock the default is
    // one second between probes; a failed command is reported to the boot
    // supervisor, which restarts card initialization.
    parameter [24:0] RETRY_CYCLES = 25'd25200000
) (
    input  wire      clock,
    input  wire      reset,
    input  wire      enable,
    input  wire      miso,
    output reg       cs_n,
    output reg       sck,
    output reg       mosi,
    output reg [7:0] status,
    output reg [7:0] detail
);
    localparam ST_IDLE = 4'd0, ST_GAP = 4'd1, ST_COMMAND = 4'd2,
               ST_RESPONSE = 4'd3, ST_TOKEN = 4'd4, ST_DATA = 4'd5,
               ST_CRC = 4'd6, ST_DONE = 4'd7, ST_ERROR = 4'd8;

    reg [3:0] state;
    reg [2:0] command_index;
    reg [7:0] response_tries;
    reg [11:0] token_tries;
    reg [8:0] data_index;
    reg crc_index;
    reg [7:0] signature_lo;
    reg [7:0] signature_hi;
    reg [24:0] retry_count;

    reg [7:0] tx_byte;
    reg [7:0] rx_byte;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [6:0] divider;
    reg [3:0] bit_count;
    reg transfer;
    reg start_byte;
    reg byte_done;

    function [7:0] cmd17_byte;
        input [2:0] index;
        begin
            case (index)
                0: cmd17_byte = 8'h51;
                1, 2, 3, 4: cmd17_byte = 8'h00;
                default: cmd17_byte = 8'h01;
            endcase
        end
    endfunction

    always @(posedge clock) begin
        byte_done <= 1'b0;
        if (reset) begin
            sck <= 1'b0;
            mosi <= 1'b1;
            divider <= 0;
            bit_count <= 0;
            transfer <= 1'b0;
            rx_byte <= 8'hff;
            tx_shift <= 8'hff;
            rx_shift <= 8'h00;
        end else if (start_byte && !transfer) begin
            transfer <= 1'b1;
            divider <= 0;
            bit_count <= 0;
            tx_shift <= tx_byte;
            rx_shift <= 8'h00;
            sck <= 1'b0;
            mosi <= tx_byte[7];
        end else if (transfer) begin
            if (divider == HALF_PERIOD-1) begin
                divider <= 0;
                if (!sck) begin
                    sck <= 1'b1;
                    rx_shift <= {rx_shift[6:0], miso};
                end else begin
                    sck <= 1'b0;
                    if (bit_count == 7) begin
                        transfer <= 1'b0;
                        rx_byte <= rx_shift;
                        byte_done <= 1'b1;
                        mosi <= 1'b1;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        tx_shift <= {tx_shift[6:0], 1'b1};
                        mosi <= tx_shift[6];
                    end
                end
            end else begin
                divider <= divider + 1'b1;
            end
        end
    end

    always @(posedge clock) begin
        start_byte <= 1'b0;
        if (reset) begin
            state <= ST_IDLE;
            cs_n <= 1'b1;
            status <= 8'h00;
            detail <= 8'hff;
            command_index <= 0;
            response_tries <= 0;
            token_tries <= 0;
            data_index <= 0;
            crc_index <= 0;
            signature_lo <= 0;
            signature_hi <= 0;
            retry_count <= 0;
            tx_byte <= 8'hff;
        end else if (!transfer && !start_byte) begin
            case (state)
                ST_IDLE: if (enable) begin
                    status <= 8'h10;
                    detail <= 8'hff;
                    retry_count <= 0;
                    cs_n <= 1'b1;
                    tx_byte <= 8'hff;
                    start_byte <= 1'b1;
                    state <= ST_GAP;
                end
                ST_GAP: if (byte_done) begin
                    cs_n <= 1'b0;
                    command_index <= 0;
                    state <= ST_COMMAND;
                end
                ST_COMMAND: begin
                    if (command_index < 6) begin
                        tx_byte <= cmd17_byte(command_index);
                        start_byte <= 1'b1;
                        command_index <= command_index + 1'b1;
                    end else begin
                        response_tries <= 0;
                        state <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: if (byte_done && rx_byte[7] == 1'b0) begin
                    detail <= rx_byte;
                    if (rx_byte == 8'h00) begin
                        token_tries <= 0;
                        tx_byte <= 8'hff;
                        start_byte <= 1'b1;
                        state <= ST_TOKEN;
                    end else begin
                        status <= 8'he3;
                        cs_n <= 1'b1;
                        state <= ST_ERROR;
                    end
                end else if (response_tries == 8'hff) begin
                    status <= 8'he2;
                    cs_n <= 1'b1;
                    state <= ST_ERROR;
                end else begin
                    tx_byte <= 8'hff;
                    start_byte <= 1'b1;
                    response_tries <= response_tries + 1'b1;
                end
                ST_TOKEN: if (byte_done && rx_byte == 8'hfe) begin
                    data_index <= 0;
                    tx_byte <= 8'hff;
                    start_byte <= 1'b1;
                    state <= ST_DATA;
                end else if (token_tries == 12'hfff) begin
                    status <= 8'he4;
                    detail <= rx_byte;
                    cs_n <= 1'b1;
                    state <= ST_ERROR;
                end else begin
                    tx_byte <= 8'hff;
                    start_byte <= 1'b1;
                    token_tries <= token_tries + 1'b1;
                end
                ST_DATA: if (byte_done) begin
                    if (data_index == 9'd510) signature_lo <= rx_byte;
                    if (data_index == 9'd511) begin
                        signature_hi <= rx_byte;
                        crc_index <= 0;
                        tx_byte <= 8'hff;
                        start_byte <= 1'b1;
                        state <= ST_CRC;
                    end else begin
                        data_index <= data_index + 1'b1;
                        tx_byte <= 8'hff;
                        start_byte <= 1'b1;
                    end
                end
                ST_CRC: if (byte_done) begin
                    if (!crc_index) begin
                        crc_index <= 1'b1;
                        tx_byte <= 8'hff;
                        start_byte <= 1'b1;
                    end else begin
                        cs_n <= 1'b1;
                        if (signature_lo == 8'h55 && signature_hi == 8'haa) begin
                            status <= 8'h81;
                            detail <= 8'h00;
                            state <= ST_DONE;
                        end else begin
                            status <= 8'he5;
                            detail <= signature_hi;
                            state <= ST_ERROR;
                        end
                    end
                end
                ST_DONE: if (!enable) begin
                    state <= ST_IDLE;
                    retry_count <= 0;
                end else if (retry_count == RETRY_CYCLES - 1'b1) begin
                    // Repeat CMD17 rather than treating a former success as
                    // a permanent card-present indication.
                    retry_count <= 0;
                    state <= ST_IDLE;
                end else begin
                    retry_count <= retry_count + 1'b1;
                end
                default: begin end
            endcase
        end
    end
endmodule

`default_nettype wire
