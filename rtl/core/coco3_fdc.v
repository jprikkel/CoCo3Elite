`timescale 1ns/1ps
`default_nettype none

// Minimal read-only WD1773-compatible interface for the standard CoCo disk
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
    output wire        nmi
);
    reg [7:0] drive_latch;
    reg [7:0] status;
    reg [7:0] track;
    reg [7:0] sector;
    reg [7:0] data_register;
    reg [7:0] byte_index;
    reg       read_active;
    reg       first_data_access;
    reg       nmi_pending;

`ifdef EMBEDDED_TEST_DISKS
    wire drive0_selected = drive_latch[0];
    wire drive1_selected = !drive_latch[0] && drive_latch[1];
    wire drive_selected = drive0_selected || drive1_selected;
    wire valid_position = track < 8'd35 && sector >= 8'd1 && sector <= 8'd18;
    wire [9:0] linear_sector = ({2'b00, track} << 4) +
                               ({2'b00, track} << 1) +
                               {2'b00, sector} - 10'd1;
    wire [17:0] image_address = {linear_sector, 8'b0} + byte_index;
    wire [7:0] drive0_data;
    wire [7:0] drive1_data;
    wire [7:0] image_data = drive1_selected ? drive1_data : drive0_data;

    (* dont_touch = "yes" *)
    coco3_disk_image #(.IMAGE_FILE("build/disks/cashman.mem")) drive0_image_i (
        .clock(clock), .address(image_address), .data(drive0_data)
    );

    (* dont_touch = "yes" *)
    coco3_disk_image #(.IMAGE_FILE("build/disks/mudpies.mem")) drive1_image_i (
        .clock(clock), .address(image_address), .data(drive1_data)
    );
`endif

    wire data_read = io_read && address == 16'hFF4B;
    wire status_read = io_read && address == 16'hFF48;

    always @* begin
        case (address)
            16'hFF40: read_data = drive_latch;
            16'hFF48: read_data = status;
            16'hFF49: read_data = track;
            16'hFF4A: read_data = sector;
`ifdef EMBEDDED_TEST_DISKS
            16'hFF4B: read_data = read_active ? image_data : data_register;
`else
            16'hFF4B: read_data = data_register;
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
            first_data_access <= 1'b0;
            nmi_pending <= 1'b0;
        end else begin
            if (status_read)
                nmi_pending <= 1'b0;

            if (data_read && read_active) begin
                // cpu09 holds each bus value between enable cycles.  The
                // first FF4B value is consequently visible to this peripheral
                // one enable before Disk BASIC consumes it.  Treat that first
                // observation as a prefetch so byte zero is not skipped.
                if (first_data_access) begin
                    first_data_access <= 1'b0;
                end else if (byte_index == 8'hFF) begin
                    read_active <= 1'b0;
                    status <= 8'h00;
                    nmi_pending <= 1'b1;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end

            if (io_write) begin
                case (address)
                    16'hFF40: drive_latch <= write_data;
                    16'hFF49: track <= write_data;
                    16'hFF4A: sector <= write_data;
                    16'hFF4B: data_register <= write_data;
                    16'hFF48: begin
                        nmi_pending <= 1'b0;
                        case (write_data[7:4])
                            4'h0: begin // restore
                                track <= 8'h00;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h1: begin // seek to data register
                                track <= data_register;
                                status <= 8'h00;
                                read_active <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            4'h8, 4'h9: begin // read single sector
                                byte_index <= 8'h00;
                                first_data_access <= 1'b1;
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
                                status <= 8'h80; // SD backend not yet connected
                                read_active <= 1'b0;
                                nmi_pending <= 1'b1;
`endif
                            end
                            4'hA, 4'hB: begin // write sector: read-only media
                                status <= 8'h40;
                                read_active <= 1'b0;
                                first_data_access <= 1'b0;
                                nmi_pending <= 1'b1;
                            end
                            4'hD: begin // force interrupt
                                status <= 8'h00;
                                read_active <= 1'b0;
                                first_data_access <= 1'b0;
                            end
                            default: begin
                                status <= 8'h00;
                                read_active <= 1'b0;
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
