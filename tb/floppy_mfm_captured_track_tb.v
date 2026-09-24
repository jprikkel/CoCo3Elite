`timescale 1ns/1ps

module floppy_mfm_captured_track_tb;
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
    reg [7:0] samples [0:49151];
    reg [7:0] expected [0:4607];
    reg [15:0] count_memory [0:0];
    reg [7:0] track_memory [0:0];
    integer sample_count;
    integer index;
    integer expected_track;

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

    initial begin
        $readmemh("captured_track.mem", track_memory);
        expected_track = track_memory[0];
        $readmemh("captured_count.mem", count_memory);
        sample_count = count_memory[0];
        $readmemh("captured_samples.mem", samples);
        $readmemh("captured_expected.mem", expected);
        repeat (4) @(posedge clock);
        reset = 0;
        start = 1;
        @(posedge clock);
        start = 0;
        for (index = 0; index < sample_count; index = index + 1) begin
            while (!sample_ready) @(posedge clock);
            sample_interval = samples[index];
            sample_last = index == sample_count - 1;
            sample_valid = 1;
            @(posedge clock);
            sample_valid = 0;
            sample_last = 0;
        end
        wait (done);
        #1;
        if (!success || decoded_track != expected_track || decoded_side != 0 ||
            sector_valid != 18'h3ffff || id_crc_errors != 0 ||
            data_crc_errors != 0) begin
            $display("FAIL: captured track metadata track=%0d side=%0d valid=%h iderr=%0d dataerr=%0d",
                     decoded_track, decoded_side, sector_valid,
                     id_crc_errors, data_crc_errors);
            $fatal;
        end
        for (index = 0; index < 4608; index = index + 1) begin
            cache_read_address = index;
            repeat (2) @(posedge clock); #1;
            if (cache_read_data !== expected[index]) begin
                $display("FAIL: captured track byte %0d expected=%h actual=%h",
                         index, expected[index], cache_read_data);
                $fatal;
            end
        end
        $display("PASS: captured TEAC track %0d decoded byte-for-byte", expected_track);
        $finish;
    end
endmodule
