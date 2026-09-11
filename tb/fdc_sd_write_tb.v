`timescale 1ns/1ps
`default_nettype none

// Verify the write-side ownership contract independently of the SD card:
// every CPU FF4B store is presented once to the cache port, and completion
// remains busy until firmware acknowledges the flush toggle.
module fdc_sd_write_tb;
    reg clock=0, reset=1, io_read=0, io_write=0;
    reg [15:0] address=0; reg [7:0] write_data=0;
    reg write_done_toggle=0, write_success=0;
    wire [7:0] read_data, buffer_address, backend_write_data;
    wire nmi, backend_write_strobe, write_complete_toggle;
    wire [1:0] drive; wire [7:0] track, sector;
    reg [7:0] captured[0:255]; integer n;
    always #5 clock=~clock;
    always @(posedge clock) if(backend_write_strobe) captured[buffer_address] <= backend_write_data;
    coco3_fdc dut(
        .clock(clock),.reset(reset),.io_read(io_read),.io_write(io_write),.address(address),.write_data(write_data),
        .read_data(read_data),.nmi(nmi),.backend_present(3'b001),.backend_done_toggle(1'b0),.backend_success(1'b0),
        .backend_write_done_toggle(write_done_toggle),.backend_write_success(write_success),.backend_data(8'h00),
        .backend_buffer_address(buffer_address),.backend_drive(drive),.backend_track(track),.backend_sector(sector),
        .backend_write_strobe(backend_write_strobe),.backend_write_data(backend_write_data),
        .backend_write_complete_toggle(write_complete_toggle)
    );
    task wr(input [15:0] a,input [7:0] d); begin
        @(negedge clock); address=a; write_data=d; io_write=1;
        @(negedge clock); io_write=0;
    end endtask
    reg [7:0] status;
    initial begin
        repeat(4)@(posedge clock); reset=0;
        wr(16'hff40,8'h01); wr(16'hff49,8'd3); wr(16'hff4a,8'd7); wr(16'hff48,8'ha0);
        for(n=0;n<256;n=n+1) wr(16'hff4b,n[7:0]^8'ha5);
        repeat(2)@(posedge clock);
        if(write_complete_toggle!==1 || drive!==0 || track!==3 || sector!==7) begin
            $display("FAIL: bad write completion metadata"); $finish;
        end
        for(n=0;n<256;n=n+1) if(captured[n] !== (n[7:0]^8'ha5)) begin
            $display("FAIL: cache byte %0d is %02h",n,captured[n]); $finish;
        end
        @(negedge clock); address=16'hff48; io_read=1; #1 status=read_data; @(negedge clock);io_read=0;
        if(status!==8'h01) begin $display("FAIL: write was not held busy (%02h)",status);$finish;end
        write_success=1; write_done_toggle=write_complete_toggle;
        repeat(2)@(posedge clock);
        if(!nmi) begin $display("FAIL: write completion did not raise NMI");$finish;end
        @(negedge clock); address=16'hff48; io_read=1; #1 status=read_data; @(negedge clock);io_read=0;
        if(status!==8'h00) begin $display("FAIL: write acknowledgement missing (%02h)",status);$finish;end
        $display("PASS: FDC write cache transfer and flush acknowledgement"); $finish;
    end
endmodule

`default_nettype wire
