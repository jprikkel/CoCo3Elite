`timescale 1ns/1ps
`default_nettype none

module fdc_read_tb;
    reg clock = 0;
    reg reset = 1;
    reg io_read = 0;
    reg io_write = 0;
    reg [15:0] address = 0;
    reg [7:0] write_data = 0;
    wire [7:0] read_data;
    wire nmi;
    reg [7:0] sector_data [0:255];
    integer index;

    always #5 clock = ~clock;

    coco3_fdc dut (
        .clock(clock), .reset(reset), .io_read(io_read),
        .io_write(io_write), .address(address), .write_data(write_data),
        .read_data(read_data), .nmi(nmi)
    );

    task write_register(input [15:0] target, input [7:0] value);
        begin
            @(negedge clock);
            address = target;
            write_data = value;
            io_write = 1;
            @(negedge clock);
            io_write = 0;
        end
    endtask

    task read_register(input [15:0] target, output [7:0] value);
        begin
            @(negedge clock);
            address = target;
            io_read = 1;
            @(posedge clock);
            #1 value = read_data;
            @(negedge clock);
            io_read = 0;
        end
    endtask

    reg [7:0] value;
    initial begin
        repeat (4) @(posedge clock);
        reset = 0;

        // Drive 0, motor on; directory track 17, first directory sector 3.
        write_register(16'hFF40, 8'h09);
        write_register(16'hFF49, 8'd17);
        write_register(16'hFF4A, 8'd3);
        write_register(16'hFF48, 8'h80);
        repeat (3) @(posedge clock);

        read_register(16'hFF48, value);
        if (value !== 8'h03) begin
            $display("FAIL: read command status=%02h", value);
            $finish;
        end

        // Model the cpu09 bus value becoming visible to the peripheral one
        // enable before the read value is consumed by Disk BASIC.
        read_register(16'hFF4B, value);

        for (index = 0; index < 256; index = index + 1)
            read_register(16'hFF4B, sector_data[index]);

        if (!nmi) begin
            $display("FAIL: no completion NMI");
            $finish;
        end
        if ({sector_data[0], sector_data[1], sector_data[2], sector_data[3],
             sector_data[4], sector_data[5], sector_data[6], sector_data[7]} !==
            64'h5350414345202020) begin
            $display("FAIL: drive 0 INTRUDERS directory bytes are incorrect");
            $finish;
        end
        if ({sector_data[8], sector_data[9], sector_data[10]} !== 24'h424153) begin
            $display("FAIL: drive 0 INTRUDERS extension bytes are incorrect");
            $finish;
        end

        read_register(16'hFF48, value);
        if (value !== 8'h00 || nmi) begin
            $display("FAIL: completion status=%02h nmi=%0d", value, nmi);
            $finish;
        end

        write_register(16'hFF48, 8'hA0);
        if (!nmi) begin
            $display("FAIL: write-protect completion NMI missing");
            $finish;
        end
        read_register(16'hFF48, value);
        if (value !== 8'h40) begin
            $display("FAIL: write-protect status=%02h", value);
            $finish;
        end

        // Select drive 1 and verify that its directory comes from the second
        // image rather than aliasing drive 0.
        write_register(16'hFF40, 8'h0A);
        write_register(16'hFF49, 8'd17);
        write_register(16'hFF4A, 8'd3);
        write_register(16'hFF48, 8'h80);
        repeat (3) @(posedge clock);
        read_register(16'hFF48, value);
        if (value !== 8'h03) begin
            $display("FAIL: drive 1 read command status=%02h", value);
            $finish;
        end
        read_register(16'hFF4B, value);
        for (index = 0; index < 256; index = index + 1)
            read_register(16'hFF4B, sector_data[index]);

        if (!nmi) begin
            $display("FAIL: drive 1 completion NMI missing");
            $finish;
        end
        if ({sector_data[0], sector_data[1], sector_data[2], sector_data[3],
             sector_data[4], sector_data[5], sector_data[6], sector_data[7]} !==
            64'h444147474F524154) begin
            $display("FAIL: drive 1 directory name bytes are incorrect");
            $finish;
        end
        if ({sector_data[8], sector_data[9], sector_data[10]} !== 24'h42494E) begin
            $display("FAIL: drive 1 directory extension bytes are incorrect");
            $finish;
        end

        $display("PASS: read drive 0 INTRUDERS and drive 1 DAGGORAT directories; reject writes");
        $finish;
    end
endmodule

`default_nettype wire
