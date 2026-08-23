`timescale 1ns/1ps
`default_nettype none

module cpu_diagnostic_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    always #20 clock = ~clock;

    reg [3:0] divider = 4'd0;
    reg hold = 1'b1;
    wire vma;
    wire [15:0] address;
    wire read_cycle;
    wire [7:0] write_data;
    wire [7:0] ram_data;
    wire [7:0] rom_data;
    wire [7:0] read_data = address[15:12] == 4'hF ? rom_data : ram_data;
    wire ram_write = !hold && vma && !read_cycle && address[15:12] != 4'hF;
    wire [15:0] video_data;

    always @(posedge clock) begin
        if (reset) begin
            divider <= 4'd0;
            hold <= 1'b1;
        end else if (divider == 4'd13) begin
            divider <= 4'd0;
            hold <= 1'b0;
        end else begin
            divider <= divider + 1'b1;
            hold <= 1'b1;
        end
    end

    cpu09 cpu_i (
        .clk(clock), .rst(reset), .vma(vma), .lic_out(), .ifetch(),
        .opfetch(), .ba(), .bs(), .addr(address), .rw(read_cycle),
        .data_out(write_data), .data_in(read_data), .irq(1'b0),
        .firq(1'b0), .nmi(1'b0), .halt(1'b0), .hold(hold)
    );

    coco3_diagnostic_rom rom_i (
        .clock(clock), .address(address[11:0]), .data(rom_data)
    );

    coco3_128k_ram ram_i (
        .clock(clock), .cpu_address({1'b0, address}),
        .cpu_write_data(write_data), .cpu_write_enable(ram_write),
        .cpu_read_data(ram_data), .video_address(20'h00078),
        .video_read_data(video_data)
    );

    initial begin
        repeat (20) @(posedge clock);
        reset <= 1'b0;
        repeat (40000) @(posedge clock);

        if (video_data !== 16'h5043)
            $fatal(1, "CPU/BRAM diagnostic failed: expected CP, got %h", video_data);
        if (ram_i.memory_low[16'h007C] !== 8'h38 ||
            ram_i.memory_high[16'h007C] !== 8'h4B)
            $fatal(1, "CPU/BRAM byte lanes failed near end of first message");
        if (ram_i.memory_low[16'h0168] !== 8'h53 ||
            ram_i.memory_high[16'h0168] !== 8'h54)
            $fatal(1, "CPU/BRAM third message was not written");

        $display("PASS: reset vector, CPU execution, and 128 KiB BRAM byte lanes");
        $finish;
    end
endmodule

`default_nettype wire
