`timescale 1ns/1ps

module pmod_floppy_read_only_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg motor_request = 1'b0;
    reg direction_request = 1'b1;
    reg side_select_request = 1'b1;
    reg step_request_toggle = 1'b0;
    reg home_request_toggle = 1'b0;
    reg abort_request_toggle = 1'b0;
    reg capture_request_toggle = 1'b0;
    reg [15:0] capture_skip_count = 16'b0;
    reg [15:0] capture_sample_address = 16'b0;
    reg read_data_n = 1'b1;
    reg track_zero_n = 1'b1;
    reg index_n = 1'b1;
    wire drive_select_n, motor_enable_n, direction, step_n, side_select;
    wire motor_active;
    wire home_active, home_done_toggle, home_success;
    wire [7:0] home_step_count;
    wire [2:0] input_status;
    wire [31:0] index_pulse_count, read_transition_count;
    wire capture_busy, capture_done_toggle, capture_success;
    wire capture_truncated, capture_direction, capture_side;
    wire [15:0] capture_flux_count, capture_min_interval;
    wire [15:0] capture_max_interval, capture_sample_data;
    wire [23:0] capture_revolution_cycles;
    wire [31:0] capture_hash;
    wire [15:0] capture_sample_count;

    always #5 clock = !clock;

    pmod_floppy_read_only #(
        .MOTOR_MAX_CYCLES(500), .HOME_SPINUP_CYCLES(2),
        .HOME_DIRECTION_SETUP_CYCLES(2), .STEP_LOW_CYCLES(2),
        .STEP_INTERVAL_CYCLES(3), .HOME_MAX_STEPS(4),
        .CAPTURE_MAX_CYCLES(100), .CAPTURE_INDEXLESS_CYCLES(120)
    ) dut (
        .clock(clock), .reset(reset),
        .motor_request(motor_request),
        .direction_request(direction_request),
        .side_select_request(side_select_request),
        .step_request_toggle(step_request_toggle),
        .home_request_toggle(home_request_toggle),
        .abort_request_toggle(abort_request_toggle),
        .capture_request_toggle(capture_request_toggle),
        .capture_skip_count(capture_skip_count),
        .capture_sample_address(capture_sample_address),
        .read_data_n(read_data_n), .track_zero_n(track_zero_n),
        .index_n(index_n), .drive_select_n(drive_select_n),
        .motor_enable_n(motor_enable_n), .direction(direction),
        .step_n(step_n), .side_select(side_select),
        .motor_active(motor_active),
        .home_active(home_active), .home_done_toggle(home_done_toggle),
        .home_success(home_success), .home_step_count(home_step_count),
        .input_status(input_status),
        .index_pulse_count(index_pulse_count),
        .read_transition_count(read_transition_count),
        .capture_busy(capture_busy),
        .capture_done_toggle(capture_done_toggle),
        .capture_success(capture_success),
        .capture_truncated(capture_truncated),
        .capture_direction(capture_direction),
        .capture_side(capture_side),
        .capture_flux_count(capture_flux_count),
        .capture_revolution_cycles(capture_revolution_cycles),
        .capture_min_interval(capture_min_interval),
        .capture_max_interval(capture_max_interval),
        .capture_hash(capture_hash),
        .capture_sample_count(capture_sample_count),
        .capture_sample_data(capture_sample_data)
    );

    task settle;
        begin
            repeat (4) @(posedge clock);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        #1;
        if ({drive_select_n,motor_enable_n,direction,step_n,side_select}
            !== 5'b11111) begin
            $display("FAIL: floppy outputs are not reset-safe");
            $fatal;
        end

        reset = 1'b0;
        settle;
        if (input_status !== 3'b100 || index_pulse_count !== 0 ||
            read_transition_count !== 0) begin
            $display("FAIL: idle floppy input state is incorrect");
            $fatal;
        end

        motor_request = 1'b1;
        wait (motor_active); #1;
        if (!motor_active || drive_select_n || motor_enable_n ||
            {direction,step_n,side_select} !== 3'b111) begin
            $display("FAIL: bounded motor request did not select the drive");
            $fatal;
        end
        direction_request = 1'b0;
        side_select_request = 1'b0;
        settle;
        if (direction || side_select) begin
            $display("FAIL: runtime direction/side control did not update");
            $fatal;
        end
        step_request_toggle = !step_request_toggle;
        wait (!step_n);
        wait (step_n);
        direction_request = 1'b1;
        side_select_request = 1'b1;
        settle;
        if (!direction || !side_select) begin
            $display("FAIL: runtime direction/side control did not restore");
            $fatal;
        end
        repeat (501) @(posedge clock); #1;
        if (motor_active || !drive_select_n || !motor_enable_n) begin
            $display("FAIL: hardware motor watchdog did not expire safely");
            $fatal;
        end
        motor_request = 1'b0;
        settle;
        motor_request = 1'b1;
        wait (motor_active); #1;
        if (!motor_active) begin
            $display("FAIL: motor did not restart after request release");
            $fatal;
        end

        // Capture falling-edge flux pulses from one index-bounded turn. Four
        // pulses produce three intervals because the first establishes time.
        capture_request_toggle = !capture_request_toggle;
        wait (capture_busy);
        index_n = 1'b0; settle; index_n = 1'b1; settle;
        repeat (4) begin
            read_data_n = 1'b0; settle;
            read_data_n = 1'b1; settle;
        end
        index_n = 1'b0; settle; index_n = 1'b1; settle;
        wait (!capture_busy); #1;
        if (!capture_success || capture_flux_count !== 4 ||
            capture_sample_count !== 3 || capture_truncated ||
            capture_min_interval == 0 ||
            capture_max_interval < capture_min_interval ||
            capture_hash == 32'h811c9dc5) begin
            $display("FAIL: indexed flux capture statistics are incorrect");
            $fatal;
        end
        capture_sample_address = 0; settle;
        if (capture_sample_data == 0) begin
            $display("FAIL: indexed flux capture BRAM did not return data");
            $fatal;
        end

        // $fffe captures one contiguous indexed revolution into bulk BRAM.
        capture_skip_count = 16'hfffe;
        capture_request_toggle = !capture_request_toggle;
        wait (capture_busy);
        index_n = 1'b0; settle; index_n = 1'b1; settle;
        repeat (5) begin
            read_data_n = 1'b0; settle;
            read_data_n = 1'b1; settle;
        end
        index_n = 1'b0; settle; index_n = 1'b1; settle;
        wait (!capture_busy); #1;
        if (!capture_success || capture_flux_count !== 5 ||
            capture_sample_count !== 4 || capture_truncated) begin
            $display("FAIL: indexed bulk flux capture is incorrect");
            $fatal;
        end
        capture_sample_address = 0; settle;
        if (capture_sample_data[7:0] == 0 ||
            capture_sample_data[15:8] != 0) begin
            $display("FAIL: indexed bulk BRAM did not return data");
            $fatal;
        end

        // A flipped disk can hide the index aperture. $ffff requests one
        // uninterrupted timed capture with the same byte format.
        capture_skip_count = 16'hffff;
        capture_request_toggle = !capture_request_toggle;
        wait (capture_busy);
        repeat (5) begin
            read_data_n = 1'b0; settle;
            read_data_n = 1'b1; settle;
        end
        wait (!capture_busy); #1;
        if (!capture_success || capture_flux_count !== 5 ||
            capture_sample_count !== 4 || capture_truncated) begin
            $display("FAIL: indexless bulk flux capture is incorrect");
            $fatal;
        end
        capture_sample_address = 0; settle;
        if (capture_sample_data[7:0] == 0 ||
            capture_sample_data[15:8] != 0) begin
            $display("FAIL: indexless compressed BRAM did not return data");
            $fatal;
        end
        motor_request = 1'b0;
        settle;
        if (motor_active || !drive_select_n || !motor_enable_n) begin
            $display("FAIL: explicit motor stop was not immediate");
            $fatal;
        end

        track_zero_n = 1'b0;
        settle;
        if (input_status !== 3'b110) begin
            $display("FAIL: track-zero input was not synchronized");
            $fatal;
        end

        index_n = 1'b0;
        settle;
        index_n = 1'b1;
        settle;
        if (index_pulse_count !== 5 || input_status[0] !== 1'b0) begin
            $display("FAIL: index pulse counter is incorrect count=%0d status=%b",
                     index_pulse_count, input_status);
            $fatal;
        end

        read_data_n = 1'b0;
        settle;
        read_data_n = 1'b1;
        settle;
        read_data_n = 1'b0;
        settle;
        if (read_transition_count !== 31) begin
            $display("FAIL: read-transition counter is incorrect");
            $fatal;
        end

        // Home successfully after three bounded STEP pulses.
        track_zero_n = 1'b1;
        settle;
        home_request_toggle = !home_request_toggle;
        wait (home_active);
        if (direction !== 1'b1 || !motor_active) begin
            $display("FAIL: home did not select the track-zero direction");
            $fatal;
        end
        wait (home_step_count == 3);
        track_zero_n = 1'b0;
        settle;
        wait (!home_active);
        #1;
        if (!home_success || home_step_count !== 3 || motor_active ||
            !step_n) begin
            $display("FAIL: successful bounded home result is incorrect");
            $fatal;
        end

        // No TRACK0 response must stop after exactly HOME_MAX_STEPS.
        track_zero_n = 1'b1;
        settle;
        home_request_toggle = !home_request_toggle;
        wait (home_active);
        wait (!home_active);
        #1;
        if (home_success || home_step_count !== 4 || motor_active || !step_n) begin
            $display("FAIL: failed home did not stop at the step limit");
            $fatal;
        end

        // STOP/abort must remove all active outputs immediately.
        home_request_toggle = !home_request_toggle;
        wait (home_active);
        abort_request_toggle = !abort_request_toggle;
        repeat (4) @(posedge clock); #1;
        if (home_active || motor_active || !drive_select_n ||
            !motor_enable_n || !step_n || home_success) begin
            $display("FAIL: home abort was not safe and immediate");
            $fatal;
        end

        reset = 1'b1;
        @(posedge clock); #1;
        if (index_pulse_count !== 0 || read_transition_count !== 0 ||
            {drive_select_n,motor_enable_n,direction,step_n,side_select}
            !== 5'b11111) begin
            $display("FAIL: reset did not clear telemetry safely");
            $fatal;
        end

        $display("PASS: J13 read-only floppy telemetry, motor, and home");
        $finish;
    end
endmodule
