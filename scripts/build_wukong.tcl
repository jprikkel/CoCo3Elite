# Reproducible non-project build for the standalone Wukong HDMI checkpoint.
# Usage: vivado -mode batch -source scripts/build_wukong.tcl
# Override part/mode: vivado -mode batch -source ... -tclargs <part> COCO_VIDEO

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set rtl_dir    [file join $repo_dir rtl wukong]
set output_dir [file join $repo_dir build wukong]
set part       [expr {$argc > 0 ? [lindex $argv 0] : "xc7a100tfgg676-2"}]
set mode       [string toupper [expr {$argc > 1 ? [lindex $argv 1] : "TEST_PATTERN"}]]
set top        wukong_top

if {$mode ni {TEST_PATTERN COCO_VIDEO CPU_DIAGNOSTIC COCO3_BOOT COCO2_BOOT}} {
    error "Unknown video mode '$mode'; use TEST_PATTERN, COCO_VIDEO, CPU_DIAGNOSTIC, or COCO3_BOOT"
}

file mkdir $output_dir

set sources [list \
    [file join $rtl_dir wukong_top.v] \
    [file join $rtl_dir clocking.v] \
    [file join $rtl_dir hdmi video_timing.v] \
    [file join $rtl_dir hdmi test_pattern.v] \
    [file join $rtl_dir hdmi tmds_encoder.v] \
    [file join $rtl_dir hdmi tmds_serializer.v]]

if {$mode in {COCO_VIDEO CPU_DIAGNOSTIC COCO3_BOOT COCO2_BOOT}} {
    lappend sources \
        [file join $repo_dir rtl core coco3_char_rom.v] \
        [file join $repo_dir rtl core coco3_synthetic_video_ram.v] \
        [file join $repo_dir rtl coco3vid.v] \
        [file join $rtl_dir coco_video_source.v]
    set_property verilog_define COCO_VIDEO [current_fileset]
}

if {$mode eq "COCO2_BOOT"} {
    set rom_mem [file join $repo_dir build roms coco2.mem]
    if {![file exists $rom_mem]} { error "Prepared CoCo 2 ROM not found; run scripts/prepare_coco2_rom.ps1" }
    lappend sources [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco2_system_rom.v] \
        [file join $repo_dir rtl core coco2_boot_machine.v] \
        [file join $rtl_dir coco2_boot_system.v]
    set_property verilog_define COCO2_BOOT [current_fileset]
    read_vhdl [file join $repo_dir rtl cpu09l_128.vhd]
}

if {$mode eq "COCO3_BOOT"} {
    set rom_mem [file join $repo_dir build roms coco3.mem]
    if {![file exists $rom_mem]} {
        error "Prepared ROM not found at $rom_mem; run scripts/prepare_coco3_rom.ps1"
    }
    lappend sources \
        [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco3_system_rom.v] \
        [file join $repo_dir rtl core coco3_boot_machine.v] \
        [file join $rtl_dir coco3_boot_system.v]
    set_property verilog_define {COCO3_BOOT NEW_SRAM} [current_fileset]
    read_vhdl [file join $repo_dir rtl cpu09l_128.vhd]
}

if {$mode eq "CPU_DIAGNOSTIC"} {
    lappend sources \
        [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco3_diagnostic_rom.v] \
        [file join $rtl_dir coco3_diagnostic_system.v]
    set_property verilog_define CPU_DIAGNOSTIC [current_fileset]
    read_vhdl [file join $repo_dir rtl cpu09l_128.vhd]
}

read_verilog $sources
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

set bit_name [expr {$mode eq "COCO2_BOOT" ? "wukong_coco2_boot.bit" :
                    ($mode eq "COCO3_BOOT" ? "wukong_coco3_boot.bit" :
                    ($mode eq "CPU_DIAGNOSTIC" ? "wukong_cpu_diagnostic.bit" :
                    ($mode eq "COCO_VIDEO" ? "wukong_coco_video.bit" : "wukong_hdmi_test.bit")))}]
write_bitstream -force [file join $output_dir $bit_name]
puts "Wrote [file join $output_dir $bit_name] for $part in $mode mode"
