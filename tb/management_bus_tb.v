`timescale 1ns/1ps
// Tests the MCS IO adapter with a bus-functional substitute, not CPU execution.
module management_bus_tb;
    reg clk = 0, reset = 1;
    always #10 clk = !clk;
    wire cs_n, sck, mosi, reset_n, vbus, irq, uart;
    management_prototype dut (
        .clk_50mhz(clk), .reset(reset), .uart_tx(uart),
        .usb_cs_n(cs_n), .usb_sck(sck), .usb_mosi(mosi), .usb_miso(1'b1),
        .usb_int_n(1'b1), .usb_reset_n(reset_n), .usb_vbus_en(vbus),
        .usb_overcurrent_n(1'b1), .usb_irq_pending(irq)
    );
    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
        wait(dut.cpu.finished);
        if (!cs_n || sck || vbus || !reset_n)
            $fatal(1, "FAIL: management adapter changed safe outputs");
        $display("PASS: management_bus_tb");
        $finish;
    end
    initial begin #100000; $fatal(1, "FAIL: MCS IO adapter timeout"); end
endmodule

// Deliberately included only by test_usb_host_spi.ps1. Actual synthesis uses
// the generated AMD IP, never this test double. MCS emits one-cycle strobes
// and samples the reply on a rising clock with IO_ready asserted.
module management_cpu (
    input wire Clk, Reset,
    output wire IO_addr_strobe,
    output reg [31:0] IO_address = 0,
    output reg [3:0] IO_byte_enable = 15,
    input wire [31:0] IO_read_data,
    output reg IO_read_strobe = 0,
    input wire IO_ready,
    output reg [31:0] IO_write_data = 0,
    output reg IO_write_strobe = 0,
    output wire UART_txd
);
    assign IO_addr_strobe = IO_read_strobe || IO_write_strobe;
    assign UART_txd = 1;
    reg finished = 0;
    task transfer;
        input writing;
        input [31:0] address, data;
        output [31:0] result;
        integer guard;
        begin
            @(negedge Clk);
            IO_address = address; IO_write_data = data;
            IO_write_strobe = writing; IO_read_strobe = !writing;
            @(negedge Clk); IO_write_strobe = 0; IO_read_strobe = 0;
            guard = 0;
            @(posedge Clk);
            while (!IO_ready && guard < 10) begin
                @(posedge Clk); guard = guard + 1;
            end
            if (!IO_ready) $fatal(1, "FAIL: MCS reply timeout");
            result = IO_read_data;
            @(negedge Clk);
            if (IO_ready) $fatal(1, "FAIL: repeated MCS reply");
        end
    endtask
    reg [31:0] value;
    initial begin
        wait(!Reset);
        transfer(0, 32'hc0000000, 0, value);
        if (value != 32'h55425331) $fatal(1, "FAIL: mapped ID response");
        transfer(1, 32'hc0000008, 2, value);
        transfer(0, 32'hc0000008, 0, value);
        if (value != 2) $fatal(1, "FAIL: mapped control write/read");
        transfer(1, 32'hc0000108, 32'h80000000, value);
        transfer(0, 32'hc0000008, 0, value);
        if (value != 2) $fatal(1, "FAIL: adjacent bank aliases control");
        transfer(0, 32'hc0000100, 0, value);
        if (value != 0) $fatal(1, "FAIL: unmapped bank response");
        IO_byte_enable = 1;
        transfer(1, 32'hc0000008, 0, value);
        IO_byte_enable = 15;
        transfer(0, 32'hc0000004, 0, value);
        if (!value[2]) $fatal(1, "FAIL: byte enables not passed through");
        finished = 1;
    end
endmodule
