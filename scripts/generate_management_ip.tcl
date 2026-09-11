# Generate the isolated MicroBlaze V management prototype (not the CoCo image).
set repo [file normalize [file join [file dirname [info script]] ..]]
set work [file join $repo build management]
file mkdir $work
file mkdir [file join $work ip]
create_project -in_memory -part xc7a100tfgg676-2
set_property target_language Verilog [current_project]
set xci [file join $work ip management_cpu management_cpu.xci]
if {[file exists $xci]} {
    read_ip $xci
} else {
    create_ip -name microblaze_mcs_riscv -vendor xilinx.com -library ip \
        -version 1.0 -module_name management_cpu -dir [file join $work ip]
}
set_property -dict [list CONFIG.FREQ {50} CONFIG.MEMSIZE {65536} \
    CONFIG.USE_IO_BUS {1} CONFIG.USE_UART_TX {1} CONFIG.UART_BAUDRATE {115200}] \
    [get_ips management_cpu]
# Include the generated RTL in the parent synthesis for this small standalone
# evaluation, instead of requiring separately launched IP synthesis runs.
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips management_cpu]
puts "Management CPU generated in $work"
