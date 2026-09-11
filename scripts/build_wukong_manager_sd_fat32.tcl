set script_dir [file normalize [file dirname [info script]]]
set repo [file normalize [file join $script_dir ..]]
set work [file join $repo build wukong-manager-sd-fat32]
set core [file join $repo rtl third-party ultraembedded-riscv core riscv]
set tcm [file join $repo rtl third-party ultraembedded-riscv top_tcm_axi src_v]
file mkdir $work
set_param general.maxThreads 8
set sources [concat [lsort [glob [file join $core *.v]]] [lsort [glob [file join $tcm *.v]]] \
    [list [file join $repo rtl management manager_sd_mmio.v] \
          [file join $repo rtl management ultraembedded_manager_sd_fat32.v] \
          [file join $repo rtl management wukong_manager_sd_fat32_top.v] \
          [file join $repo rtl wukong uart_tx.v]]]
set_property include_dirs [list $core $work] [current_fileset]
read_verilog $sources
read_xdc [file join $repo constraints wukong_manager_sd_fat32.xdc]
synth_design -top wukong_manager_sd_fat32_top -part xc7a100tfgg676-2
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $work timing_summary.rpt]
report_utilization -file [file join $work utilization.rpt]
report_drc -file [file join $work drc.rpt]
set worst_path [get_timing_paths -max_paths 1]
if {[llength $worst_path] == 0 || [get_property SLACK $worst_path] < 0} { error "Timing failed; bitstream not generated" }
write_bitstream -force [file join $work wukong_manager_sd_fat32.bit]
puts "Wrote [file join $work wukong_manager_sd_fat32.bit]"
