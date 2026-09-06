`timescale 1ns/1ps
// Clock/buffer substitutes only; actual board RTL, filters and HDMI library.
module wukong_clocking(input clk_50mhz,output pixel_clk,serial_clk,locked,video_reset);
 assign pixel_clk=clk_50mhz; assign serial_clk=clk_50mhz;
 assign locked=1'b1; assign video_reset=hdmi_window_tb.reset;
endmodule
module OBUFDS #(parameter IOSTANDARD="DEFAULT", SLEW="SLOW")(input I,output O,OB);
 assign O=I; assign OB=~I;
endmodule
module serializer #(parameter int NUM_CHANNELS=3, parameter real VIDEO_RATE=0)
 (input logic clk_pixel,clk_pixel_x5,reset,
  input logic [9:0] tmds_internal [NUM_CHANNELS-1:0],
  output logic [2:0] tmds,output logic tmds_clock);
 always_comb begin tmds='0;tmds_clock=0;end
endmodule
module hdmi_window_tb;
 reg clk=0,reset=1; always #5 clk=~clk;
 reg [3:0] test_hres=1;
 integer m,n,count,first,last,lost,tag,failures=0;
 integer capture_file, capture_pixels;
 wukong_top dut(.clk_50mhz(clk),.ps2_clk(1'b1),.ps2_data(1'b1),.sd_miso(1'b1));
 initial begin
  force dut.source_i.machine_i.hold=1'b1;
  force dut.source_i.coco=1'b0;
  force dut.source_i.hres=test_hres;
  force dut.source_i.bp=1'b0;
  force dut.source_i.lpf=2'd1;
  force dut.source_i.lpr=3'd3;
  force dut.source_i.cres=2'd0;
  force dut.source_i.scroll=4'd0;
  // Tag source content (not the surrounding border), preserving its timing.
  force dut.source_i.raw_red=(!dut.source_i.hblank && !dut.source_i.vblank)?8'hA5:8'h00;
  force dut.source_i.raw_green=dut.source_i.video_i.PIXEL_COUNT[7:0];
  force dut.source_i.raw_blue={6'd0,dut.source_i.video_i.PIXEL_COUNT[9:8]};
  for(m=0;m<3;m=m+1) begin
   test_hres=m==0?1:m==1?5:0;
   reset=1; repeat(8) @(negedge clk); #1; reset=0;
   // Let one frame resync, then inspect a central visible output line.
   repeat(430000) @(negedge clk);
   wait(dut.library_x==0 && dut.library_y==200);
   count=0;first=-1;last=-1;lost=0;
   for(n=0;n<800;n=n+1) begin
    @(posedge clk); #1;
    // Library mode and video_data are the actual paired encoder inputs.
    if(dut.library_hdmi_i.video_data[23:16]==8'hA5) begin
     tag={dut.library_hdmi_i.video_data[1:0],dut.library_hdmi_i.video_data[15:8]};
     if(dut.library_hdmi_i.mode==1) begin
      if(first<0) first=tag;
      last=tag;count=count+1;
     end else lost=lost+1;
    end
   end
   $display("WINDOW hres=%0d content=%0d first=%0d last=%0d blanked=%0d",test_hres,count,first,last,lost);
   if(count!=(m==2?512:640) || lost!=0) failures=failures+1;

   // Capture the actual RGB words presented to hdl-util. These images make
   // the simulated active-window placement directly comparable with a photo
   // of the monitor. Black represents HDMI blanking.
   case (m)
     0: capture_file=$fopen("width40.ppm","wb");
     1: capture_file=$fopen("width80.ppm","wb");
     default: capture_file=$fopen("width32.ppm","wb");
   endcase
   if(!capture_file) $fatal(1,"Unable to create simulated screen capture");
   $fwrite(capture_file,"P6\n640 480\n255\n");
   wait(dut.library_x==0 && dut.library_y==0);
   capture_pixels=0;
   for(n=0;n<800*525;n=n+1) begin
    @(posedge clk); #1;
    if(dut.library_x<640 && dut.library_y<480) begin
     if(dut.library_hdmi_i.mode==1)
      $fwrite(capture_file,"%c%c%c",
       dut.library_hdmi_i.video_data[23:16],
       dut.library_hdmi_i.video_data[15:8],
       dut.library_hdmi_i.video_data[7:0]);
     else $fwrite(capture_file,"%c%c%c",0,0,0);
     capture_pixels=capture_pixels+1;
    end
   end
   $fclose(capture_file);
   if(capture_pixels!=640*480)
    $fatal(1,"Capture contained %0d pixels",capture_pixels);
  end
  if(failures) $fatal(1,"HDMI window clipped in %0d modes",failures);
  $display("PASS: full HDMI content window in 32/40/80-column modes");$finish;
 end
 initial begin #90000000; $fatal(1,"Window test timeout");end
endmodule
