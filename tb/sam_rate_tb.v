`timescale 1ns/1ps
module sam_rate_tb;
 reg clock=0, reset=1, turbo=0;
 integer releases;
 always #5 clock=~clock;
 coco3_boot_machine dut(
  .clock(clock),.reset(reset),.cpu_fast_mode(turbo),.cpu_halt(1'b0),
  .diagnostic_cartridge_enabled(1'b0),.keyboard_keys(56'b0),
  .keyboard_shift(1'b0),.keyboard_shift_override(1'b0),
  .joystick_left_x(6'd32),.joystick_left_y(6'd32),.joystick_left_fire(1'b0),
  .joystick_right_x(6'd32),.joystick_right_y(6'd32),.joystick_right_fire(1'b0),
  .sd_status(8'h0),.sd_detail(8'h0),.video_hsync(1'b1),
  .video_vsync(1'b1),.video_address(20'h0));

 task write_strobe;
  input [15:0] target;
  begin
   force dut.address=target; force dut.vma=1'b1;
   force dut.read_cycle=1'b0; force dut.hold=1'b0;
   force dut.write_data=8'h00;
   @(posedge clock); #1;
   release dut.address; release dut.vma; release dut.read_cycle;
   release dut.hold; release dut.write_data;
  end
 endtask

 task count_releases;
  output integer releases;
  integer i;
  begin
   releases=0;
   for(i=0;i<140;i=i+1) begin
    @(negedge clock);
    if(!dut.hold) releases=releases+1;
   end
  end
 endtask

 initial begin
  repeat(2) @(posedge clock); reset=0; #1;
  if(dut.sam_fast_mode!==0) $fatal(1,"FAIL: SAM rate did not reset to normal");
  write_strobe(16'hFFD9);
  if(dut.sam_fast_mode!==1) $fatal(1,"FAIL: FFD9 did not select fast mode");
  count_releases(releases);
  if(releases<39 || releases>41)
   $fatal(1,"FAIL: fast phase cadence got %0d releases, expected about 40",releases);
  write_strobe(16'hFFD8);
  if(dut.sam_fast_mode!==0) $fatal(1,"FAIL: FFD8 did not select normal mode");
  count_releases(releases);
  if(releases<19 || releases>21)
   $fatal(1,"FAIL: normal phase cadence got %0d releases, expected about 20",releases);
  turbo=1; #1;
  if(!(turbo || dut.sam_fast_mode)) $fatal(1,"FAIL: board turbo override");
  count_releases(releases);
  if(releases<39 || releases>41)
   $fatal(1,"FAIL: turbo phase cadence got %0d releases, expected about 40",releases);
  $display("PASS: SAM FFD8/FFD9 normal/fast strobes and board turbo override");
  $finish;
 end
endmodule
