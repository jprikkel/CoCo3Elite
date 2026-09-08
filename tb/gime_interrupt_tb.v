`timescale 1ns/1ps
module gime_interrupt_tb;
 reg clock=0, reset=1;
 reg irq_master=0, firq_master=0, irq_ack=0, firq_ack=0;
 reg legacy_irq=0, legacy_firq=0;
 reg [5:0] irq_enable=0, firq_enable=0, events=0;
 wire [5:0] irq_status, firq_status;
 wire cpu_irq, cpu_firq;
 always #5 clock=~clock;

 coco3_gime_interrupt dut(
  .clock(clock),.reset(reset),
  .irq_master_enable(irq_master),.firq_master_enable(firq_master),
  .irq_enable(irq_enable),.firq_enable(firq_enable),
  .event_pulse(events),.irq_ack(irq_ack),.firq_ack(firq_ack),
  .legacy_irq(legacy_irq),.legacy_firq(legacy_firq),
  .irq_status(irq_status),.firq_status(firq_status),
  .cpu_irq(cpu_irq),.cpu_firq(cpu_firq));

 initial begin
  repeat(2) @(posedge clock); reset=0;

  legacy_irq=1; legacy_firq=1; #1;
  if(!cpu_irq || !cpu_firq) $fatal(1,"FAIL: legacy routing");
  irq_master=1; firq_master=1; #1;
  if(cpu_irq || cpu_firq) $fatal(1,"FAIL: master routing did not select GIME");

  // Zenix enables vertical-border IRQ (bit 3) and timer FIRQ (bit 5).
  irq_enable=6'b001000; firq_enable=6'b100000;
  events=6'b101000; @(posedge clock); #1; events=0;
  if(irq_status!==6'b101000 || firq_status!==6'b101000)
   $fatal(1,"FAIL: event pending latch");
  if(!cpu_irq || !cpu_firq) $fatal(1,"FAIL: enabled Zenix interrupt routing");

  irq_ack=1; @(posedge clock); #1; irq_ack=0;
  if(irq_status!==0 || cpu_irq) $fatal(1,"FAIL: FF92 acknowledge");
  if(firq_status!==6'b101000 || !cpu_firq)
   $fatal(1,"FAIL: FF92 incorrectly cleared FIRQ status");

  firq_ack=1; @(posedge clock); #1; firq_ack=0;
  if(firq_status!==0 || cpu_firq) $fatal(1,"FAIL: FF93 acknowledge");

  // Disabled sources remain visible in status but do not assert the CPU line.
  events=6'b000010; @(posedge clock); #1; events=0;
  if(irq_status!==6'b000010 || firq_status!==6'b000010)
   $fatal(1,"FAIL: disabled source was not latched");
  if(cpu_irq || cpu_firq) $fatal(1,"FAIL: disabled source asserted CPU line");

  $display("PASS: GIME IRQ/FIRQ enables, status, acknowledge, and master routing");
  $finish;
 end
endmodule
