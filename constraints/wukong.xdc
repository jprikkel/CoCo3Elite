# QMTECH Wukong v2, XC7A100T-2FGG676.
# Pin source: vendor-derived v2 board definition and schematic listed in
# docs/WUKONG_PORT.md. Only the no-wiring HDMI milestone pins are constrained.

set_property -dict { PACKAGE_PIN M21 IOSTANDARD LVCMOS33 } [get_ports clk_50mhz]
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

set_property -dict { PACKAGE_PIN E1 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_p[0]}]
set_property -dict { PACKAGE_PIN D1 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_n[0]}]
set_property -dict { PACKAGE_PIN F2 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_p[1]}]
set_property -dict { PACKAGE_PIN E2 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_n[1]}]
set_property -dict { PACKAGE_PIN G2 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_p[2]}]
set_property -dict { PACKAGE_PIN G1 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_n[2]}]
set_property -dict { PACKAGE_PIN D4 IOSTANDARD TMDS_33 } [get_ports hdmi_clk_p]
set_property -dict { PACKAGE_PIN C4 IOSTANDARD TMDS_33 } [get_ports hdmi_clk_n]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
