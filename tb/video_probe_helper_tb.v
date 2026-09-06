`timescale 1ns/1ps
// Software regression only: flat RAM/register model, NOT a GIME video model.
module video_probe_helper_tb;
 reg clk=0, rst=1;
 wire [15:0] addr;
 wire [7:0] dout;
 reg [7:0] din;
 wire rw,vma;
 reg [7:0] mem[0:65535];
 reg [7:0] saved[0:65535];
 integer i,c,n;
 reg seen;
 always #5 clk=~clk;
 always @(posedge clk) din<=mem[addr];
 cpu09 cpu(.clk(clk),.rst(rst),.addr(addr),.data_in(din),
 .data_out(dout),.rw(rw),.vma(vma),.irq(1'b0),.firq(1'b0),
 .nmi(1'b0),.halt(1'b0),.hold(1'b0));
 always @(posedge clk) if(!rst && vma && !rw) begin
  mem[addr]<=dout;
 end
 initial begin
  for(c=1;c<=7;c=c+1) begin
   rst=1;
   for(i=0;i<65536;i=i+1) mem[i]=(i^(i>>8))&255;
   $readmemh("vidhelp.mem",mem);
   // LDS #$5F00; JSR $6000; BRA *
   mem['h5000]='h10; mem['h5001]='hCE;
   mem['h5002]='h5F; mem['h5003]=0;
   mem['h5004]='hBD; mem['h5005]='h60; mem['h5006]=0;
   mem['h5007]='h20; mem['h5008]='hFE;
   mem['hFFFE]='h50; mem['hFFFF]=0;
   mem['hFF90]='h40; mem['hFF91]=0;
   mem['hFFA3]=(c==7)?'h3A:'h3B;
   mem['hFF00]='hFF; mem['hFF02]='hFF;
   mem['h6003]=(c==7)?1:c;
   mem['h6005]=0;
   for(i=0;i<65536;i=i+1) saved[i]=mem[i];
   repeat(8) @(negedge clk);
   #1; rst=0; seen=0;
   n=0;
   while(!(addr=='h5007 && rw && vma && mem['h6005]=='hFE) && n<2000000) begin
    @(negedge clk); n=n+1;
    if(mem['h6005]==1) seen=1;
   end
   if(n==2000000) $fatal(1,"Case %0d timeout PC=%h",c,addr);
   if(mem['h6005]!='hFE || mem['h6004]!==((c==7)?8'd4:8'd0))
    $fatal(1,"Case %0d result=%h stage=%h",c,mem['h6004],mem['h6005]);
   if(c<=6 && !seen) $fatal(1,"Missing display stage");
   for(i='h200;i<'h2200;i=i+1)
    if(mem[i]!==saved[i]) $fatal(1,"Screen not restored at %h",i);
   for(i='hFF98;i<='hFF9F;i=i+1)
    if(mem[i]!==saved[i]) $fatal(1,"Video register not restored %h",i);
   for(i='hFFB0;i<='hFFBF;i=i+1)
    if(mem[i]!==saved[i]) $fatal(1,"Palette not restored %h",i);
   if(mem['hFF90]!==saved['hFF90] || mem['hFF02]!==saved['hFF02])
    $fatal(1,"INIT0/columns not restored");
   $display("PASS: helper case %0d returned and restored state",c);
  end
  $display("PASS: all video helper software cases"); $finish;
 end
endmodule
