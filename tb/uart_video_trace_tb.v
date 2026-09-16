`timescale 1ns/1ps
module uart_video_trace_tb;
 reg clk=0,reset=1;
 wire tx;
 reg [8*119-1:0] expected={"PC=1234 K=1 R=FF C=FF S=80 T=00 V=807E00D620980123456789ABCDEF0123456789AB G=4C204 M=38393A3B3C3D3E3F3031323334353637",8'h0d,8'h0a};
 reg [7:0] received;
 integer i,b;
 always #5 clk=~clk;
 coco3_uart_debug dut(.clock(clk),.reset(reset),.cpu_address(16'd0),.cpu_pc(16'h1234),
 .cpu_vma(1'b0),.cpu_read(1'b1),.cpu_read_data(8'd0),
 .cpu_write_data(8'd0),.keyboard_active(1'b1),.cartridge_enabled(1'b0),
 .sd_status(8'h80),
 .video_state(160'h807E00D620980123456789ABCDEF0123456789AB),
 .gime_init0(8'h4c),.gime_init1(8'h20),.memory_flags(3'b100),
 .mmu_state(128'h38393A3B3C3D3E3F3031323334353637),.uart_tx_o(tx));
 initial begin
  repeat(4) @(negedge clk); reset=0;
  wait(dut.message_active); wait(!dut.message_active);
  repeat(2500) @(negedge clk);
  force dut.second_count=25'd25199999;
  @(posedge clk); #1; release dut.second_count;
  for(i=0;i<119;i=i+1) begin
   @(negedge tx);
   repeat(328) @(posedge clk);
   for(b=0;b<8;b=b+1) begin
    #1; received[b]=tx;
    repeat(219) @(posedge clk);
   end
   if(received!==expected[8*(118-i)+:8]) $fatal(1,"UART byte %0d got %h expected %h",i,received,expected[8*(118-i)+:8]);
  end
  $display("PASS: UART emits complete 119-byte PC/SD/video/MMU snapshot at 115200 baud");
  $finish;
 end
 initial begin #6000000; $fatal(1,"UART timeout"); end
endmodule
