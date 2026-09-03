`timescale 1ns/1ps
// Exercise the real BRAM -> video latches; isolate raster scheduling by
// supplying pixel/row counters. Expected addresses derive from cell numbers.
module native_text_fetch_tb;
 reg clk=0; always #5 clk=~clk;
 reg [3:0] hres=1;
 reg [1:0] cres=0;
 reg [9:0] pixel=0;
 reg [20:0] rowaddr=21'h70200;
 wire [19:0] addr; wire [15:0] data;
 integer m,row,col,p,width,bytespercell,index,expected,failures=0;
`ifdef NEW_SRAM
 localparam FETCH_PHASE=5;
`else
 localparam FETCH_PHASE=3;
`endif
 coco3_128k_ram ram(.clock(clk),.cpu_address(17'd0),
 .cpu_write_data(8'd0),.cpu_write_enable(1'b0),.video_address(addr),.video_read_data(data));
 COCO3VIDEO dut(.PIX_CLK(clk),.RESET_N(1'b1),.RAM_ADDRESS(addr),.RAM_DATA(data),
 .COCO(1'b0),.V(3'd0),.BP(1'b0),.VERT(7'd0),.VID_CONT(4'd0),.CSS(1'b0),
 .LPF(2'd1),.VERT_FIN_SCRL(4'd0),.HLPR(1'b0),.LPR(3'd3),.HRES(hres),
 .CRES(cres),.HVEN(1'b0),.HOR_OFFSET(7'd0),.SCRN_START_HSB(2'd0),
 .SCRN_START_MSB(8'hE0),.SCRN_START_LSB(8'h40),.BLINK(1'b0),.SWITCH5(1'b0));
 initial begin
  force dut.PIXEL_COUNT=pixel;
  force dut.ROW_ADD=rowaddr;
  force dut.VLPR=0;
  #1;
  for(m=0;m<8;m=m+1) begin
   hres=((m/2)%2)?5:1; if(m>=4) hres=hres-1;
   cres=m%2; width=hres[2]?(hres[0]?80:64):(hres[0]?40:32);
   bytespercell=cres?2:1;
   for(row=0;row<25;row=row+1) begin
    rowaddr='h70200+row*width*bytespercell;
    for(col=0;col<width;col=col+1) begin
     index=('h10200+row*width*bytespercell+col*bytespercell);
     if(index%2) ram.memory_high[index/2]=65+col%26;
     else ram.memory_low[index/2]=65+col%26;
     if(cres) ram.memory_high[index/2]=8'h0A;
    end
    #1;
    if(dut.SCREEN_OFF !== rowaddr+width*bytespercell) $fatal(1,"Row stride mismatch");
    for(p=0;p<width*(hres[2]?8:16);p=p+1) begin
     @(posedge clk); #1; pixel=p;
     @(negedge clk); #1;
     if(p%16==FETCH_PHASE) begin
      col=p/(hres[2]?8:16); expected=65+col%26;
      if(dut.CHAR_LATCH_0[7:0]!==expected[7:0]) begin
       if(failures<8) $display("FAIL width=%0d attr=%0d row=%0d col=%0d expected=%h got=%h word=%h",
        width,cres,row,col,expected[7:0],dut.CHAR_LATCH_0[7:0],data);
       failures=failures+1;
      end
      if(cres && dut.CHAR_LATCH_0[15:8]!==8'h0A) $fatal(1,"Attribute latch mismatch");
     end
     if(hres[2] && p%16==15) begin
      col=p/8; expected=65+col%26;
      if((cres?dut.CHARACTER2:dut.CHARACTER1) !== dut.coco3gen.memory[expected*16+3]) begin
       if(failures<8) $display("FAIL second glyph width=%0d attr=%0d col=%0d",width,cres,col);
       failures=failures+1;
      end
     end
    end
   end
   $display("Completed width=%0d attr=%0d",width,cres);
  end
  if(failures) $fatal(1,"Native text fetch failures=%0d",failures);
  $display("PASS: native text fetch eight modes, 25 rows each"); $finish;
 end
endmodule
