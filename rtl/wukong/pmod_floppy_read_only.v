`timescale 1ns/1ps
`default_nettype none

// Safe first-stage interface to the Adafruit Floppy FeatherWing on J13.
//
// Drive select and motor may be enabled for a bounded diagnostic interval.
// A hardware watchdog removes both signals even if firmware stalls. Three
// asynchronous drive inputs are synchronized into the pixel-clock domain and
// reduced to passive telemetry. No write-gate or write-data signal exists.
module pmod_floppy_read_only #(
    parameter integer MOTOR_MAX_CYCLES = 252000000,
    parameter integer HOME_SPINUP_CYCLES = 12600000,
    parameter integer HOME_DIRECTION_SETUP_CYCLES = 504000,
    parameter integer STEP_LOW_CYCLES = 504,
    parameter integer STEP_INTERVAL_CYCLES = 151200,
    parameter integer HOME_MAX_STEPS = 85,
    parameter integer CAPTURE_MAX_CYCLES = 7560000,
    // 205 ms includes a complete nominal 300 RPM revolution plus modest
    // spindle tolerance when flipped media hides the index aperture.
    parameter integer CAPTURE_INDEXLESS_CYCLES = 5166000,
    parameter integer CAPTURE_BULK_SAMPLES = 49152
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        motor_request,
    input  wire        direction_request,
    input  wire        side_select_request,
    input  wire        step_request_toggle,
    input  wire        home_request_toggle,
    input  wire        abort_request_toggle,
    input  wire        capture_request_toggle,
    input  wire [15:0] capture_skip_count,
    input  wire [15:0] capture_sample_address,
    input  wire        read_data_n,
    input  wire        track_zero_n,
    input  wire        index_n,
    output wire        drive_select_n,
    output wire        motor_enable_n,
    output wire        direction,
    output wire        step_n,
    output wire        side_select,
    output reg         motor_active,
    output reg         home_active,
    output reg         home_done_toggle,
    output reg         home_success,
    output reg  [7:0]  home_step_count,
    output wire [2:0]  input_status,
    output reg  [31:0] index_pulse_count,
    output reg  [31:0] read_transition_count,
    output reg         capture_busy,
    output reg         capture_done_toggle,
    output reg         capture_success,
    output reg         capture_truncated,
    output reg         capture_direction,
    output reg         capture_side,
    output reg  [15:0] capture_flux_count,
    output reg  [23:0] capture_revolution_cycles,
    output reg  [15:0] capture_min_interval,
    output reg  [15:0] capture_max_interval,
    output reg  [31:0] capture_hash,
    output reg  [15:0] capture_sample_count,
    output reg  [15:0] capture_sample_data
);
    (* ASYNC_REG = "TRUE" *) reg [2:0] input_meta;
    (* ASYNC_REG = "TRUE" *) reg [2:0] input_sync;
    reg [2:0] input_previous;
    reg [1:0] synchronization_valid;
    (* ASYNC_REG = "TRUE" *) reg [5:0] control_meta;
    (* ASYNC_REG = "TRUE" *) reg [5:0] control_sync;
    reg [5:0] control_previous;
    reg [31:0] motor_watchdog;
    reg [31:0] home_timer;
    reg [31:0] manual_step_timer;
    reg manual_step_active;
    reg [2:0] home_state;
    reg capture_request_meta;
    reg capture_request_sync;
    reg capture_request_previous;
    reg [1:0] capture_state;
    reg [31:0] capture_timer;
    reg [15:0] capture_interval_timer;
    reg [15:0] capture_interval_index;
    reg capture_have_flux;
    reg capture_bulk_mode;
    reg capture_indexless_mode;
    (* ram_style = "block" *) reg [15:0] capture_samples [0:1023];
    // A DECB track is normally below 48K transitions. Bulk captures
    // quantize 25.2 MHz intervals to two-clock units, fitting one uninterrupted
    // track in 48 KiB. Overflow is reported instead of silently wrapping.
    (* ram_style = "block" *) reg [7:0]
        capture_bulk_samples [0:CAPTURE_BULK_SAMPLES-1];
    reg [15:0] capture_sample_word;
    reg [7:0] capture_bulk_sample_byte;
    wire index_active_edge = input_previous[0] && !input_sync[0];
    // RD is an active-low pulse for each detected flux transition. The rising
    // edge is the fixed pulse ending, not a second transition.
    wire flux_active_edge = input_previous[2] && !input_sync[2];
    wire [15:0] capture_current_interval =
        capture_interval_timer == 16'hffff
        ? 16'hffff : capture_interval_timer + 1'b1;
    // One unit is two 25.2 MHz clocks (79.4 ns). This retains enough timing
    // resolution for FM/MFM decoding while fitting a revolution in 48 KiB.
    wire [7:0] capture_bulk_interval =
        capture_current_interval >= 16'd510
        ? 8'hff : (capture_current_interval + 1'b1) >> 1;

    localparam [2:0] HOME_IDLE = 3'd0,
                     HOME_SPINUP = 3'd1,
                     HOME_DIRECTION_SETUP = 3'd2,
                     HOME_STEP_LOW = 3'd3,
                     HOME_STEP_INTERVAL = 3'd4;
    localparam [1:0] CAPTURE_IDLE = 2'd0,
                     CAPTURE_WAIT_INDEX = 2'd1,
                     CAPTURE_REVOLUTION = 2'd2;

    // Select, motor, and step are active low. Direction and side are runtime
    // controls so drive mechanics and cable wiring can be diagnosed over the
    // serial API without rebuilding the FPGA image.
    assign drive_select_n = !motor_active;
    assign motor_enable_n = !motor_active;
    assign direction      = control_sync[3];
    assign step_n         = ((home_state == HOME_STEP_LOW) ||
                             manual_step_active) ? 1'b0 : 1'b1;
    assign side_select    = control_sync[4];

    // Status is active-high for software: {read level, track zero, index}.
    assign input_status = {input_sync[2], !input_sync[1], !input_sync[0]};

    always @(posedge clock) begin
        if (reset) begin
            input_meta <= 3'b111;
            input_sync <= 3'b111;
            input_previous <= 3'b111;
            synchronization_valid <= 2'b00;
            control_meta <= 6'b011000;
            control_sync <= 6'b011000;
            control_previous <= 6'b011000;
            motor_watchdog <= 32'b0;
            home_timer <= 32'b0;
            manual_step_timer <= 32'b0;
            manual_step_active <= 1'b0;
            home_state <= HOME_IDLE;
            motor_active <= 1'b0;
            home_active <= 1'b0;
            home_done_toggle <= 1'b0;
            home_success <= 1'b0;
            home_step_count <= 8'b0;
            index_pulse_count <= 32'b0;
            read_transition_count <= 32'b0;
            capture_request_meta <= 1'b0;
            capture_request_sync <= 1'b0;
            capture_request_previous <= 1'b0;
            capture_state <= CAPTURE_IDLE;
            capture_timer <= 32'b0;
            capture_interval_timer <= 16'b0;
            capture_interval_index <= 16'b0;
            capture_have_flux <= 1'b0;
            capture_bulk_mode <= 1'b0;
            capture_indexless_mode <= 1'b0;
            capture_busy <= 1'b0;
            capture_done_toggle <= 1'b0;
            capture_success <= 1'b0;
            capture_truncated <= 1'b0;
            capture_direction <= 1'b1;
            capture_side <= 1'b1;
            capture_flux_count <= 16'b0;
            capture_revolution_cycles <= 24'b0;
            capture_min_interval <= 16'hffff;
            capture_max_interval <= 16'b0;
            capture_hash <= 32'h811c9dc5;
            capture_sample_count <= 16'b0;
            capture_sample_data <= 16'b0;
        end else begin
            input_meta <= {read_data_n, track_zero_n, index_n};
            input_sync <= input_meta;
            input_previous <= input_sync;
            synchronization_valid <= {synchronization_valid[0], 1'b1};
            control_meta <= {step_request_toggle, side_select_request,
                             direction_request, abort_request_toggle,
                             home_request_toggle, motor_request};
            control_sync <= control_meta;
            control_previous <= control_sync;
            capture_request_meta <= capture_request_toggle;
            capture_request_sync <= capture_request_meta;
            capture_request_previous <= capture_request_sync;
            // Select between independently registered BRAM read ports.  A
            // mux around the array references prevents Vivado from inferring
            // block RAM and would otherwise expand the 64 KiB track buffer
            // into thousands of LUTRAM primitives.
            capture_sample_data <= capture_bulk_mode
                ? {8'b0, capture_bulk_sample_byte}
                : capture_sample_word;

            // Abort is an event rather than a firmware-dependent level. It
            // immediately removes select, motor, and STEP even if firmware
            // becomes stuck during a seek.
            if (control_sync[2] != control_previous[2]) begin
                if (home_active) begin
                    home_done_toggle <= ~home_done_toggle;
                    home_success <= 1'b0;
                end
                home_active <= 1'b0;
                home_state <= HOME_IDLE;
                home_timer <= 32'b0;
                motor_active <= 1'b0;
                motor_watchdog <= 32'b0;
                manual_step_active <= 1'b0;
                manual_step_timer <= 32'b0;
                if (capture_busy) begin
                    capture_busy <= 1'b0;
                    capture_success <= 1'b0;
                    capture_done_toggle <= ~capture_done_toggle;
                end
                capture_state <= CAPTURE_IDLE;
            end else if ((control_sync[1] != control_previous[1]) &&
                         !home_active && !capture_busy) begin
                home_active <= 1'b1;
                home_success <= 1'b0;
                home_step_count <= 8'b0;
                home_state <= HOME_SPINUP;
                home_timer <= HOME_SPINUP_CYCLES - 1;
                motor_active <= 1'b1;
                motor_watchdog <= MOTOR_MAX_CYCLES - 1;
            end else if (home_active) begin
                if (!input_sync[1]) begin
                    home_active <= 1'b0;
                    home_state <= HOME_IDLE;
                    home_success <= 1'b1;
                    home_done_toggle <= ~home_done_toggle;
                    motor_active <= 1'b0;
                    motor_watchdog <= 32'b0;
                end else if (motor_watchdog == 0) begin
                    home_active <= 1'b0;
                    home_state <= HOME_IDLE;
                    home_success <= 1'b0;
                    home_done_toggle <= ~home_done_toggle;
                    motor_active <= 1'b0;
                end else begin
                    motor_watchdog <= motor_watchdog - 1'b1;
                    case (home_state)
                        HOME_SPINUP: begin
                            if (home_timer == 0) begin
                                home_state <= HOME_DIRECTION_SETUP;
                                home_timer <= HOME_DIRECTION_SETUP_CYCLES - 1;
                            end else
                                home_timer <= home_timer - 1'b1;
                        end
                        HOME_DIRECTION_SETUP: begin
                            if (home_timer == 0) begin
                                home_state <= HOME_STEP_LOW;
                                home_timer <= STEP_LOW_CYCLES - 1;
                            end else
                                home_timer <= home_timer - 1'b1;
                        end
                        HOME_STEP_LOW: begin
                            if (home_timer == 0) begin
                                home_step_count <= home_step_count + 1'b1;
                                home_state <= HOME_STEP_INTERVAL;
                                home_timer <= STEP_INTERVAL_CYCLES - 1;
                            end else
                                home_timer <= home_timer - 1'b1;
                        end
                        HOME_STEP_INTERVAL: begin
                            if (home_timer == 0) begin
                                if (home_step_count >= HOME_MAX_STEPS) begin
                                    home_active <= 1'b0;
                                    home_state <= HOME_IDLE;
                                    home_success <= 1'b0;
                                    home_done_toggle <= ~home_done_toggle;
                                    motor_active <= 1'b0;
                                    motor_watchdog <= 32'b0;
                                end else begin
                                    home_state <= HOME_STEP_LOW;
                                    home_timer <= STEP_LOW_CYCLES - 1;
                                end
                            end else
                                home_timer <= home_timer - 1'b1;
                        end
                        default: begin
                            home_state <= HOME_IDLE;
                            home_active <= 1'b0;
                            home_success <= 1'b0;
                            home_done_toggle <= ~home_done_toggle;
                            motor_active <= 1'b0;
                            motor_watchdog <= 32'b0;
                        end
                    endcase
                end
            end else begin
                // Standalone motor test. A timed-out request must first be
                // released before a rising edge can start another interval.
                if (!control_sync[0]) begin
                    motor_active <= 1'b0;
                    motor_watchdog <= 32'b0;
                end else if (control_sync[0] && !control_previous[0]) begin
                    motor_active <= 1'b1;
                    motor_watchdog <= MOTOR_MAX_CYCLES - 1;
                end else if (motor_active) begin
                    if (motor_watchdog == 0)
                        motor_active <= 1'b0;
                    else
                        motor_watchdog <= motor_watchdog - 1'b1;
                end
            end

            // Capture one complete revolution of active-low read-data pulse
            // timing.  Keep a compact exact prefix for diagnostics and fold
            // every interval into summary statistics and an order-sensitive
            // signature.  This works for either head; host software may also
            // reverse the interval prefix when examining physically flipped
            // media.
            if (control_sync[2] != control_previous[2]) begin
                capture_busy <= 1'b0;
                capture_success <= 1'b0;
                capture_state <= CAPTURE_IDLE;
            end else if ((capture_request_sync != capture_request_previous) &&
                !capture_busy && !home_active && control_sync[0]) begin
                capture_busy <= 1'b1;
                capture_success <= 1'b0;
                capture_truncated <= 1'b0;
                capture_direction <= control_sync[3];
                capture_side <= control_sync[4];
                capture_flux_count <= 16'b0;
                capture_revolution_cycles <= 24'b0;
                capture_min_interval <= 16'hffff;
                capture_max_interval <= 16'b0;
                capture_hash <= 32'h811c9dc5;
                capture_sample_count <= 16'b0;
                capture_interval_timer <= 16'b0;
                capture_interval_index <= 16'b0;
                capture_have_flux <= 1'b0;
                capture_bulk_mode <= capture_skip_count == 16'hffff ||
                                     capture_skip_count == 16'hfffe;
                capture_indexless_mode <= capture_skip_count == 16'hffff;
                if (capture_skip_count == 16'hffff) begin
                    capture_state <= CAPTURE_REVOLUTION;
                    capture_timer <= CAPTURE_INDEXLESS_CYCLES - 1;
                end else begin
                    capture_state <= CAPTURE_WAIT_INDEX;
                    capture_timer <= CAPTURE_MAX_CYCLES - 1;
                end
            end else if (capture_busy) begin
                if (!motor_active || !control_sync[0]) begin
                    capture_busy <= 1'b0;
                    capture_success <= 1'b0;
                    capture_done_toggle <= ~capture_done_toggle;
                    capture_state <= CAPTURE_IDLE;
                end else begin
                    case (capture_state)
                        CAPTURE_WAIT_INDEX: begin
                            if (capture_timer == 0) begin
                                capture_busy <= 1'b0;
                                capture_success <= 1'b0;
                                capture_done_toggle <= ~capture_done_toggle;
                                capture_state <= CAPTURE_IDLE;
                            end else if (index_active_edge) begin
                                capture_state <= CAPTURE_REVOLUTION;
                                capture_timer <= CAPTURE_MAX_CYCLES - 1;
                                capture_revolution_cycles <= 24'b0;
                                capture_interval_timer <= 16'b0;
                                capture_interval_index <= 16'b0;
                                capture_have_flux <= 1'b0;
                            end else
                                capture_timer <= capture_timer - 1'b1;
                        end
                        CAPTURE_REVOLUTION: begin
                            if (!capture_indexless_mode && index_active_edge) begin
                                capture_busy <= 1'b0;
                                capture_success <= capture_flux_count != 0;
                                capture_done_toggle <= ~capture_done_toggle;
                                capture_state <= CAPTURE_IDLE;
                            end else if (capture_timer == 0) begin
                                capture_busy <= 1'b0;
                                capture_success <= capture_indexless_mode &&
                                                   capture_flux_count != 0;
                                capture_done_toggle <= ~capture_done_toggle;
                                capture_state <= CAPTURE_IDLE;
                            end else begin
                                capture_timer <= capture_timer - 1'b1;
                                if (capture_revolution_cycles != 24'hffffff)
                                    capture_revolution_cycles <=
                                        capture_revolution_cycles + 1'b1;
                                if (capture_interval_timer != 16'hffff)
                                    capture_interval_timer <=
                                        capture_interval_timer + 1'b1;
                                if (flux_active_edge) begin
                                    if (capture_flux_count != 16'hffff)
                                        capture_flux_count <=
                                            capture_flux_count + 1'b1;
                                    else
                                        capture_truncated <= 1'b1;
                                    if (capture_have_flux) begin
                                        if (capture_bulk_mode) begin
                                            if (capture_sample_count <
                                                CAPTURE_BULK_SAMPLES) begin
                                                capture_bulk_samples[
                                                    capture_sample_count] <=
                                                    capture_bulk_interval;
                                                capture_sample_count <=
                                                    capture_sample_count + 1'b1;
                                            end else begin
                                                capture_truncated <= 1'b1;
                                            end
                                        end else if (capture_interval_index >=
                                            capture_skip_count &&
                                            capture_sample_count < 16'd1024) begin
                                            capture_samples[
                                                capture_sample_count[9:0]] <=
                                                capture_current_interval;
                                            capture_sample_count <=
                                                capture_sample_count + 1'b1;
                                        end else if (capture_interval_index >=
                                                     capture_skip_count)
                                            capture_truncated <= 1'b1;
                                        if (capture_interval_index != 16'hffff)
                                            capture_interval_index <=
                                                capture_interval_index + 1'b1;
                                        if (capture_current_interval <
                                            capture_min_interval)
                                            capture_min_interval <=
                                                capture_current_interval;
                                        if (capture_current_interval >
                                            capture_max_interval)
                                            capture_max_interval <=
                                                capture_current_interval;
                                        capture_hash <=
                                            {capture_hash[24:0],
                                             capture_hash[31:25]} ^
                                            {16'b0,
                                             capture_current_interval};
                                    end else
                                        capture_have_flux <= 1'b1;
                                    capture_interval_timer <= 16'b0;
                                end
                            end
                        end
                        default: begin
                            capture_busy <= 1'b0;
                            capture_success <= 1'b0;
                            capture_done_toggle <= ~capture_done_toggle;
                            capture_state <= CAPTURE_IDLE;
                        end
                    endcase
                end
            end

            // A serial STEP request produces one bounded active-low pulse.
            // It is accepted only while the drive is already selected and
            // never competes with the automatic HOME state machine.
            if (control_sync[2] != control_previous[2]) begin
                manual_step_active <= 1'b0;
                manual_step_timer <= 32'b0;
            end else if ((control_sync[5] != control_previous[5]) &&
                         motor_active && !home_active &&
                         !capture_busy && !manual_step_active) begin
                manual_step_active <= 1'b1;
                manual_step_timer <= STEP_LOW_CYCLES - 1;
            end else if (manual_step_active) begin
                if (manual_step_timer == 0)
                    manual_step_active <= 1'b0;
                else
                    manual_step_timer <= manual_step_timer - 1'b1;
            end

            if (synchronization_valid[1]) begin
                // Index is an active-low pulse; count its leading edge.
                if (index_active_edge &&
                    index_pulse_count != 32'hffffffff)
                    index_pulse_count <= index_pulse_count + 1'b1;

                // Raw read data alternates at every flux transition. Count
                // either edge without interpreting FM/MFM timing yet.
                if (input_previous[2] != input_sync[2] &&
                    read_transition_count != 32'hffffffff)
                    read_transition_count <= read_transition_count + 1'b1;
            end
        end
    end

    always @(posedge clock) begin
        capture_sample_word <= capture_samples[capture_sample_address[9:0]];
        capture_bulk_sample_byte <=
            capture_bulk_samples[capture_sample_address];
    end
endmodule

`default_nettype wire
