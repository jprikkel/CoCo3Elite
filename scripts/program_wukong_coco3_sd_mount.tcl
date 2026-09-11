set script_dir [file normalize [file dirname [info script]]]
set repo [file normalize [file join $script_dir ..]]
set bitfile [file join $repo build wukong wukong_coco3_elite.bit]
if {![file exists $bitfile]} { error "Missing bitstream: $bitfile" }
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices xc7a100t*]
if {[llength $devices] != 1} { error "Expected one xc7a100t JTAG device, found [llength $devices]" }
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device
puts "Programmed $device with $bitfile"
close_hw_target
disconnect_hw_server
close_hw_manager
