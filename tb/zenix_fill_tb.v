`timescale 1ns/1ps
module zenix_fill_tb;
 reg clock=0,reset=1;
 localparam integer HELPER_SIZE=271;
 reg [7:0] program_data[0:255], helper[0:HELPER_SIZE-1];
 wire [7:0] injected_rom=dut.address==16'hfffe ? 8'h80 :
                         dut.address==16'hffff ? 8'h00 :
                         program_data[dut.address[7:0]];
 integer i,color;
 reg [7:0] actual,expected,first_offset;
 always #5 clock=~clock;
 coco3_boot_machine dut(.clock(clock),.reset(reset),.cpu_fast_mode(1'b1),.cpu_halt(1'b0),
 .diagnostic_cartridge_enabled(1'b0),.keyboard_keys(56'b0),
 .keyboard_shift(1'b0),.keyboard_shift_override(1'b0),
 .joystick_left_x(6'd32),.joystick_left_y(6'd32),.joystick_left_fire(1'b0),
 .joystick_right_x(6'd32),.joystick_right_y(6'd32),.joystick_right_fire(1'b0),
 .sd_status(8'd0),.sd_detail(8'd0),.video_hsync(1'b1),
 .video_vsync(1'b1),.video_address(20'd0));
 initial begin
  $readmemh("zen_harness.mem",program_data);
  $readmemh("zen_helper.mem",helper);
  force dut.rom_data=injected_rom;
  #1;
  // Standard page $3B maps logical $6000 to physical $16000.
  for(i=0;i<HELPER_SIZE;i=i+1) begin
   if(i[0]) dut.ram_i.memory_high[('h16000+i)/2]=helper[i];
   else dut.ram_i.memory_low[('h16000+i)/2]=helper[i];
  end
  repeat(12) @(negedge clock); reset=0;
  wait(dut.gime_video_mode==8'h80 && dut.gime_video_resolution==8'h7e &&
       dut.gime_video_offset==16'hd620 && dut.gime_video_horizontal_offset[7]);
  first_offset=dut.gime_video_horizontal_offset;
  wait(dut.gime_video_horizontal_offset!=first_offset);
  for(i='hb100;i<'h19200;i=i+1) begin
   actual=i[0] ? dut.ram_i.memory_high[i/2] : dut.ram_i.memory_low[i/2];
   color=(((i & 8'hff)>>4) ^ (8'h30+(i>>13))) & 15;
   expected=color*17;
   if(actual!==expected)
    $fatal(1,"Zenix MMU pattern mismatch at physical %h got %h expected %h",i,actual,expected);
  end
  if(dut.mmu[3]!==8'h34)
   $fatal(1,"Zenix helper did not relocate page three: %h",dut.mmu[3]);
  if(dut.mmu_enable!==1'b1)
   $fatal(1,"Zenix helper did not enable the MMU");
  $display("PASS: Zenix CPU/MMU fill starts MMU-disabled, reaches $D620 HVEN framebuffer and scroll loop");
  $finish;
 end
 initial begin #500000000; $fatal(1,"Zenix helper timeout PC=%h",dut.cpu_i.debug_pc); end
endmodule
