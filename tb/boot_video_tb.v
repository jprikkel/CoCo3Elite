`timescale 1ns/1ps
module boot_video_tb;
 reg clock=0, reset=1, raster_resync=0; wire hs,vs,de; wire [7:0] r,g,b;
 integer n, active_lines, first_active, last_active;
 always #5 clock=~clock;
 coco3_boot_system dut(.pixel_clk(clock),.reset(reset),
  .raster_resync(raster_resync),.hsync(hs),.vsync(vs),
  .video_enable(de),.red(r),.green(g),.blue(b));
 initial begin
  repeat(8) @(posedge clock);
  #1;
  if ({dut.palette[0],dut.palette[1],dut.palette[2],dut.palette[3],
       dut.palette[4],dut.palette[5],dut.palette[6],dut.palette[7]} !==
      {6'h12,6'h36,6'h09,6'h24,6'h3f,6'h1b,6'h2d,6'h26} ||
      {dut.palette[8],dut.palette[9],dut.palette[10],dut.palette[11],
       dut.palette[12],dut.palette[13],dut.palette[14],dut.palette[15]} !==
      {6'h00,6'h12,6'h00,6'h3f,6'h00,6'h12,6'h00,6'h26}) begin
   $display("FAIL: GIME compatibility palette reset values are incorrect");
   $fatal;
  end
  reset=0;

  // GIME palette bits are R2 G2 B2 R1 G1 B1. Full green must not decode
  // as magenta, which catches the adjacent-pair mapping used by the first
  // Wukong checkpoint.
  force dut.palette[0] = 6'b010010;
  force dut.color = 9'h000;
  #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h00ff00) begin
   $display("FAIL: palette green decoded as RGB %02h%02h%02h",dut.raw_red,dut.raw_green,dut.raw_blue);
   $fatal;
  end
  release dut.color;
  release dut.palette[0];

  // GIME logical color 16 is the border register at $FF9A, not palette 0.
  // Use a value different from palette 0 so truncating color[4] is detected.
  force dut.machine_i.border_palette = 6'b100100;
  force dut.color = 9'h010;
  #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'hff0000) begin
   $display("FAIL: FF9A border color decoded as RGB %02h%02h%02h",dut.raw_red,dut.raw_green,dut.raw_blue);
   $fatal;
  end
  release dut.color;
  release dut.machine_i.border_palette;

  // Exercise the actual Wukong frame-realignment path. Seed both filters
  // with conspicuous active green pixels, then resync while the source is
  // blank. No previous-frame green may survive into the new frame.
  force dut.raw_video_enable = 1'b1;
  force dut.raw_red = 8'h00;
  force dut.raw_green = 8'hff;
  force dut.raw_blue = 8'h00;
  repeat(12) @(posedge clock);
  force dut.raw_video_enable = 1'b0;
  force dut.raw_green = 8'h00;
  raster_resync = 1'b1;
  @(posedge clock); #1;
  raster_resync = 1'b0;
  repeat(4) begin
   @(posedge clock); #1;
   if (de || r != 0 || g != 0 || b != 0) begin
    $display("FAIL: stale RGB survived raster resync de=%0d rgb=%02h%02h%02h",de,r,g,b);
    $fatal;
   end
  end
  release dut.raw_video_enable;
  release dut.raw_red;
  release dut.raw_green;
  release dut.raw_blue;

  repeat(5000000) @(posedge clock);

  // A 192-line CoCo image is doubled to 384 scanlines and centered within
  // the legacy 225-line viewport: scanlines 32 through 415 inclusive.
  wait(dut.video_i.LINE == 10'd523);
  @(negedge hs); #1;
  active_lines=0; first_active=-1; last_active=-1;
  for(n=0;n<524;n=n+1) begin
   if(!dut.vblank) begin
    active_lines=active_lines+1;
    if(first_active < 0) first_active=dut.video_i.LINE;
    last_active=dut.video_i.LINE;
   end
   @(negedge hs); #1;
  end
  if((active_lines != 384) || (first_active != 32) || (last_active != 415)) begin
   $display("FAIL: raster active=%0d first=%0d last=%0d",active_lines,first_active,last_active);
   $fatal;
  end
  $display("PASS: palette/border decode and centered 192-line raster");

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
