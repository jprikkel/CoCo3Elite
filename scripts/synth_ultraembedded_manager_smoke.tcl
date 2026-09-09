# Out-of-context resource/timing check only. This does not alter the CoCo top
# level, constraints, pins, or boot image.
set script_dir [file normalize [file dirname [info script]]]
set repo [file normalize [file join $script_dir ..]]
set work [file join $repo build management ultraembedded-smoke]
set core [file join $repo rtl third-party ultraembedded-riscv core riscv]
set tcm [file join $repo rtl third-party ultraembedded-riscv top_tcm_axi src_v]
file mkdir $work

set sources [concat [lsort [glob [file join $core *.v]]] \
                    [lsort [glob [file join $tcm *.v]]] \
                    [list [file join $repo rtl management ultraembedded_manager_smoke.v]]]
set_property include_dirs [list $core] [current_fileset]
read_verilog $sources
synth_design -top ultraembedded_manager_smoke -part xc7a100tfgg676-2 -mode out_of_context
create_clock -name management_clk -period 20.000 [get_ports clock]
report_utilization -file [file join $work utilization_synth.rpt]
report_timing_summary -file [file join $work timing_synth.rpt]
write_checkpoint -force [file join $work ultraembedded_manager_smoke_synth.dcp]
puts "PASS: UltraEmbedded RV32IM management smoke synthesis (isolated)"
