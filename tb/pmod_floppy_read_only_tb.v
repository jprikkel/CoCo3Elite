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
    reg read_data_n = 1'b1;
    reg track_zero_n = 1'b1;
    reg index_n = 1'b1;
    wire drive_select_n, motor_enable_n, direction, step_n, side_select;
    wire motor_active;
    wire home_active, home_done_toggle, home_success;
    wire [7:0] home_step_count;
    wire [2:0] input_status;
    wire [31:0] index_pulse_count, read_transition_count;

    always #5 clock = !clock;

    pmod_floppy_read_only #(
        .MOTOR_MAX_CYCLES(40), .HOME_SPINUP_CYCLES(2),
        .HOME_DIRECTION_SETUP_CYCLES(2), .STEP_LOW_CYCLES(2),
        .STEP_INTERVAL_CYCLES(3), .HOME_MAX_STEPS(4)
    ) dut (
        .clock(clock), .reset(reset),
        .motor_request(motor_request),
        .direction_request(direction_request),
        .side_select_request(side_select_request),
        .step_request_toggle(step_request_toggle),
        .home_request_toggle(home_request_toggle),
        .abort_request_toggle(abort_request_toggle),
        .read_data_n(read_data_n), .track_zero_n(track_zero_n),
        .index_n(index_n), .drive_select_n(drive_select_n),
        .motor_enable_n(motor_enable_n), .direction(direction),
        .step_n(step_n), .side_select(side_select),
        .motor_active(motor_active),
        .home_active(home_active), .home_done_toggle(home_done_toggle),
        .home_success(home_success), .home_step_count(home_step_count),
        .input_status(input_status),
        .index_pulse_count(index_pulse_count),
        .read_transition_count(read_transition_count)
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
        repeat (41) @(posedge clock); #1;
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
        if (index_pulse_count !== 1 || input_status[0] !== 1'b0) begin
            $display("FAIL: index pulse counter is incorrect");
            $fatal;
        end

        read_data_n = 1'b0;
        settle;
        read_data_n = 1'b1;
        settle;
        read_data_n = 1'b0;
        settle;
        if (read_transition_count !== 3) begin
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
