`timescale 1ns/1ps
`default_nettype none

// Minimal WD1773-compatible interface for the standard CoCo disk
// controller. The former BRAM-backed DSK images have been removed so they
// cannot conflict with the external SD-card backend. Until that backend is
// connected, sector operations report not-ready.
module coco3_fdc (
    input  wire        clock,
    input  wire        reset,
    input  wire        io_read,
    input  wire        io_write,
    input  wire [15:0] address,
    input  wire [7:0]  write_data,
    output reg  [7:0]  read_data,
    output wire        nmi,
    // Firmware-backed SD transport.  These ports are unused by the optional
    // embedded-ROM test configuration, which remains a deterministic unit
    // test of the WD1773-visible behavior.
    input  wire [2:0]  backend_present,
    input  wire        backend_done_toggle,
    input  wire        backend_success,
    input  wire        backend_write_done_toggle,
    input  wire        backend_write_success,
    input  wire [7:0]  backend_data,
    output wire [7:0]  backend_buffer_address,
    output reg  [1:0]  backend_drive,
    output reg  [7:0]  backend_track,
    output reg  [7:0]  backend_sector,
    output reg  [7:0]  backend_last_type1,
    output reg  [31:0] backend_debug_word,
    output reg  [31:0] backend_completed_debug_word,
    output reg         backend_read_complete_toggle,
    output wire        backend_write_strobe,
    output wire [7:0]  backend_write_data,
    output reg         backend_write_complete_toggle,
    output reg         backend_request_toggle
);
    reg [7:0] drive_latch;
    reg [7:0] status;
    reg [7:0] track;
    reg [7:0] sector;
    reg [7:0] data_register;
    reg [7:0] byte_index;
    reg       read_active;
    reg       read_waiting;
    reg       write_active;
    reg       write_waiting;
    reg       first_data_access;
    reg       nmi_pending;
    reg       last_step_in;
    reg [7:0] debug_byte_count;

    wire drive0_selected = drive_latch[0];
    wire drive1_selected = drive_latch[1];
    wire drive2_selected = drive_latch[2];
    wire drive_selected = drive0_selected | drive1_selected | drive2_selected;
    wire valid_track = track < 8'd35;
    wire valid_position = valid_track && sector >= 8'd1 && sector <= 8'd18;

`ifdef EMBEDDED_TEST_DISKS
    wire [10:0] linear_sector = ({3'b000, track} << 4) +
                                ({3'b000, track} << 1) +
                                {3'b000, sector} - 11'd1;
    wire [18:0] image_address = {linear_sector, 8'b0} + byte_index;
    wire [7:0] drive0_data;
    wire [7:0] drive1_data;
    wire [7:0] image_data = drive0_selected ? drive0_data : drive1_data;

    (* dont_touch = "yes" *)
    coco3_disk_image #(
        .IMAGE_FILE("build/disks/fpgatest.mem"),
        .IMAGE_BYTES(161280)
    ) drive0_image_i (
        .clock(clock), .address(image_address), .data(drive0_data)
    );
    (* dont_touch = "yes" *)
    coco3_disk_image #(
        .IMAGE_FILE("build/disks/games.mem"),
        .IMAGE_BYTES(161280)
    ) drive1_image_i (
        .clock(clock), .address(image_address), .data(drive1_data)
    );
`endif

    wire data_read = io_read && address == 16'hFF4B;
    wire status_read = io_read && address == 16'hFF48;
    assign backend_buffer_address = byte_index;
    // The manager owns the write port of the cache.  The FDC holds its byte
    // index stable for the complete CPU write cycle, including byte FF.
    assign backend_write_strobe = write_active && io_write && address == 16'hFF4B;
    assign backend_write_data = write_data;

    always @* begin
        case (address)
            16'hFF40: read_data = drive_latch;
            16'hFF48: read_data = status;
            16'hFF49: read_data = track;
            16'hFF4A: read_data = sector;
`ifdef EMBEDDED_TEST_DISKS
            16'hFF4B: read_data = read_active ? image_data : data_register;
`else
            16'hFF4B: read_data = read_active ? backend_data : data_register;
