`timescale 1ns/1ps
module hven_fill_tb;
 reg clock=0,reset=1;
 reg [7:0] program_data[0:255], helper[0:255];
 wire [7:0] injected_rom=dut.address==16'hfffe ? 8'h80 : dut.address==16'hffff ? 8'h00 : program_data[dut.address[7:0]];
 integer i;
 reg [7:0] actual,expected;
 always #5 clock=~clock;
 coco3_boot_machine dut(.clock(clock),.reset(reset),.cpu_fast_mode(1'b0),.cpu_halt(1'b0),
 .diagnostic_cartridge_enabled(1'b0),.keyboard_keys(56'b0),
 .keyboard_shift(1'b0),.keyboard_shift_override(1'b0),
 .joystick_left_x(6'd32),.joystick_left_y(6'd32),.joystick_left_fire(1'b0),
 .joystick_right_x(6'd32),.joystick_right_y(6'd32),.joystick_right_fire(1'b0),
 .sd_status(8'd0),.sd_detail(8'd0),.video_hsync(1'b1),.video_vsync(1'b1),.video_address(20'd0));
 initial begin
  $readmemh("hven_harness.mem",program_data);
  $readmemh("hven_helper.mem",helper);
  force dut.rom_data=injected_rom;
  #1;
  for(i=0;i<256;i=i+2) begin
   dut.ram_i.memory_low['hb000+i/2]=helper[i];
   dut.ram_i.memory_high['hb000+i/2]=helper[i+1];
  end
  repeat(12) @(negedge clock); reset=0;
  wait(dut.diagnostic_probe_address==13'hfe);
  for(i=0;i<24576;i=i+1) begin
   actual=i%2 ? dut.ram_i.memory_high[i/2] : dut.ram_i.memory_low[i/2];
   expected=((i%256)/16)*17;
   if(actual!==expected) $fatal(1,"Pattern mismatch byte %h got %h expected %h",i,actual,expected);
  end
  if(dut.mmu[2]!==8'h3a || dut.gime_video_mode!==8'h82 || dut.gime_video_horizontal_offset!==8'h80)
   $fatal(1,"HVEN mode or MMU restoration failed");
  if(dut.ram_i.memory_low['h3000]!==0) $fatal(1,"Write exceeded 24K allocation");
  $display("PASS: HVEN helper fills 24K pattern, restores MMU/stack, selects double-line HVEN");
  $finish;
 end
 initial begin #200000000; $fatal(1,"HVEN helper timeout PC=%h",dut.cpu_i.debug_pc); end
endmodule
