# Standalone UltraEmbedded-management smoke image: oscillator and the
# FPGA-to-PC direction of the onboard CH340N USB-to-UART bridge only.
set_property -dict { PACKAGE_PIN M21 IOSTANDARD LVCMOS33 } [get_ports clk_50mhz]
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