`endif
            default:  read_data = 8'hFF;
        endcase
    end

    always @(posedge clock) begin
        if (reset) begin
            drive_latch <= 8'h00;
            status <= 8'h00;
            track <= 8'h00;
            sector <= 8'h01;
            data_register <= 8'h00;
            byte_index <= 8'h00;
            read_active <= 1'b0;
            read_waiting <= 1'b0;
            write_active <= 1'b0;
            write_waiting <= 1'b0;
            first_data_access <= 1'b0;
            nmi_pending <= 1'b0;
            last_step_in <= 1'b0;
            backend_drive <= 2'd0;
            backend_track <= 8'd0;
            backend_sector <= 8'd1;
            backend_last_type1 <= 8'd0;
            backend_debug_word <= 32'd0;
            backend_completed_debug_word <= 32'd0;
            backend_read_complete_toggle <= 1'b0;
            backend_write_complete_toggle <= 1'b0;
            backend_request_toggle <= 1'b0;
            debug_byte_count <= 8'd0;
        end else begin
`ifndef EMBEDDED_TEST_DISKS
            // The manager acknowledges by copying the request toggle after it
            // has filled its 256-byte buffer.  Disk BASIC polls status while
            // this is pending, exactly as it would wait for a real WD1773.
            if (read_waiting && backend_done_toggle == backend_request_toggle) begin
                read_waiting <= 1'b0;
                if (backend_success) begin
                    status <= 8'h03;
                    read_active <= 1'b1;
                    first_data_access <= 1'b1;
                end else begin
                    status <= 8'h10;
                    read_active <= 1'b0;
                    nmi_pending <= 1'b1;
                end
            end
            // A write remains busy until firmware has copied the completed
            // 256-byte cache sector into its containing FAT32 512-byte block
            // and CMD24 has accepted it.  This prevents a later write from
            // overwriting the shared flush buffer.
            if (write_waiting && backend_write_done_toggle == backend_write_complete_toggle) begin
                write_waiting <= 1'b0;
                if (backend_write_success) begin
                    status <= 8'h00;
                end else begin
                    status <= 8'h40;
                end
                nmi_pending <= 1'b1;
            end
`endif
            if (status_read)
                nmi_pending <= 1'b0;

            if (data_read && read_active) begin
                // cpu09 presents a first FF4B service observation before the
                // data is consumed on falling E.  Hold byte zero for that
                // prefetch; the manager buffer has a direct-addressed read
                // port, so the following real access advances cleanly.
                if (first_data_access) begin
                    first_data_access <= 1'b0;
                end else if (byte_index == 8'hFF) begin
                    if (debug_byte_count == 8'd0) backend_debug_word[31:24] <= read_data;
                    else if (debug_byte_count == 8'd1) backend_debug_word[23:16] <= read_data;
                    else if (debug_byte_count == 8'd2) backend_debug_word[15:8] <= read_data;
                    else if (debug_byte_count == 8'd3) backend_debug_word[7:0] <= read_data;
                    debug_byte_count <= debug_byte_count + 1'b1;
                    backend_completed_debug_word <= backend_debug_word;
                    backend_read_complete_toggle <= ~backend_read_complete_toggle;
                    read_active <= 1'b0;
                    status <= 8'h00;
                    nmi_pending <= 1'b1;
                end else begin
                    if (debug_byte_count == 8'd0) backend_debug_word[31:24] <= read_data;
                    else if (debug_byte_count == 8'd1) backend_debug_word[23:16] <= read_data;
                    else if (debug_byte_count == 8'd2) backend_debug_word[15:8] <= read_data;
                    else if (debug_byte_count == 8'd3) backend_debug_word[7:0] <= read_data;
                    debug_byte_count <= debug_byte_count + 1'b1;
                    byte_index <= byte_index + 1'b1;
                end
            end

            if (io_write) begin
                case (address)
                    16'hFF40: drive_latch <= write_data;
                    16'hFF49: track <= write_data;
                    16'hFF4A: sector <= write_data;
                    16'hFF4B: begin
                        data_register <= write_data;
                        if (write_active) begin
                            if (byte_index == 8'hFF) begin
                                write_active <= 1'b0;
                                write_waiting <= 1'b1;
                                status <= 8'h01;
                                backend_write_complete_toggle <= ~backend_write_complete_toggle;
                            end else begin
                                byte_index <= byte_index + 1'b1;
                            end
                        end
                    end
                    16'hFF48: begin
                        nmi_pending <= 1'b0;
                        case (write_data[7:4])
                            4'h0: begin // restore
                                backend_last_type1 <= write_data;
                                track <= 8'h00;
                                last_step_in <= 1'b0;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h1: begin // seek to data register
                                backend_last_type1 <= write_data;
                                track <= data_register;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            // Disk BASIC walks from track zero to the DECB
                            // directory using Type-I STEP-IN commands.  The
                            // former ROM-image test wrote FF49 directly and
                            // therefore never exercised these operations.
                            4'h2, 4'h3: begin // step in the prior direction
                                backend_last_type1 <= write_data;
                                if (last_step_in) track <= track + 1'b1;
                                else if (track != 0) track <= track - 1'b1;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h4, 4'h5: begin // step in
                                backend_last_type1 <= write_data;
                                track <= track + 1'b1;
                                last_step_in <= 1'b1;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h6, 4'h7: begin // step out
                                backend_last_type1 <= write_data;
                                if (track != 0) track <= track - 1'b1;
                                last_step_in <= 1'b0;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h8, 4'h9: begin // read single sector
                                byte_index <= 8'h00;
                                first_data_access <= 1'b1;
                                debug_byte_count <= 8'd0;
                                backend_debug_word <= 32'd0;
`ifdef EMBEDDED_TEST_DISKS
                                if (!drive_selected) begin
                                    status <= 8'h80;
                                    read_active <= 1'b0;
                                    nmi_pending <= 1'b1;
                                end else if (!valid_position) begin
                                    status <= 8'h10;
                                    read_active <= 1'b0;
                                    nmi_pending <= 1'b1;
                                end else begin
                                    status <= 8'h03;
                                    read_active <= 1'b1;
                                end
