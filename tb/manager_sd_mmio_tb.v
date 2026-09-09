`timescale 1ns/1ps
`default_nettype none
module manager_sd_mmio_tb;
    reg clock = 0, reset = 1;
    always #5 clock = ~clock;
    reg awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg [3:0] wstrb = 4'hf;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire uart_tx, sd_cs_n, sd_sck, sd_mosi;
    integer rising_edges = 0;
    always @(posedge sd_sck) rising_edges = rising_edges + 1;

    manager_sd_mmio #(.UART_CLKS_PER_BIT(2)) dut (
        .clock(clock), .reset(reset), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_awaddr(awaddr), .axi_wvalid(wvalid), .axi_wready(wready), .axi_wdata(wdata),
        .axi_wstrb(wstrb), .axi_bvalid(bvalid), .axi_bready(bready), .axi_bresp(bresp),
        .axi_arvalid(arvalid), .axi_arready(arready), .axi_araddr(araddr), .axi_rvalid(rvalid),
        .axi_rready(rready), .axi_rdata(rdata), .axi_rresp(rresp), .uart_tx(uart_tx),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(1'b1)
    );

    task write32;
        input [31:0] address;
        input [31:0] value;
        begin
            // Drive on the falling edge so the DUT sees stable valid signals
            // at the next rising edge; this avoids a TB/DUT race.
            @(negedge clock);
            awaddr = address; wdata = value; awvalid = 1; wvalid = 1;
            @(posedge clock);
            #1 awvalid = 0; wvalid = 0;
            while (!bvalid) @(posedge clock);
            @(posedge clock);
        end
    endtask
    task read32;
        input [31:0] address;
        output [31:0] value;
        begin
            @(negedge clock);
            araddr = address; arvalid = 1;
            @(posedge clock); #1 arvalid = 0;
            while (!rvalid) @(posedge clock);
            value = rdata;
            @(posedge clock);
        end
    endtask
    reg [31:0] value;
    initial begin
        #200000;
        $fatal(1, "manager SD MMIO test timed out");
    end
    initial begin
        repeat (4) @(posedge clock);
        reset = 0;
        $display("configuring SPI");
        write32(32'h80000100, 32'h00000200); // active CS, divider=2
        rising_edges = 0;
        $display("starting transfer");
        write32(32'h80000104, 32'ha5);
        if (rising_edges != 8) $fatal(1, "SPI store ACK arrived after %0d rising edges, expected 8", rising_edges);
        read32(32'h80000108, value);
        if (value[7:0] != 8'hff) $fatal(1, "SPI receive mismatch: %h", value[7:0]);
        if (sd_cs_n !== 1'b0) $fatal(1, "SPI CS changed during transfer");
        $display("PASS: manager SD MMIO completes one byte before its AXI response");
        $finish;
    end
endmodule
`default_nettype wire
