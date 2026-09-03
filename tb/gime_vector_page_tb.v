`timescale 1ns/1ps
module gime_vector_page_tb;
 reg clock=0, reset=1; wire [7:0] read_data; wire ram_write;
 always #5 clock=~clock;
 coco3_boot_machine dut(
  .clock(clock),.reset(reset),.cpu_fast_mode(1'b0),
  .diagnostic_cartridge_enabled(1'b0),.debug_read_data(read_data),
  .debug_ram_write(ram_write),.keyboard_keys(56'b0),.keyboard_shift(1'b0),
  .keyboard_shift_override(1'b0),.joystick_left_x(6'd32),.joystick_left_y(6'd32),
  .joystick_left_fire(1'b0),.joystick_right_x(6'd32),.joystick_right_y(6'd32),
  .joystick_right_fire(1'b0),.sd_status(8'h0),.sd_detail(8'h0),
  .video_hsync(1'b1),.video_vsync(1'b1),.video_address(20'h0));
 initial begin
  repeat(2) @(posedge clock); reset=0; #1;
  force dut.address=16'hFE00; force dut.vma=1'b1;
  force dut.read_cycle=1'b1; force dut.hold=1'b0; force dut.all_ram=1'b0;
  dut.ram_i.memory_low[16'hEF00]=8'ha5;
  dut.ram_i.memory_low[16'hFF00]=8'h5a;
  force dut.mmu_enable=1'b1; force dut.mmu_task=1'b0;
  dut.mmu[7]=8'h3e;
  force dut.gime_init0=8'h40; #20;
  if(read_data !== 8'ha5) $fatal(1,"FAIL: FE00 MMU view got %02h",read_data);
  force dut.gime_init0=8'h48; #20;
  if(read_data !== 8'h5a) $fatal(1,"FAIL: FE00 fixed view got %02h",read_data);
  force dut.read_cycle=1'b0; #1;
  if(!ram_write) $fatal(1,"FAIL: FE00 RAM write not enabled");
  $display("PASS: FF90.3 selects fixed page 3F instead of MMU block 7"); $finish;
 end
endmodule
