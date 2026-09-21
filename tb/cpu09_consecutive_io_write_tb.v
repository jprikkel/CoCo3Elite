`timescale 1ns/1ps
`default_nettype none

// Reproduce Galactus's GIME initialization sequence at the cpu09 wrapper.
// Immediate loads followed by extended stores must present matching address
// and data on the one-clock VMA service pulse.
module cpu09_consecutive_io_write_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg [4:0] divider = 5'd0;
    reg hold = 1'b1;
    wire vma, read_cycle;
    wire [15:0] address;
    wire [7:0] write_data;
    integer write_count = 0;

    always #5 clock = ~clock;

    always @(posedge clock) begin
        if (reset) begin
            divider <= 5'd0;
            hold <= 1'b1;
        end else if (divider == 5'd6) begin
            divider <= 5'd0;
            hold <= 1'b0;
        end else begin
            divider <= divider + 1'b1;
            hold <= 1'b1;
        end
    end

    function [7:0] program_byte;
        input [15:0] a;
        begin
            case (a)
                16'h0000:program_byte=8'h86; 16'h0001:program_byte=8'h44;
                16'h0002:program_byte=8'hb7; 16'h0003:program_byte=8'hff; 16'h0004:program_byte=8'h90;
                16'h0005:program_byte=8'h86; 16'h0006:program_byte=8'h08;
                16'h0007:program_byte=8'hb7; 16'h0008:program_byte=8'hff; 16'h0009:program_byte=8'ha4;
                16'h000a:program_byte=8'h4c;
                16'h000b:program_byte=8'hb7; 16'h000c:program_byte=8'hff; 16'h000d:program_byte=8'ha5;
                16'h000e:program_byte=8'h4c;
                16'h000f:program_byte=8'hb7; 16'h0010:program_byte=8'hff; 16'h0011:program_byte=8'ha6;
                16'h0012:program_byte=8'h4c;
                16'h0013:program_byte=8'hb7; 16'h0014:program_byte=8'hff; 16'h0015:program_byte=8'ha7;
                16'h0016:program_byte=8'h86; 16'h0017:program_byte=8'h80;
                16'h0018:program_byte=8'hb7; 16'h0019:program_byte=8'hff; 16'h001a:program_byte=8'h98;
                16'h001b:program_byte=8'h86; 16'h001c:program_byte=8'h1e;
                16'h001d:program_byte=8'hb7; 16'h001e:program_byte=8'hff; 16'h001f:program_byte=8'h99;
                16'h0020:program_byte=8'h86; 16'h0021:program_byte=8'h20;
                16'h0022:program_byte=8'hb7; 16'h0023:program_byte=8'hff; 16'h0024:program_byte=8'h9d;
                16'h0025:program_byte=8'h7f; 16'h0026:program_byte=8'hff; 16'h0027:program_byte=8'h9e;
                16'h0028:program_byte=8'h20; 16'h0029:program_byte=8'hfe;
                16'hfffe:program_byte=8'h00; 16'hffff:program_byte=8'h00;
                default:program_byte=8'h12;
            endcase
        end
    endfunction

    wire [7:0] read_data = program_byte(address);

    cpu09 cpu_i (
        .clk(clock), .rst(reset), .vma(vma), .lic_out(), .ifetch(),
        .opfetch(), .ba(), .bs(), .debug_pc(), .addr(address),
        .rw(read_cycle), .data_out(write_data), .data_in(read_data),
        .irq(1'b0), .firq(1'b0), .nmi(1'b0), .halt(1'b0), .hold(hold)
    );

    task expect_write;
        input [15:0] wanted_address;
        input [7:0] wanted_data;
        begin
            if (address !== wanted_address || write_data !== wanted_data)
                $fatal(1, "write %0d got %04h=%02h expected %04h=%02h",
                       write_count, address, write_data,
                       wanted_address, wanted_data);
        end
    endtask

    always @(posedge clock) begin
        if (!hold && vma && !read_cycle) begin
            case (write_count)
                0:expect_write(16'hff90,8'h44);
                1:expect_write(16'hffa4,8'h08);
                2:expect_write(16'hffa5,8'h09);
                3:expect_write(16'hffa6,8'h0a);
                4:expect_write(16'hffa7,8'h0b);
                5:expect_write(16'hff98,8'h80);
                6:expect_write(16'hff99,8'h1e);
                7:expect_write(16'hff9d,8'h20);
                8:expect_write(16'hff9e,8'h00);
                default:$fatal(1,"unexpected extra write %04h=%02h",address,write_data);
            endcase
            write_count <= write_count + 1;
        end
    end

    initial begin
        repeat (16) @(posedge clock);
        reset = 1'b0;
        repeat (30000) @(posedge clock);
        if (write_count != 9)
            $fatal(1,"saw %0d writes; expected 9",write_count);
        $display("PASS: consecutive cpu09 GIME writes preserve address/data pairing");
        $finish;
    end
endmodule

`default_nettype wire
