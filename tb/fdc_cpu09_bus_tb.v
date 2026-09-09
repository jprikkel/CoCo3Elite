`timescale 1ns/1ps
`default_nettype none

// End-to-end regression for the cpu09 E/Q service timing and the FDC's
// direct-addressed manager buffer.  The 6809 executes a real disk sequence:
// select drive 0, seek track 17, read sector 3, then store four FF4B bytes.
module fdc_cpu09_bus_tb;
    reg clock = 0, reset = 1;
    wire vma, rw, nmi;
    wire [15:0] address, pc;
    wire [7:0] write_data, read_data, fdc_read_data;
    wire [7:0] buffer_address;
    wire [1:0] backend_drive;
    wire [7:0] backend_track, backend_sector, backend_last_type1;
    wire [31:0] backend_debug_word;
    wire request_toggle;
    reg done_toggle = 0, request_seen = 0;
    reg [7:0] result [0:3];
    reg [7:0] buffer [0:255];
    integer n;

    always #5 clock = ~clock;

    cpu09 cpu_i (
        .clk(clock), .rst(reset), .vma(vma), .lic_out(), .ifetch(),
        .opfetch(), .ba(), .bs(), .addr(address), .rw(rw), .debug_pc(pc),
        .data_out(write_data), .data_in(read_data), .irq(1'b0), .firq(1'b0),
        .nmi(nmi), .halt(1'b0), .hold(1'b0)
    );

    wire io_read = vma && rw && address[15:8] == 8'hff;
    wire io_write = vma && !rw && address[15:8] == 8'hff;
    coco3_fdc fdc_i (
        .clock(clock), .reset(reset), .io_read(io_read), .io_write(io_write),
        .address(address), .write_data(write_data), .read_data(fdc_read_data),
        .nmi(nmi), .backend_present(3'b001), .backend_done_toggle(done_toggle),
        .backend_success(1'b1), .backend_data(buffer[buffer_address]),
        .backend_buffer_address(buffer_address), .backend_drive(backend_drive),
        .backend_track(backend_track), .backend_sector(backend_sector),
        .backend_last_type1(backend_last_type1), .backend_debug_word(backend_debug_word),
        .backend_read_complete_toggle(), .backend_request_toggle(request_toggle)
    );

    // Tiny 6809 monitor program and reset vector.  Data reads are
    // combinational, like the machine's ROM/RAM/FDC multiplexer.
    function [7:0] program_byte;
        input [15:0] a;
        begin
            case (a)
                16'h0000: program_byte=8'h86; 16'h0001: program_byte=8'h09;
                16'h0002: program_byte=8'hb7; 16'h0003: program_byte=8'hff; 16'h0004: program_byte=8'h40;
                16'h0005: program_byte=8'h86; 16'h0006: program_byte=8'h11;
                16'h0007: program_byte=8'hb7; 16'h0008: program_byte=8'hff; 16'h0009: program_byte=8'h49;
                16'h000a: program_byte=8'h86; 16'h000b: program_byte=8'h03;
                16'h000c: program_byte=8'hb7; 16'h000d: program_byte=8'hff; 16'h000e: program_byte=8'h4a;
                16'h000f: program_byte=8'h86; 16'h0010: program_byte=8'h80;
                16'h0011: program_byte=8'hb7; 16'h0012: program_byte=8'hff; 16'h0013: program_byte=8'h48;
                16'h0014: program_byte=8'hb6; 16'h0015: program_byte=8'hff; 16'h0016: program_byte=8'h48;
                // A WD1773 keeps BUSY set during a read.  Disk BASIC waits
                // for DRQ (bit 1), then consumes the data register.
                16'h0017: program_byte=8'h84; 16'h0018: program_byte=8'h02;
                16'h0019: program_byte=8'h27; 16'h001a: program_byte=8'hf9;
                16'h001b: program_byte=8'hb6; 16'h001c: program_byte=8'hff; 16'h001d: program_byte=8'h4b;
                16'h001e: program_byte=8'hb7; 16'h001f: program_byte=8'h01; 16'h0020: program_byte=8'h00;
                16'h0021: program_byte=8'hb6; 16'h0022: program_byte=8'hff; 16'h0023: program_byte=8'h4b;
                16'h0024: program_byte=8'hb7; 16'h0025: program_byte=8'h01; 16'h0026: program_byte=8'h01;
                16'h0027: program_byte=8'hb6; 16'h0028: program_byte=8'hff; 16'h0029: program_byte=8'h4b;
                16'h002a: program_byte=8'hb7; 16'h002b: program_byte=8'h01; 16'h002c: program_byte=8'h02;
                16'h002d: program_byte=8'hb6; 16'h002e: program_byte=8'hff; 16'h002f: program_byte=8'h4b;
                16'h0030: program_byte=8'hb7; 16'h0031: program_byte=8'h01; 16'h0032: program_byte=8'h03;
                16'h0033: program_byte=8'h20; 16'h0034: program_byte=8'hfe;
                16'hfffe: program_byte=8'h00; 16'hffff: program_byte=8'h00;
                default: program_byte=8'h12;
            endcase
        end
    endfunction
    assign read_data = (address >= 16'h0100 && address <= 16'h0103) ? result[address[1:0]] :
                       (address >= 16'hff48 && address <= 16'hff4b) ? fdc_read_data :
                       program_byte(address);

    always @(posedge clock) begin
        if (vma && !rw && address >= 16'h0100 && address <= 16'h0103)
            result[address[1:0]] <= write_data;
        if (request_toggle != request_seen) begin
            request_seen <= request_toggle;
            done_toggle <= request_toggle;
        end
    end

    initial begin
        buffer[0]=8'h5a; buffer[1]=8'h45; buffer[2]=8'h4e; buffer[3]=8'h49;
        for (n=4; n<256; n=n+1) buffer[n]=n;
        repeat (16) @(posedge clock); reset=0;
        repeat (4000) @(posedge clock);
        if (backend_drive!==0 || backend_track!==17 || backend_sector!==3) begin
            $display("FAIL: manager request d=%0d t=%0d s=%0d",backend_drive,backend_track,backend_sector); $finish;
        end
        if ({result[0],result[1],result[2],result[3]}!==32'h5a454e49) begin
            $display("FAIL: cpu09 bytes %02h %02h %02h %02h",result[0],result[1],result[2],result[3]); $finish;
        end
        $display("PASS: cpu09 FDC reads ZENI without a skipped or repeated byte");
        $finish;
    end
endmodule

`default_nettype wire
