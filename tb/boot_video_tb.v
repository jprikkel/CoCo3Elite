`timescale 1ns/1ps
module boot_video_tb;
 reg clock=0, reset=1, raster_resync=0; wire hs,vs,de; wire [7:0] r,g,b;
 integer n, active_lines, first_active, last_active;
 always #5 clock=~clock;
 coco3_boot_system #(.SOFT_RESET_GUARD_CLOCKS(3),
                     .CARTRIDGE_COLD_RESET_CLOCKS(3)) dut(.pixel_clk(clock),.reset(reset),
  .raster_resync(raster_resync),.screen_x(10'd0),.screen_y(10'd0),.hsync(hs),.vsync(vs),
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

  // A cartridge selection must behave like installing a ROM-Pak with power
  // off.  Preserve the manager, cold-reset the CoCo, clear BASIC's retained
  // warm-start flag, wait for its initialized idle loop, and only then CART.
  dut.machine_i.ram_i.memory_high[16'h8038] = 8'h55;
  force dut.manager_cartridge_enabled = 1'b1;
  force dut.manager_cartridge_launch = 1'b1;
  @(posedge clock); #1;
  force dut.manager_cartridge_launch = 1'b0;
  if (dut.cartridge_boot_state != dut.CART_BOOT_RESET ||
      !dut.machine_reset || dut.effective_cartridge_enabled) begin
   $display("FAIL: cartridge selection did not begin an isolated cold reset");
   $fatal;
  end
  @(posedge clock); #1;
  if (dut.machine_i.ram_i.memory_high[16'h8038] !== 8'h00) begin
   $display("FAIL: cartridge cold reset did not clear BASIC warm-start flag");
   $fatal;
  end
  wait(dut.cartridge_cold_reset_count == 3);
  force dut.cpu_pc = 16'ha7d5;
  @(posedge clock); #1;
  if (dut.cartridge_boot_state != dut.CART_BOOT_WAIT_START || dut.machine_reset) begin
   $display("FAIL: cartridge cold reset did not release into BASIC startup");
   $fatal;
  end
  @(posedge clock); #1;
  if (dut.cartridge_boot_state != dut.CART_BOOT_WAIT_START ||
      dut.effective_cartridge_launch) begin
   $display("FAIL: stale pre-reset BASIC PC caused an early CART event");
   $fatal;
  end
  force dut.cpu_pc = 16'hfffe;
  @(posedge clock); #1;
  if (dut.cartridge_boot_state != dut.CART_BOOT_WAIT_BASIC) begin
   $display("FAIL: reset-vector startup did not qualify BASIC wait");
   $fatal;
  end
  force dut.cpu_pc = 16'ha7d5;
  @(posedge clock); #1;
  if (dut.cartridge_boot_state != dut.CART_BOOT_LAUNCH ||
      !dut.effective_cartridge_launch) begin
   $display("FAIL: initialized BASIC idle did not arm the CART event");
   $fatal;
  end
  @(posedge clock); #1;
  release dut.cpu_pc;
  if (!dut.cartridge_session_active || !dut.effective_cartridge_enabled ||
      dut.effective_cartridge_launch) begin
   $display("FAIL: cold cartridge launch did not enter a stable session");
   $fatal;
  end
  $display("PASS: cartridge launch uses a staged cold CoCo start");

  // A later Ctrl-Alt-Delete ends the session while preserving the manager.
  // Its persistent enable level must not remap or relaunch the old ROM.
  force dut.keyboard_reset = 1'b1;
  wait(dut.soft_reset_active);
  #1;
  release dut.keyboard_reset;
  if (!dut.keyboard_decoder_reset || dut.effective_cartridge_enabled) begin
   $display("FAIL: soft reset did not clear cartridge/keyboard state");
   $fatal;
  end
  wait(dut.soft_reset_release_count == 3);
  raster_resync = 1'b1;
  @(posedge clock); #1;
  raster_resync = 1'b0;
  if (dut.soft_reset_active || dut.effective_cartridge_enabled ||
      dut.cartridge_session_active) begin
   $display("FAIL: persistent manager enable replayed cartridge after reset");
   $fatal;
  end
  force dut.manager_cartridge_enabled = 1'b0;
  @(posedge clock); #1;
  if (dut.cartridge_session_active || dut.effective_cartridge_enabled) begin
   $display("FAIL: cartridge disable did not end the session");
   $fatal;
  end
  release dut.manager_cartridge_launch;
  release dut.manager_cartridge_enabled;
  $display("PASS: soft reset disarms persistent cartridge state");

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

  // Setup palette themes are display-only substitutions for the four VDG
  // logical slots: green, yellow, blue, and red. Verify the requested Base
  // remap completely, then spot-check the named machine palettes.
  force dut.coco = 1'b1;
  force dut.vid_cont = 4'b0000;
  force dut.manager_text_color_theme = 4'd0;
  force dut.manager_coco2_palette = 4'd1;
  force dut.color = 9'h000; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h000000)
   $fatal(1,"Base original-green slot mismatch");
  force dut.color = 9'h001; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'hc48a52)
   $fatal(1,"Base original-yellow slot mismatch");
  force dut.color = 9'h002; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h783c18)
   $fatal(1,"Base original-blue slot mismatch");
  force dut.color = 9'h003; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h186828)
   $fatal(1,"Base original-red slot mismatch");
  force dut.manager_coco2_palette = 4'd2; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h68372b)
   $fatal(1,"C64 red slot mismatch");
  force dut.manager_coco2_palette = 4'd3;
  force dut.color = 9'h002; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h4040c0)
   $fatal(1,"Atari blue slot mismatch");
  force dut.manager_coco2_palette = 4'd4;
  force dut.color = 9'h001; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h40c8d0)
   $fatal(1,"CGA cyan slot mismatch");
  force dut.manager_coco2_palette = 4'd8;
  force dut.color = 9'h002; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'he06020)
   $fatal(1,"CoCo artifact orange slot mismatch");
  force dut.manager_coco2_palette = 4'd15;
  force dut.color = 9'h003; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'hf0f0f0)
   $fatal(1,"grayscale white slot mismatch");

  // Text themes independently replace MC6847 alpha foreground, background,
  // and border colors without affecting graphics or software-visible state.
  force dut.manager_text_color_theme = 4'd4;
  force dut.color = 9'h00d; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h100c04)
   $fatal(1,"VT220 amber background mismatch");
  force dut.color = 9'h00c; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'hffb850)
   $fatal(1,"VT220 amber foreground mismatch");
  force dut.color = 9'h010; #1;
  if ({dut.raw_red,dut.raw_green,dut.raw_blue} !== 24'h201408)
   $fatal(1,"VT220 amber border mismatch");
  release dut.color;
  release dut.manager_text_color_theme;
  release dut.manager_coco2_palette;
  release dut.vid_cont;
  release dut.coco;
  $display("PASS: four-color palettes and text themes");

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
