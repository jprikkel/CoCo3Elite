`timescale 1ns/1ps
module zenix_video_tb;
 reg clk=0,reset=1;
 reg [9:0] pixel=0;
 reg [20:0] rowaddr=21'h6b100;
 reg [6:0] hoff=24;
 wire [19:0] addr;
 wire [15:0] data;
 integer i,row,p,k,ofs,phys,j,n,colors=0;
 reg [15:0] seen=0;
 reg [3:0] actual_pixel,want_pixel;
 reg [15:0] expected;
 always #5 clk=~clk;
 coco3_128k_ram ram(.clock(clk),.cpu_address(17'd0),.cpu_write_data(8'd0),
 .cpu_write_enable(1'b0),.video_address(addr),.video_read_data(data));
 COCO3VIDEO dut(.PIX_CLK(clk),.RESET_N(!reset),.RAM_ADDRESS(addr),.RAM_DATA(data),
 .COCO(1'b0),.V(3'd0),.BP(1'b1),.VERT(7'd0),.VID_CONT(4'd0),.CSS(1'b0),
 .LPF(2'd3),.VERT_FIN_SCRL(4'd0),.HLPR(1'b0),.LPR(3'd0),.HRES(4'd7),
 .CRES(2'd2),.HVEN(1'b1),.HOR_OFFSET(hoff),.SCRN_START_HSB(2'd0),
 .SCRN_START_MSB(8'hd6),.SCRN_START_LSB(8'h20),.BLINK(1'b0),.SWITCH5(1'b0));
 function [7:0] pattern;
 input integer a;
 begin pattern=((a*29) ^ (a>>8)); end
 endfunction
 initial begin
  #1;
  for(i=0;i<65536;i=i+1) begin
   ram.memory_low[i]=pattern(i*2);
   ram.memory_high[i]=pattern(i*2+1);
  end
  force dut.PIXEL_COUNT=pixel;
  force dut.ROW_ADD=rowaddr;
  repeat(4) @(posedge clk); #1; reset=0;
  for(k=0;k<2;k=k+1) begin
   hoff=k ? 126 : 24;
   for(row=0;row<225;row=row+1) begin
    rowaddr='h6b100+row*256;
    #1;
    if(dut.SCREEN_OFF!==rowaddr+256) $fatal(1,"HVEN row stride");
    for(p=0;p<640;p=p+1) begin
     @(posedge clk); #1; pixel=p;
     @(negedge clk); #1;
     if(p%16==15) begin
      ofs=((p/16)*4+hoff*2)%256;
      phys=(rowaddr+ofs)&'h1ffff;
      expected={pattern(phys+1),pattern(phys)};
      if(dut.CHAR_LATCH_0!==expected) $fatal(1,"Fetch0 row=%0d pixel=%0d expected=%h actual=%h",row,p,expected,dut.CHAR_LATCH_0);
      for(j=0;j<8;j=j+1) begin
       actual_pixel={dut.COLOR3[j],dut.COLOR2[j],dut.COLOR1[j],dut.COLOR0[j]};
       case(j/2)
        0: want_pixel=expected[7:4];
        1: want_pixel=expected[3:0];
        2: want_pixel=expected[15:12];
        3: want_pixel=expected[11:8];
       endcase
       if(actual_pixel!==want_pixel) $fatal(1,"Decoded pixel mismatch row=%0d p=%0d sub=%0d got=%h expected=%h",row,p,j,actual_pixel,want_pixel);
      end
      phys=(rowaddr+((ofs+2)%256))&'h1ffff;
      expected={pattern(phys+1),pattern(phys)};
      if(dut.CHAR_LATCH_1!==expected) $fatal(1,"Fetch1 row=%0d pixel=%0d expected=%h actual=%h",row,p,expected,dut.CHAR_LATCH_1);
     end
    end
   end
  end
  release dut.PIXEL_COUNT;
  release dut.ROW_ADD;
  reset=1; repeat(4) @(posedge clk); #1; reset=0;
  // Exercise the unforced raster after a full startup frame.
  repeat(800*525) @(posedge clk);
  for(n=0;n<800*525;n=n+1) begin
   @(posedge clk); #1;
   if(!dut.HBLANKING && !dut.VBLANKING) seen[dut.COLOR[3:0]]=1;
  end
  if(seen!==16'hffff) $fatal(1,"Real raster did not display all pattern colors: %h",seen);
  $display("PASS: Zenix 320x225 16-color HVEN fetches, pixel decode, both RAM banks, wrap and full raster");
  $finish;
 end
endmodule
