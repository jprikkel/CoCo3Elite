# Reproducible non-project build for the standalone Wukong HDMI checkpoint.
# Usage: vivado -mode batch -source scripts/build_wukong.tcl
# Override part/mode: vivado -mode batch -source ... -tclargs <part> COCO_VIDEO

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set rtl_dir    [file join $repo_dir rtl wukong]
set output_dir [file join $repo_dir build wukong]
set part       [expr {$argc > 0 ? [lindex $argv 0] : "xc7a100tfgg676-2"}]
set mode       [string toupper [expr {$argc > 1 ? [lindex $argv 1] : "TEST_PATTERN"}]]
set embedded_test_disks [expr {$argc > 2 ? [lindex $argv 2] : 0}]
set top        wukong_top

# Allow Vivado implementation phases to use the available host cores. Some
# synthesis algorithms retain an internal two-thread cap in Vivado 2025.2.
set_param general.maxThreads 8

if {$mode ni {TEST_PATTERN HDMI_LIBRARY_TEST HDMI_COCO_TEST HDMI_COCO_AUDIO COCO_VIDEO CPU_DIAGNOSTIC COCO3_BOOT}} {
    error "Unknown video mode '$mode'; use TEST_PATTERN, HDMI_LIBRARY_TEST, HDMI_COCO_TEST, HDMI_COCO_AUDIO, COCO_VIDEO, CPU_DIAGNOSTIC, or COCO3_BOOT"
}

file mkdir $output_dir

set sources [list \
    [file join $rtl_dir clocking.v] \
    [file join $rtl_dir hdmi video_timing.v] \
    [file join $rtl_dir hdmi test_pattern.v] \
    [file join $rtl_dir hdmi tmds_serializer.v]]
set systemverilog_sources [list \
    [file join $rtl_dir wukong_top.v] \
    [file join $rtl_dir wukong_hdmi_tx.sv]]

set hdmi_library_dir [file join $repo_dir rtl third_party hdl-util-hdmi src]
set hdmi_sources [glob -nocomplain [file join $hdmi_library_dir *.sv]]
if {[llength $hdmi_sources] == 0} {
    error "hdl-util/hdmi sources not found at $hdmi_library_dir"
}

if {$mode eq "HDMI_LIBRARY_TEST"} {
    set_property verilog_define HDMI_LIBRARY_TEST [current_fileset]
}

if {$mode in {HDMI_COCO_TEST HDMI_COCO_AUDIO}} {
    set_property verilog_define {HDMI_LIBRARY_TEST HDMI_LIBRARY_COCO} [current_fileset]
}

if {$mode in {HDMI_COCO_TEST HDMI_COCO_AUDIO COCO_VIDEO CPU_DIAGNOSTIC COCO3_BOOT}} {
    lappend sources \
        [file join $repo_dir rtl core coco3_char_rom.v] \
        [file join $repo_dir rtl core coco3_synthetic_video_ram.v] \
        [file join $repo_dir rtl coco3vid.v] \
        [file join $rtl_dir coco_video_source.v]
    set_property verilog_define COCO_VIDEO [current_fileset]
}

if {$mode in {COCO3_BOOT HDMI_COCO_TEST HDMI_COCO_AUDIO}} {
    set rom_mem [file join $repo_dir build roms coco3.mem]
    if {![file exists $rom_mem]} {
        error "Prepared ROM not found at $rom_mem; run scripts/prepare_coco3_rom.ps1"
    }
    set disk_rom_mem [file join $repo_dir build roms disk11.mem]
    if {![file exists $disk_rom_mem]} {
        error "Prepared Disk BASIC ROM not found at $disk_rom_mem; run scripts/prepare_disk_rom.ps1"
    }
    lappend sources \
        [file join $repo_dir rtl ps2_keyboard.v] \
        [file join $repo_dir rtl cocokey.v] \
        [file join $repo_dir rtl core coco3_keyboard_matrix.v] \
        [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco3_system_rom.v] \
        [file join $repo_dir rtl core coco3_disk_rom.v] \
        [file join $repo_dir rtl core coco3_diagnostic_cartridge.v] \
        [file join $repo_dir rtl core coco3_disk_image.v] \
        [file join $repo_dir rtl core sd_spi_init.v] \
        [file join $repo_dir rtl core sd_spi_read_sector0.v] \
        [file join $repo_dir rtl core coco3_fdc.v] \
        [file join $repo_dir rtl core coco3_gime_timer.v] \
        [file join $repo_dir rtl core coco3_boot_machine.v] \
        [file join $rtl_dir uart_tx.v] \
        [file join $rtl_dir coco3_uart_debug.v] \
        [file join $rtl_dir ntsc_artifact_filter.v] \
        [file join $rtl_dir crt_filter.v] \
        [file join $rtl_dir coco3_boot_system.v]
    set coco3_defines {COCO3_BOOT NEW_SRAM}
    if {$mode in {HDMI_COCO_TEST HDMI_COCO_AUDIO}} {
        lappend coco3_defines HDMI_LIBRARY_TEST HDMI_LIBRARY_COCO HDMI_RASTER_800X525
    }
    if {$mode eq "HDMI_COCO_AUDIO"} {
        lappend coco3_defines HDMI_LIBRARY_AUDIO
    }
    if {$embedded_test_disks} {
        lappend coco3_defines EMBEDDED_TEST_DISKS
    }
    set_property verilog_define $coco3_defines [current_fileset]
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
read_verilog -sv [concat $systemverilog_sources $hdmi_sources]
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

set bit_name [expr {$mode eq "COCO3_BOOT" ? "wukong_coco3_boot.bit" :
                    ($mode eq "CPU_DIAGNOSTIC" ? "wukong_cpu_diagnostic.bit" :
                    ($mode eq "COCO_VIDEO" ? "wukong_coco_video.bit" :
                    ($mode eq "HDMI_LIBRARY_TEST" ? "wukong_hdmi_library_test.bit" :
                    ($mode eq "HDMI_COCO_TEST" ? "wukong_hdmi_coco_test.bit" :
                    ($mode eq "HDMI_COCO_AUDIO" ? "wukong_hdmi_coco_audio.bit" : "wukong_hdmi_test.bit")))))}]
write_bitstream -force [file join $output_dir $bit_name]
puts "Wrote [file join $output_dir $bit_name] for $part in $mode mode"
