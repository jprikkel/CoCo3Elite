`timescale 1ns/1ps
module coco2_boot_video_tb;
 reg clock=0,reset=1;wire hs,vs,de;wire[7:0]r,g,b;integer n;
 integer visible_samples=0, non_background_samples=0; reg measure_rows=0;
 always #5 clock=~clock;
 coco2_boot_system dut(.pixel_clk(clock),.reset(reset),.hsync(hs),.vsync(vs),.video_enable(de),.red(r),.green(g),.blue(b));
 initial begin
  repeat(8)@(posedge clock);reset=0;repeat(4000000)@(posedge clock);
  visible_samples=0; non_background_samples=0; measure_rows=1;
  repeat(1000000)@(posedge clock);
  $display("CPU=%04h v=%0h vert=%0h vid=%0h css=%0d color=%03h rgb=%02h%02h%02h",dut.addr,dut.v,dut.vert,dut.vid_cont,dut.css,dut.color,r,g,b);
  $display("VIDEO line=%0d pixel=%0d row=%05h rowx=%05h vaddr=%05h vdata=%04h",dut.video_i.LINE,dut.video_i.PIXEL_COUNT,
   dut.video_i.ROW_ADD,dut.video_i.RAM_ADDRESS_X,dut.vaddr,dut.vdata);
  $display("LATCH char0=%04h char1=%04h char2=%04h glyph0=%02h glyph1=%02h glyph2=%02h romaddr=%03h romdata=%02h",
   dut.video_i.CHAR_LATCH_0,dut.video_i.CHAR_LATCH_1,dut.video_i.CHAR_LATCH_2,
   dut.video_i.CHARACTER0,dut.video_i.CHARACTER1,dut.video_i.CHARACTER2,
   dut.video_i.ROM_ADDRESS,dut.video_i.ROM_DATA1);
  $write("RAM $0400:");for(n=16'h200;n<16'h210;n=n+1)$write(" %02h%02h",dut.machine_i.ram_i.memory_high[n],dut.machine_i.ram_i.memory_low[n]);
  $display("");$finish;end
 always @(negedge clock) begin
  if(measure_rows && dut.video_i.LINE==10'd10 && dut.video_i.PIXEL_COUNT>=10'd16 &&
     dut.video_i.PIXEL_COUNT<10'd528) begin
   visible_samples=visible_samples+1;
   if(dut.color!==9'h00d) non_background_samples=non_background_samples+1;
  end
  if(!reset && dut.video_i.PIXEL_COUNT==10'd100 &&
     (dut.video_i.LINE==10'd10 || dut.video_i.LINE==10'd400 ||
      dut.video_i.LINE==10'd510))
   $display("SAMPLE line=%0d pixel=%0d color=%03h active=%0d hb=%0d vb=%0d border=%0d/%0d",
    dut.video_i.LINE,dut.video_i.PIXEL_COUNT,dut.color,de,dut.hb,dut.vb,
    dut.video_i.HBORDER,dut.video_i.VBORDER);
 end
 final begin
  $display("ROW CHECK samples=%0d non_background=%0d",visible_samples,non_background_samples);
 end
endmodule
