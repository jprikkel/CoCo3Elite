# Reproducible non-project build for Wukong HDMI targets.
# Usage: vivado -mode batch -source scripts/build_wukong.tcl
# Override part/mode: vivado -mode batch -source ... -tclargs <part> BASIC_6809_DVI_TEST

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set rtl_dir    [file join $repo_dir rtl wukong]
set output_dir [file join $repo_dir build wukong]
set part       [expr {$argc > 0 ? [lindex $argv 0] : "xc7a100tfgg676-2"}]
set mode       [string toupper [expr {$argc > 1 ? [lindex $argv 1] : "COCO3_ELITE"}]]
set embedded_test_disks [expr {$argc > 2 ? [lindex $argv 2] : 0}]
set top        wukong_top

# Allow Vivado implementation phases to use the available host cores. Some
# synthesis algorithms retain an internal two-thread cap in Vivado 2025.2.
set_param general.maxThreads 8

if {$mode ni {HDMI_TEST_PATTERN COCO3_ELITE BASIC_6809_DVI_TEST}} {
    error "Unknown mode '$mode'; use HDMI_TEST_PATTERN, COCO3_ELITE, or BASIC_6809_DVI_TEST"
}

file mkdir $output_dir

set sources [list \
    [file join $rtl_dir clocking.v] \
    [file join $rtl_dir hdmi test_pattern.v] \
    [file join $rtl_dir hdmi tmds_serializer.v]]
set systemverilog_sources [list [file join $rtl_dir wukong_top.v]]

set hdmi_library_dir [file join $repo_dir rtl third-party hdl-util-hdmi src]
set hdmi_sources [glob -nocomplain [file join $hdmi_library_dir *.sv]]
if {[llength $hdmi_sources] == 0} {
    error "hdl-util/hdmi sources not found at $hdmi_library_dir"
}

if {$mode eq "HDMI_TEST_PATTERN"} {
    set_property verilog_define {HDMI_TEST_PATTERN HDMI_LIBRARY_AUDIO} [current_fileset]
}

if {$mode in {COCO3_ELITE BASIC_6809_DVI_TEST}} {
    lappend sources \
        [file join $repo_dir rtl core coco3_char_rom.v] \
        [file join $repo_dir rtl third-party coco3fpga coco3vid.v]
}

if {$mode eq "COCO3_ELITE"} {
    set rom_mem [file join $repo_dir build roms coco3.mem]
    if {![file exists $rom_mem]} {
        error "Prepared ROM not found at $rom_mem; run scripts/prepare_coco3_rom.ps1"
    }
    set disk_rom_mem [file join $repo_dir build roms disk11.mem]
    if {![file exists $disk_rom_mem]} {
        error "Prepared Disk BASIC ROM not found at $disk_rom_mem; run scripts/prepare_disk_rom.ps1"
    }
    lappend sources \
        {*}[lsort [glob [file join $repo_dir rtl third-party ultraembedded-riscv core riscv *.v]]] \
        {*}[lsort [glob [file join $repo_dir rtl third-party ultraembedded-riscv top_tcm_axi src_v *.v]]] \
        [file join $repo_dir rtl third-party PS2_Key ps2_keyboard.v] \
        [file join $repo_dir rtl third-party coco3fpga cocokey.v] \
        [file join $repo_dir rtl core coco3_keyboard_matrix.v] \
        [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco3_system_rom.v] \
        [file join $repo_dir rtl core coco3_disk_rom.v] \
        [file join $repo_dir rtl core coco3_diagnostic_cartridge.v] \
        [file join $repo_dir rtl management manager_sd_mmio.v] \
        [file join $repo_dir rtl management ultraembedded_manager_sd_mount.v] \
        [file join $repo_dir rtl management manager_osd.v] \
        [file join $repo_dir rtl core coco3_fdc.v] \
        [file join $repo_dir rtl core coco3_gime_timer.v] \
        [file join $repo_dir rtl core coco3_gime_interrupt.v] \
        [file join $repo_dir rtl core coco3_boot_machine.v] \
        [file join $rtl_dir uart_tx.v] \
        [file join $rtl_dir coco3_uart_debug.v] \
        [file join $rtl_dir ntsc_artifact_filter.v] \
        [file join $rtl_dir crt_filter.v] \
        [file join $rtl_dir coco3_boot_system.v]
    set coco3_defines {NEW_SRAM HDMI_TEST_PATTERN HDMI_LIBRARY_COCO HDMI_LIBRARY_AUDIO HDMI_RASTER_800X525}
    set_property include_dirs [list [file join $repo_dir rtl third-party ultraembedded-riscv core riscv] $output_dir] [current_fileset]
    if {$embedded_test_disks} {
        lappend coco3_defines EMBEDDED_TEST_DISKS
    }
    set_property verilog_define $coco3_defines [current_fileset]
    read_verilog [file join $repo_dir rtl third-party MC6809 mc6809i.v]
    read_verilog [file join $repo_dir rtl core cpu09.v]
}

if {$mode eq "BASIC_6809_DVI_TEST"} {
    lappend sources \
        [file join $repo_dir rtl core coco3_128k_ram.v] \
        [file join $repo_dir rtl core coco3_diagnostic_rom.v] \
        [file join $rtl_dir coco3_diagnostic_system.v]
    set_property verilog_define BASIC_6809_DVI_TEST [current_fileset]
    read_verilog [file join $repo_dir rtl third-party MC6809 mc6809i.v]
    read_verilog [file join $repo_dir rtl core cpu09.v]
}

read_verilog $sources
read_verilog -sv [concat $systemverilog_sources $hdmi_sources]
read_xdc [file join $repo_dir constraints wukong.xdc]
if {$mode in {HDMI_TEST_PATTERN COCO3_ELITE}} {
    read_xdc [file join $repo_dir constraints wukong_audio.xdc]
}

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

set bit_name [expr {$mode eq "COCO3_ELITE"
                    ? "wukong_coco3_elite.bit"
                    : ($mode eq "HDMI_TEST_PATTERN"
                       ? "wukong_hdmi_test_pattern.bit"
                       : "wukong_basic_6809_dvi_test.bit")}]
write_bitstream -force [file join $output_dir $bit_name]
puts "Wrote [file join $output_dir $bit_name] for $part in $mode mode"
