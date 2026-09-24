`timescale 1ns/1ps

module floppy_mfm_track_decoder_tb;
    reg clock = 0;
    reg reset = 1;
    reg start = 0;
    reg sample_valid = 0;
    reg [7:0] sample_interval = 0;
    reg sample_last = 0;
    reg [12:0] cache_read_address = 0;
    wire sample_ready;
    wire [7:0] cache_read_data;
    wire busy, done, success;
    wire [7:0] decoded_track;
    wire decoded_side;
    wire [17:0] sector_valid;
    wire [7:0] id_crc_errors, data_crc_errors;

    integer slots_since_transition = 0;
    reg previous_data = 0;
    integer index;
    reg [15:0] id_crc, data_crc;

    always #5 clock = !clock;

    floppy_mfm_track_decoder dut (
        .clock(clock), .reset(reset), .start(start),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_interval(sample_interval), .sample_last(sample_last),
        .cache_read_address(cache_read_address),
        .cache_read_data(cache_read_data), .busy(busy), .done(done),
        .success(success), .decoded_track(decoded_track),
        .decoded_side(decoded_side), .sector_valid(sector_valid),
        .id_crc_errors(id_crc_errors), .data_crc_errors(data_crc_errors)
    );

    function [15:0] crc16_byte;
        input [15:0] current;
        input [7:0] value;
        integer bit_number;
        reg [15:0] next_crc;
        begin
            next_crc = current ^ {value, 8'h00};
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                next_crc = next_crc[15]
                    ? (next_crc << 1) ^ 16'h1021 : next_crc << 1;
            crc16_byte = next_crc;
        end
    endfunction

    task send_interval;
        input [7:0] value;
        input final_sample;
        begin
            while (!sample_ready) @(posedge clock);
            sample_interval = value;
            sample_last = final_sample;
            sample_valid = 1;
            @(posedge clock);
            sample_valid = 0;
            sample_last = 0;
        end
    endtask

    task emit_raw_bit;
        input value;
        begin
            slots_since_transition = slots_since_transition + 1;
            if (value) begin
                send_interval(slots_since_transition * 25, 0);
                slots_since_transition = 0;
            end
        end
    endtask

    task emit_raw_word;
        input [15:0] value;
        integer bit_number;
        begin
            for (bit_number = 15; bit_number >= 0; bit_number = bit_number - 1)
                emit_raw_bit(value[bit_number]);
            previous_data = value[0];
        end
    endtask

    task emit_mfm_byte;
        input [7:0] value;
        integer bit_number;
        reg data_bit;
        reg clock_bit;
        begin
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                data_bit = value[bit_number];
                clock_bit = !(previous_data || data_bit);
                emit_raw_bit(clock_bit);
                emit_raw_bit(data_bit);
                previous_data = data_bit;
            end
        end
    endtask

    task emit_sync;
        begin
            emit_raw_word(16'h4489);
            emit_raw_word(16'h4489);
            emit_raw_word(16'h4489);
        end
    endtask

    task emit_gap;
        input integer count;
        integer byte_number;
        begin
            for (byte_number = 0; byte_number < count; byte_number = byte_number + 1)
                emit_mfm_byte(8'h4e);
        end
    endtask

    initial begin
        repeat (4) @(posedge clock);
        reset = 0;
        start = 1;
        @(posedge clock);
        start = 0;

        emit_gap(12);
        emit_sync;
        id_crc = 16'hffff;
        id_crc = crc16_byte(id_crc, 8'ha1);
        id_crc = crc16_byte(id_crc, 8'ha1);
        id_crc = crc16_byte(id_crc, 8'ha1);
        id_crc = crc16_byte(id_crc, 8'hfe);
        emit_mfm_byte(8'hfe);
        id_crc = crc16_byte(id_crc, 8'd17); emit_mfm_byte(8'd17);
        id_crc = crc16_byte(id_crc, 8'd0);  emit_mfm_byte(8'd0);
        id_crc = crc16_byte(id_crc, 8'd3);  emit_mfm_byte(8'd3);
        id_crc = crc16_byte(id_crc, 8'd1);  emit_mfm_byte(8'd1);
        emit_mfm_byte(id_crc[15:8]);
        emit_mfm_byte(id_crc[7:0]);

        emit_gap(10);
        emit_sync;
        data_crc = 16'hffff;
        data_crc = crc16_byte(data_crc, 8'ha1);
        data_crc = crc16_byte(data_crc, 8'ha1);
        data_crc = crc16_byte(data_crc, 8'ha1);
        data_crc = crc16_byte(data_crc, 8'hfb);
        emit_mfm_byte(8'hfb);
        for (index = 0; index < 256; index = index + 1) begin
            data_crc = crc16_byte(data_crc, index[7:0] ^ 8'h5a);
            emit_mfm_byte(index[7:0] ^ 8'h5a);
        end
        emit_mfm_byte(data_crc[15:8]);
        emit_mfm_byte(data_crc[7:0]);
        emit_gap(12);
        // Supply a final legal transition interval and mark it as the end.
        send_interval(8'd50, 1);

        wait (done);
        #1;
        if (!success || decoded_track != 17 || decoded_side != 0 ||
            sector_valid != 18'b000000000000000100 ||
            id_crc_errors != 0 || data_crc_errors != 0) begin
            $display("FAIL: decoded track metadata is wrong track=%0d side=%0d valid=%h iderr=%0d dataerr=%0d",
                     decoded_track, decoded_side, sector_valid,
                     id_crc_errors, data_crc_errors);
            $fatal;
        end
        cache_read_address = 13'd512;
        repeat (2) @(posedge clock); #1;
        if (cache_read_data != 8'h5a) begin
            $display("FAIL: first decoded sector byte is %h", cache_read_data);
            $fatal;
        end
        cache_read_address = 13'd767;
        repeat (2) @(posedge clock); #1;
        if (cache_read_data != 8'ha5) begin
            $display("FAIL: last decoded sector byte is %h", cache_read_data);
            $fatal;
        end
        $display("PASS: CoCo DECB MFM track decoder and CRC");
        $finish;
    end
endmodule
