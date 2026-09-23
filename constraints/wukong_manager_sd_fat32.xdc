# Standalone RV32 firmware-driven SD/FAT32 test: UART and selected MicroSD only.
set_property -dict { PACKAGE_PIN M21 IOSTANDARD LVCMOS33 } [get_ports clk_50mhz]
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
# MicroSD pins are selected by exactly one of the shared wukong_sd_*.xdc
# fragments. The standalone build also defaults to the onboard socket.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
