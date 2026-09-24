`timescale 1ns/1ps
`default_nettype none

// Integration check for the FF91 slow timer and FF92/FF93 HBORD source.
// Sock's reference defines both in terms of one CoCo HSYNC: HBORD occurs on
// its falling edge and the slow timer period is approximately 63.695 us.
// COCO3VIDEO emits each CoCo line twice, so the duplicate transport HSYNC
// must not reach either GIME source.
module gime_reference_sync_cadence_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg video_hsync = 1'b1;
    reg pia_hsync = 1'b1;
    integer failures = 0;

    always #5 clock = ~clock;

    coco3_boot_machine dut (
        .clock(clock), .reset(reset), .cpu_fast_mode(1'b0),
        .cpu_halt(1'b1), .cartridge_enabled(1'b0),
        .cartridge_launch(1'b0), .cartridge_address(15'h0000),
        .cartridge_write_data(8'h00), .cartridge_write(1'b0),
        .cold_start_clear(1'b0), .bin_fifo_data(8'h00),
        .bin_fifo_available(1'b0), .bin_transfer_active(1'b0),
        .bin_transfer_complete(1'b0), .bin_transfer_error(1'b0),
        .keyboard_keys(56'h0), .keyboard_shift(1'b0),
        .keyboard_shift_override(1'b0), .joystick_left_x(6'd32),
        .joystick_left_y(6'd32), .joystick_left_fire(1'b0), .joystick_left_fire2(1'b0),
        .joystick_right_x(6'd32), .joystick_right_y(6'd32),
        .joystick_right_fire(1'b0), .joystick_right_fire2(1'b0), .sd_status(8'h00),
        .sd_detail(8'h00), .video_hsync(video_hsync),
        .pia_hsync(pia_hsync), .video_vsync(1'b1),
        .video_address(20'h00000), .sd_drive_present(2'b00),
        .sd_fdc_done_toggle(1'b0), .sd_fdc_success(1'b0),
        .sd_fdc_write_done_toggle(1'b0),
        .sd_fdc_write_success(1'b0), .sd_fdc_data(8'h00)
    );

    task clear_gime_status;
        begin
            force dut.gime_irq_ack = 1'b1;
            force dut.gime_firq_ack = 1'b1;
            @(posedge clock); #1;
            release dut.gime_irq_ack;
            release dut.gime_firq_ack;
        end
    endtask

    task rise_both;
        begin
            @(negedge clock);
            video_hsync = 1'b1;
            pia_hsync = 1'b1;
            @(posedge clock); #1;
        end
    endtask

    task fall_duplicate_transport_line;
        begin
            // SYNC_FLAG suppresses this duplicate line at pia_hsync.
            @(negedge clock);
            video_hsync = 1'b0;
            pia_hsync = 1'b1;
            @(posedge clock); #1;
        end
    endtask

    task fall_logical_coco_line;
        begin
            @(negedge clock);
            video_hsync = 1'b0;
            pia_hsync = 1'b0;
            @(posedge clock); #1;
        end
    endtask

    task seed_slow_timer_one;
        begin
            force dut.gime_timer_i.timer_enable = 1'b1;
            force dut.gime_timer_i.timer_count = 13'h1fff;
            force dut.gime_timer_i.timer_msb = 4'h0;
            force dut.gime_timer_i.timer_lsb = 8'h01;
            #1;
            release dut.gime_timer_i.timer_enable;
            release dut.gime_timer_i.timer_count;
            release dut.gime_timer_i.timer_msb;
            release dut.gime_timer_i.timer_lsb;
        end
    endtask

    initial begin
        repeat (4) @(posedge clock);
        #1 reset = 1'b0;
        // Enable HBORD in both status paths and select the slow timer.
        force dut.gime_init0 = 8'h30;
        force dut.gime_init1 = 8'h00;
        force dut.gime_irq_enable = 6'b010000;
        force dut.gime_firq_enable = 6'b010000;

        clear_gime_status();
        rise_both();
        fall_duplicate_transport_line();
        if (dut.gime_irq_status[4] || dut.gime_firq_status[4]) begin
            $display("FAIL duplicate renderer HSYNC generated GIME HBORD");
            failures = failures + 1;
        end

        clear_gime_status();
        rise_both();
        fall_logical_coco_line();
        if (!dut.gime_irq_status[4] || !dut.gime_firq_status[4]) begin
            $display("FAIL logical CoCo HSYNC did not generate GIME HBORD");
            failures = failures + 1;
        end

        // The duplicate line must likewise not advance the 63.695 us timer.
        rise_both();
        seed_slow_timer_one();
        fall_duplicate_transport_line();
        if (dut.gime_timer_i.timer_count !== 13'h1fff ||
            dut.gime_timer_expire) begin
            $display("FAIL duplicate renderer HSYNC advanced slow GIME timer");
            failures = failures + 1;
        end

        // A value of one on the selected 1987 GIME takes two real ticks.
        rise_both();
        seed_slow_timer_one();
        fall_logical_coco_line();
        if (dut.gime_timer_i.timer_count !== 13'h0000 ||
            dut.gime_timer_expire) begin
            $display("FAIL first logical HSYNC did not advance slow timer to zero");
            failures = failures + 1;
        end
        rise_both();
        fall_logical_coco_line();
        if (!dut.gime_timer_expire) begin
            $display("FAIL second logical HSYNC did not expire slow timer");
            failures = failures + 1;
        end

        release dut.gime_init0;
        release dut.gime_init1;
        release dut.gime_irq_enable;
        release dut.gime_firq_enable;

        if (failures != 0)
            $fatal(1, "GIME HSYNC cadence mismatches=%0d", failures);
        $display("PASS: GIME HBORD and slow timer use logical CoCo HSYNC only");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clock);
        $fatal(1, "GIME sync cadence test timeout");
    end
endmodule

`default_nettype wire
