`timescale 1ns/1ps
// Natural raster/HSYNC progression: no forced row or pixel counters.
module native_text_scroll_tb;
 reg clk=0, reset_n=0;
 always #5 clk=~clk;
 reg [2:0] lpr=3;
 reg [3:0] scroll=0;
 wire blank;
 integer c,n,height,offset,logical_line,expected_row,seen,total=0,failures=0;
 COCO3VIDEO dut(.PIX_CLK(clk),.RESET_N(reset_n),.RAM_DATA(16'h4241),
 .COCO(1'b0),.V(3'd0),.BP(1'b0),.VERT(7'd0),.VID_CONT(4'd0),.CSS(1'b0),
 .LPF(2'd1),.VERT_FIN_SCRL(scroll),.HLPR(1'b0),.LPR(lpr),.HRES(4'd1),
 .CRES(2'd0),.HVEN(1'b0),.HOR_OFFSET(7'd0),.SCRN_START_HSB(2'd0),
 .SCRN_START_MSB(8'hE0),.SCRN_START_LSB(8'h40),.BLINK(1'b0),.SWITCH5(1'b0),
 .VBLANKING(blank));
 initial begin
  for(c=0;c<15;c=c+1) begin
   case(c)
    0: begin lpr=3;scroll=0;end
    1: begin lpr=3;scroll=1;end
    2: begin lpr=3;scroll=7;end
    3: begin lpr=3;scroll=8;end
    4: begin lpr=3;scroll=15;end
    5: begin lpr=4;scroll=8;end
    6: begin lpr=4;scroll=9;end
    7: begin lpr=4;scroll=15;end
    8: begin lpr=5;scroll=9;end
    9: begin lpr=5;scroll=10;end
    10: begin lpr=6;scroll=10;end
    11: begin lpr=6;scroll=11;end
    12: begin lpr=0;scroll=15;end
    13: begin lpr=2;scroll=1;end
    14: begin lpr=2;scroll=2;end
   endcase
   height=lpr==0?1:lpr==2?2:lpr+5;
   offset=scroll<height?scroll:0;
   reset_n=0; repeat(8) @(posedge clk); #1; reset_n=1;
   seen=0;
   // Each 200-line field is doubled to 400 physical scanlines.
   while(seen<400) begin
    @(negedge clk); #1; total=total+1;
    if(total>15000000) $fatal(1,"Raster timeout");
    if(!blank && dut.PIXEL_COUNT==32) begin
     logical_line=seen/2;
     expected_row=(logical_line+offset)/height;
     if(dut.ROW_ADD!==21'h70200+expected_row*40 || dut.VLPR!==(logical_line+offset)%height) begin
      if(failures<8) $display("FAIL height=%0d scroll=%0d line=%0d rowaddr=%h glyphline=%0d expected row=%0d glyphline=%0d",
        height,scroll,seen,dut.ROW_ADD,dut.VLPR,expected_row,(logical_line+offset)%height);
      failures=failures+1;
     end
     seen=seen+1;
    end
   end
   $display("Checked height=%0d scroll=%0d final row=%0d",height,scroll,expected_row);
  end
  if(failures) $fatal(1,"Scroll raster mismatches=%0d",failures);
  $display("PASS: native text scroll natural raster, 15 cases"); $finish;
 end
endmodule
