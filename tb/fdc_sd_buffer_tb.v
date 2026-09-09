`timescale 1ns/1ps
`default_nettype none

// Exercise the FDC against the manager's direct-addressed 256-byte read port.
// This catches a byte change at the 6809/FDC service edge that the optional
// synchronous BRAM image cannot expose.
module fdc_sd_buffer_tb;
    reg clock=0, reset=1, io_read=0, io_write=0;
    reg [15:0] address=0; reg [7:0] write_data=0;
    reg done_toggle=0, success=0; reg [7:0] buffer[0:255], buffer_data;
    wire [7:0] buffer_address, read_data; wire nmi, request_toggle;
    wire [1:0] drive; wire [7:0] track, sector;
    integer n; reg request_seen=0;
    always #5 clock=~clock;
    always @* buffer_data = buffer[buffer_address];
    coco3_fdc dut(.clock(clock),.reset(reset),.io_read(io_read),.io_write(io_write),.address(address),.write_data(write_data),.read_data(read_data),.nmi(nmi),.backend_present(3'b001),.backend_done_toggle(done_toggle),.backend_success(success),.backend_data(buffer_data),.backend_buffer_address(buffer_address),.backend_drive(drive),.backend_track(track),.backend_sector(sector),.backend_request_toggle(request_toggle));
    task wr(input[15:0] a,input[7:0] d);begin @(negedge clock);address=a;write_data=d;io_write=1;@(negedge clock);io_write=0;end endtask
    // The 6809 consumes FF4B on falling E; the FDC service edge that
    // advances its byte address follows it.  Sample before that service edge.
    task rd(input[15:0] a,output[7:0] d);begin @(negedge clock);address=a;io_read=1;#1 d=read_data;@(posedge clock);@(negedge clock);io_read=0;end endtask
    reg [7:0] value; reg [7:0] got[0:3];
    initial begin
        // First four bytes of ZENIX.DSK's track 0 sector 2.
        buffer[0]=8'h8d;buffer[1]=8'h0b;buffer[2]=8'h0c;buffer[3]=8'h16;
        for(n=4;n<256;n=n+1)buffer[n]=n;
        repeat(4)@(posedge clock);reset=0;
        wr(16'hff40,8'h09);wr(16'hff49,0);
        // Disk BASIC reaches the directory through 17 WD1773 STEP-INs.
        for(n=0;n<17;n=n+1)wr(16'hff48,8'h50);
        wr(16'hff4a,2);wr(16'hff48,8'h80);
        repeat(3)@(posedge clock);
        if(request_toggle!==1 || drive!==0 || track!==17 || sector!==2)begin $display("FAIL: bad manager request");$finish;end
        success=1;done_toggle=request_toggle;
        repeat(2)@(posedge clock);rd(16'hff48,value);if(value!==8'h03)begin $display("FAIL: status %02h",value);$finish;end
        rd(16'hff4b,value); // cpu09's FDC prefetch observation
        for(n=0;n<4;n=n+1)rd(16'hff4b,got[n]);
        if({got[0],got[1],got[2],got[3]}!==32'h8d0b0c16)begin $display("FAIL: bytes %02h %02h %02h %02h",got[0],got[1],got[2],got[3]);$finish;end
        $display("PASS: SD manager direct buffer preserves FDC byte 0");$finish;
    end
endmodule
`default_nettype wire
