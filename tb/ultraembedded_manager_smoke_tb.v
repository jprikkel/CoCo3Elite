`timescale 1ns/1ps
`default_nettype none

module ultraembedded_manager_smoke_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    wire boot_done, magic_seen;
    wire [31:0] magic_value;

    ultraembedded_manager_smoke dut (
        .clock(clock), .reset(reset), .boot_done(boot_done),
        .magic_seen(magic_seen), .magic_value(magic_value)
    );

    always #10 clock = ~clock;

    initial begin
        #100 reset = 1'b0;
        wait (boot_done);
        wait (magic_seen);
        if (magic_value !== 32'h00000053) begin
            $display("FAIL: RV32IM magic write was %08x", magic_value);
            $finish;
        end
        $display("PASS: UltraEmbedded RV32IM booted from TCM and wrote management MMIO");
        #40 $finish;
    end

    initial begin
        #200000;
        $display("FAIL: UltraEmbedded management smoke timeout");
        $finish;
    end
endmodule

`default_nettype wire
