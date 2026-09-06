`timescale 1ns/1ps
module gime_timer_tb;
 reg clock=0, reset=1, fast=1, wr_msb=0, wr_lsb=0;
 reg hsync=1; reg [7:0] data=0; wire [3:0] msb; wire [7:0] lsb; wire blink;
 always #5 clock=~clock;
 coco3_gime_timer #(.FAST_DIVIDE(2)) dut(
  .clock(clock),.reset(reset),.hsync(hsync),.fast_select(fast),
  .write_msb(wr_msb),.write_lsb(wr_lsb),.write_data(data),
  .timer_msb(msb),.timer_lsb(lsb),.blink(blink));
 initial begin
  repeat(2) @(posedge clock); reset=0;
  data=8'h02; wr_lsb=1; @(posedge clock); #1; wr_lsb=0;
  data=8'h00; wr_msb=1; @(posedge clock); #1; wr_msb=0;
  if(msb!==0 || lsb!==8'h02) $fatal(1,"FAIL: timer readback");
  wait(blink==0); $display("PASS: GIME timer toggled text blink"); $finish;
 end
 initial begin repeat(40) @(posedge clock); $fatal(1,"FAIL: blink timeout"); end
endmodule
