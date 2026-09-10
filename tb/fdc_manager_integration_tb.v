`timescale 1ns/1ps
`default_nettype none

// End-to-end regression for the exact failure seen on hardware: Disk BASIC
// reads track 17 sector 2 (GAT), then immediately reads sector 3 (directory).
// Firmware is represented by AXI writes through the real manager MMIO.  The
// real FDC then consumes the published bank through its normal byte address.
module fdc_manager_integration_tb;
    reg clock=0, reset=1;
    always #5 clock=~clock;

    reg awvalid=0,wvalid=0,bready=1,arvalid=0,rready=1;
    reg [31:0] awaddr=0,wdata=0,araddr=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [31:0] rdata;
    wire [1:0] bresp,rresp;

    reg io_read=0,io_write=0;
    reg [15:0] address=0;
    reg [7:0] write_data=0;
    wire [7:0] fdc_read_data,buffer_data,buffer_address,write_buffer_data;
    wire nmi,request_toggle,done_toggle,success;
    wire write_done_toggle,write_success,write_strobe,write_complete_toggle;
    wire [1:0] backend_drive;
    wire [7:0] backend_track,backend_sector,backend_last_type1;
    wire [31:0] backend_debug_word,backend_completed_debug_word;
    wire backend_read_complete_toggle;
    wire [2:0] present;
    integer n;
    reg [7:0] value;

    manager_sd_mmio #(.UART_CLKS_PER_BIT(2)) manager_i(
        .clock(clock),.reset(reset),
        .axi_awvalid(awvalid),.axi_awready(awready),.axi_awaddr(awaddr),
        .axi_wvalid(wvalid),.axi_wready(wready),.axi_wdata(wdata),.axi_wstrb(4'hf),
        .axi_bvalid(bvalid),.axi_bready(bready),.axi_bresp(bresp),
        .axi_arvalid(arvalid),.axi_arready(arready),.axi_araddr(araddr),
        .axi_rvalid(rvalid),.axi_rready(rready),.axi_rdata(rdata),.axi_rresp(rresp),
        .uart_tx(),.sd_cs_n(),.sd_sck(),.sd_mosi(),.sd_miso(1'b1),
        .fdc_drive(backend_drive),.fdc_track(backend_track),.fdc_sector(backend_sector),
        .fdc_last_type1(backend_last_type1),.fdc_debug_word(backend_debug_word),
        .fdc_completed_debug_word(backend_completed_debug_word),
        .fdc_read_complete_toggle(backend_read_complete_toggle),
        .fdc_write_complete_toggle(write_complete_toggle),
        .fdc_request_toggle(request_toggle),.fdc_buffer_address(buffer_address),
        .fdc_buffer_data(buffer_data),.fdc_write_strobe(write_strobe),
        .fdc_write_data(write_buffer_data),.fdc_done_toggle(done_toggle),
        .fdc_success(success),.fdc_write_done_toggle(write_done_toggle),
        .fdc_write_success(write_success),.fdc_present(present),.manager_ready()
    );

    coco3_fdc fdc_i(
        .clock(clock),.reset(reset),.io_read(io_read),.io_write(io_write),
        .address(address),.write_data(write_data),.read_data(fdc_read_data),.nmi(nmi),
        .backend_present(present),.backend_done_toggle(done_toggle),
        .backend_success(success),.backend_write_done_toggle(write_done_toggle),
        .backend_write_success(write_success),.backend_data(buffer_data),
        .backend_buffer_address(buffer_address),.backend_drive(backend_drive),
        .backend_track(backend_track),.backend_sector(backend_sector),
        .backend_last_type1(backend_last_type1),.backend_debug_word(backend_debug_word),
        .backend_completed_debug_word(backend_completed_debug_word),
        .backend_read_complete_toggle(backend_read_complete_toggle),
        .backend_write_strobe(write_strobe),.backend_write_data(write_buffer_data),
        .backend_write_complete_toggle(write_complete_toggle),
        .backend_request_toggle(request_toggle)
    );

    task axi_write;
        input [31:0] a,input_value;
        begin
            @(negedge clock); awaddr=a;wdata=input_value;awvalid=1;wvalid=1;
            @(posedge clock); #1 awvalid=0;wvalid=0;
            while(!bvalid)@(posedge clock);
            @(posedge clock);
        end
    endtask
    task fdc_write;
        input [15:0] a; input [7:0] d;
        begin
            @(negedge clock);address=a;write_data=d;io_write=1;
            @(posedge clock);@(negedge clock);io_write=0;
        end
    endtask
    task fdc_read;
        input [15:0] a; output [7:0] d;
        begin
            @(negedge clock);address=a;io_read=1;#1 d=fdc_read_data;
            @(posedge clock);@(negedge clock);io_read=0;
        end
    endtask
    task publish_sector;
        input [7:0] xor_value;
        begin
            axi_write(32'h80000208,0);
            for(n=0;n<256;n=n+1)
                axi_write(32'h8000020c,n[7:0]^xor_value);
            axi_write(32'h80000210,1);
            while(done_toggle!==request_toggle)@(posedge clock);
            if(!success)$fatal(1,"manager rejected complete sector");
        end
    endtask
    task consume_sector;
        input [7:0] xor_value;
        begin
            fdc_read(16'hff48,value);
            if(value!==8'h03)$fatal(1,"FDC status %02h before data",value);
            fdc_read(16'hff4b,value); // cpu09 prefetch/service observation
            for(n=0;n<256;n=n+1)begin
                fdc_read(16'hff4b,value);
                if(value!==(n[7:0]^xor_value))
                    $fatal(1,"byte %0d is %02h expected %02h",n,value,n[7:0]^xor_value);
            end
        end
    endtask

    initial begin
        #500000;$fatal(1,"FDC/manager integration test timed out");
    end
    initial begin
        repeat(5)@(posedge clock);reset=0;
        axi_write(32'h80000214,32'h00000101);
        fdc_write(16'hff40,8'h09);
        fdc_write(16'hff49,8'h11);

        fdc_write(16'hff4a,8'h02);
        fdc_write(16'hff48,8'h80);
        while(done_toggle===request_toggle)@(posedge clock);
        publish_sector(8'ha5);
        consume_sector(8'ha5);

        fdc_write(16'hff4a,8'h03);
        fdc_write(16'hff48,8'h80);
        while(done_toggle===request_toggle)@(posedge clock);
        publish_sector(8'h5a);
        consume_sector(8'h5a);

        $display("PASS: manager/FDC publishes distinct back-to-back GAT and directory sectors");
        $finish;
    end
endmodule
`default_nettype wire
