`timescale 1ns/1ps
module boot_video_tb;
 reg clock=0, reset=1; wire hs,vs,de; wire [7:0] r,g,b; integer n;
 always #5 clock=~clock;
 coco3_boot_system dut(.pixel_clk(clock),.reset(reset),.hsync(hs),.vsync(vs),.video_enable(de),.red(r),.green(g),.blue(b));
 initial begin
  repeat(8) @(posedge clock); reset=0;
  repeat(5000000) @(posedge clock);
  $display("VIDEO coco=%0d v=%0h vert=%0h vid=%0h hres=%0h lpr=%0h start=%0h%02h%02h",
   dut.coco,dut.v,dut.vert,dut.vid_cont,dut.hres,dut.lpr,dut.start_hsb,dut.start_msb,dut.start_lsb);
  $display("CPU address=%04h all_ram=%0d mmu_enable=%0d task=%0d maps=%02h %02h %02h %02h %02h %02h %02h %02h",
   dut.cpu_address,dut.machine_i.all_ram,dut.machine_i.mmu_enable,dut.machine_i.mmu_task,
   dut.machine_i.mmu[0],dut.machine_i.mmu[1],dut.machine_i.mmu[2],dut.machine_i.mmu[3],
   dut.machine_i.mmu[4],dut.machine_i.mmu[5],dut.machine_i.mmu[6],dut.machine_i.mmu[7]);
  $write("RAM $0400:");
  for(n=16'h200;n<16'h210;n=n+1) $write(" %02h%02h",dut.machine_i.ram_i.memory_high[n],dut.machine_i.ram_i.memory_low[n]);
  $display(""); $write("RAM $10000:");
  for(n=16'h8000;n<16'h8010;n=n+1) $write(" %02h%02h",dut.machine_i.ram_i.memory_high[n],dut.machine_i.ram_i.memory_low[n]);
  $display(""); $write("RAM $10400:");
  for(n=16'h8200;n<16'h8210;n=n+1) $write(" %02h%02h",dut.machine_i.ram_i.memory_high[n],dut.machine_i.ram_i.memory_low[n]);
  $display(""); $finish;
 end
endmodule
