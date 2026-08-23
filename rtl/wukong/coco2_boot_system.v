`timescale 1ns/1ps
`default_nettype none
module coco2_boot_system(input wire pixel_clk,input wire reset,output wire hsync,
 output wire vsync,output wire video_enable,output reg [7:0] red,
 output reg [7:0] green,output reg [7:0] blue);
 wire [15:0] addr; wire io_write; wire [7:0] data; wire [19:0] vaddr;
 wire [15:0] vdata; wire [8:0] color; wire hb,vb,sf;
 reg video_reset_n=1'b1;
 reg [2:0] v; reg [6:0] vert; reg [3:0] vid_cont; reg css,pia_ddr4;
 coco2_boot_machine machine_i(.clock(pixel_clk),.reset(reset),.video_address(vaddr),
  .video_read_data(vdata),.debug_address(addr),.debug_io_write(io_write),.debug_write_data(data));
 always @(posedge pixel_clk) begin
  if(reset) begin v<=0;vert<=0;vid_cont<=0;css<=0;pia_ddr4<=0;end
  else if(io_write) case(addr)
   16'hFF22: if(pia_ddr4) begin vid_cont<=data[7:4];css<=data[3];end
   16'hFF23: pia_ddr4<=data[2];
   16'hFFC0:v[0]<=0;16'hFFC1:v[0]<=1;16'hFFC2:v[1]<=0;16'hFFC3:v[1]<=1;
   16'hFFC4:v[2]<=0;16'hFFC5:v[2]<=1;16'hFFC6:vert[0]<=0;16'hFFC7:vert[0]<=1;
   16'hFFC8:vert[1]<=0;16'hFFC9:vert[1]<=1;16'hFFCA:vert[2]<=0;16'hFFCB:vert[2]<=1;
   16'hFFCC:vert[3]<=0;16'hFFCD:vert[3]<=1;16'hFFCE:vert[4]<=0;16'hFFCF:vert[4]<=1;
   16'hFFD0:vert[5]<=0;16'hFFD1:vert[5]<=1;16'hFFD2:vert[6]<=0;16'hFFD3:vert[6]<=1;
  endcase
 end
 always @(posedge pixel_clk) video_reset_n <= ~reset;
 COCO3VIDEO video_i(.PIX_CLK(pixel_clk),.RESET_N(video_reset_n),.COLOR(color),.HSYNC(hsync),
  .SYNC_FLAG(sf),.VSYNC(vsync),.HBLANKING(hb),.VBLANKING(vb),.RAM_ADDRESS(vaddr),
  .RAM_DATA(vdata),.VIDEO_ACTIVE(video_enable),.COCO(1'b1),.V(v),.BP(1'b0),.VERT(vert),.VID_CONT(vid_cont),
  .CSS(css),.LPF(2'b0),.VERT_FIN_SCRL(4'b0),.HLPR(1'b0),.LPR(3'b0),
  .HRES(4'b0),.CRES(2'b0),.HVEN(1'b0),.HOR_OFFSET(7'b0),.SCRN_START_HSB(2'b0),
  .SCRN_START_MSB(8'b0),.SCRN_START_LSB(8'b0),.BLINK(1'b1),.SWITCH5(1'b0));
 always @* begin
  if(color[8]) begin
   case(color[7:6])
    2'b00: begin red={2{2'b00,color[5],color[2]}};green={2{2'b00,color[4],color[1]}};blue={2{2'b00,color[3],color[0]}};end
    2'b01: begin red={2{({1'b0,color[5],color[2],1'b0}+{2'b00,color[5],color[2]})}};green={2{({1'b0,color[4],color[1],1'b0}+{2'b00,color[4],color[1]})}};blue={2{({1'b0,color[3],color[0],1'b0}+{2'b00,color[3],color[0]})}};end
    2'b10: begin red={2{color[5],color[2],2'b0}};green={2{color[4],color[1],2'b0}};blue={2{color[3],color[0],2'b0}};end
    default: begin red={color[5],color[2],color[5],color[2],color[5],color[2],color[5],color[2]};green={color[4],color[1],color[4],color[1],color[4],color[1],color[4],color[1]};blue={color[3],color[0],color[3],color[0],color[3],color[0],color[3],color[0]};end
   endcase
  end
  else case(color[3:0])
   0:{red,green,blue}=24'h000000;1:{red,green,blue}=24'h0000AA;
   2:{red,green,blue}=24'h00AA00;3:{red,green,blue}=24'h00AAAA;
   4:{red,green,blue}=24'hAA0000;5:{red,green,blue}=24'hAA00AA;
   6:{red,green,blue}=24'hAA5500;7:{red,green,blue}=24'hAAAAAA;
   8:{red,green,blue}=24'h101830;9:{red,green,blue}=24'h3030FF;
   10:{red,green,blue}=24'h30FF30;11:{red,green,blue}=24'h30FFFF;
   12:{red,green,blue}=24'h40FF70;13:{red,green,blue}=24'h081008;
   14:{red,green,blue}=24'hFFFF40;15:{red,green,blue}=24'h201000;
  endcase
 end
 wire _unused=sf;
endmodule
`default_nettype wire