`else
                                if (!drive_selected ||
                                    (drive0_selected && !backend_present[0]) ||
                                    (drive1_selected && !backend_present[1]) ||
                                    (drive2_selected && !backend_present[2]) ||
                                    !valid_position) begin
                                    status <= !valid_position ? 8'h10 : 8'h80;
                                    read_active <= 1'b0;
                                    read_waiting <= 1'b0;
                                    write_active <= 1'b0;
                                    write_waiting <= 1'b0;
                                    nmi_pending <= 1'b1;
                                end else begin
                                    backend_drive <= drive0_selected ? 2'd0 :
                                                     drive1_selected ? 2'd1 : 2'd2;
                                    backend_track <= track;
                                    backend_sector <= sector;
                                    backend_request_toggle <= ~backend_request_toggle;
                                    status <= 8'h01; // busy; manager will raise DRQ
                                    read_active <= 1'b0;
                                    read_waiting <= 1'b1;
                                end
`endif
                            end
                            4'hA, 4'hB: begin // write single sector
`ifdef EMBEDDED_TEST_DISKS
                                status <= 8'h40;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                                nmi_pending <= 1'b1;
`else
                                if (!drive_selected || !drive0_selected ||
                                    (drive0_selected && !backend_present[0]) ||
                                    (drive1_selected && !backend_present[1]) ||
                                    (drive2_selected && !backend_present[2]) ||
                                    !valid_position) begin
                                    status <= !valid_position ? 8'h10 :
                                              (!drive0_selected && drive_selected) ? 8'h40 : 8'h80;
                                    read_active <= 1'b0;
                                    read_waiting <= 1'b0;
                                    write_active <= 1'b0;
                                    write_waiting <= 1'b0;
                                    nmi_pending <= 1'b1;
                                end else begin
                                    backend_drive <= drive0_selected ? 2'd0 :
                                                     drive1_selected ? 2'd1 : 2'd2;
                                    backend_track <= track;
                                    backend_sector <= sector;
                                    byte_index <= 8'h00;
                                    read_active <= 1'b0;
                                    read_waiting <= 1'b0;
                                    write_active <= 1'b1;
                                    write_waiting <= 1'b0;
                                    first_data_access <= 1'b0;
                                    status <= 8'h03;
                                end
`endif
                            end
                            4'hD: begin // force interrupt
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            default: begin
                                status <= 8'h00;
                                read_active <= 1'b0;
                                read_waiting <= 1'b0;
                                write_active <= 1'b0;
                                write_waiting <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                        endcase
                    end
                endcase
            end
        end
    end

    assign nmi = nmi_pending;
endmodule

`default_nettype wire
