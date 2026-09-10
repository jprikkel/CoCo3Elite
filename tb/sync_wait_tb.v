`timescale 1ns/1ps
module sync_wait_tb;
 reg clock=0, reset=1, vsync=1, turbo=0;
 reg [7:0] program_data[0:255];
 wire [7:0] injected_rom = dut.address==16'hfffe ? 8'h80 :
                           dut.address==16'hffff ? 8'h00 : program_data[dut.address[7:0]];
 integer stage=0;
 always #5 clock=~clock;
 coco3_boot_machine dut(.clock(clock),.reset(reset),.cpu_fast_mode(turbo),.cpu_halt(1'b0),
 .diagnostic_cartridge_enabled(1'b0),.keyboard_keys(56'b0),
 .keyboard_shift(1'b0),.keyboard_shift_override(1'b0),
 .joystick_left_x(6'd32),.joystick_left_y(6'd32),.joystick_left_fire(1'b0),
 .joystick_right_x(6'd32),.joystick_right_y(6'd32),.joystick_right_fire(1'b0),
 .sd_status(8'd0),.sd_detail(8'd0),.video_hsync(1'b1),.video_vsync(vsync),.video_address(20'd0));
 initial begin
  $readmemh("sync_wait.mem",program_data);
  force dut.rom_data=injected_rom;
  if($test$plusargs("FAST")) turbo=1;
  repeat(12) @(negedge clock);
  reset=0;
  wait(dut.diagnostic_probe_address==1);
  stage=1;
  // Pulse ends while CPU is in its delay loop; a later poll must see it.
  repeat(10) @(negedge clock); vsync=0;
  repeat(10) @(negedge clock); vsync=1;
  wait(dut.diagnostic_probe_address==2);
  stage=2;
  repeat(10) @(negedge clock); vsync=0;
  repeat(10) @(negedge clock); vsync=1;
  wait(dut.diagnostic_probe_address==13'hfe || dut.diagnostic_probe_address==13'hee);
  if(dut.diagnostic_probe_address==13'hee) $fatal(1,"FAIL: CPU read/ack stage %0d",stage);
  $display("PASS: CPU polls latched VSYNC and reads GIME status before acknowledge; fast=%0d",turbo);
  $finish;
 end
 initial begin #2000000; $fatal(1,"FAIL: wait timeout stage=%0d PC=%h",stage,dut.cpu_i.debug_pc); end
endmodule
