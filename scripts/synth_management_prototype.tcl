# Out-of-context evaluation only: no physical pins or CoCo build are changed.
source [file join [file dirname [info script]] generate_management_ip.tcl]
read_verilog [file join $repo rtl management usb_host_spi.v]
read_verilog [file join $repo rtl management management_prototype.v]
synth_design -top management_prototype -part xc7a100tfgg676-2 -mode out_of_context
create_clock -name management_clk -period 20.000 [get_ports clk_50mhz]
report_utilization -file [file join $work utilization_synth.rpt]
report_timing_summary -file [file join $work timing_synth.rpt]
write_checkpoint -force [file join $work management_prototype_synth.dcp]
puts "PASS: isolated management synthesis (not placed/routed; no boot firmware)"
