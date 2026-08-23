# Reproducible non-project build for the standalone Wukong HDMI checkpoint.
# Usage: vivado -mode batch -source scripts/build_wukong.tcl
# Override part: vivado -mode batch -source ... -tclargs xc7a200tfbg676-2

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set rtl_dir    [file join $repo_dir rtl wukong]
set output_dir [file join $repo_dir build wukong]
set part       [expr {$argc > 0 ? [lindex $argv 0] : "xc7a100tfgg676-2"}]
set top        wukong_top

file mkdir $output_dir

read_verilog [list \
    [file join $rtl_dir wukong_top.v] \
    [file join $rtl_dir clocking.v] \
    [file join $rtl_dir hdmi video_timing.v] \
    [file join $rtl_dir hdmi test_pattern.v] \
    [file join $rtl_dir hdmi tmds_encoder.v] \
    [file join $rtl_dir hdmi tmds_serializer.v]]
read_xdc [file join $repo_dir constraints wukong.xdc]

synth_design -top $top -part $part
write_checkpoint -force [file join $output_dir post_synth.dcp]
report_utilization -file [file join $output_dir post_synth_utilization.rpt]

opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $output_dir routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $output_dir timing_summary.rpt]
report_drc -file [file join $output_dir drc.rpt]
report_utilization -file [file join $output_dir routed_utilization.rpt]

set worst_path [get_timing_paths -max_paths 1]
if {[llength $worst_path] == 0} {
    error "No timed paths found; bitstream not generated"
}
set worst_slack [get_property SLACK $worst_path]
if {$worst_slack < 0} {
    error "Timing failed; bitstream not generated"
}

write_bitstream -force [file join $output_dir wukong_hdmi_test.bit]
puts "Wrote [file join $output_dir wukong_hdmi_test.bit] for $part"
