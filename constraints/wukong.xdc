# QMTECH Wukong V3, XC7A100T-FGG676.
# Pin source: the vendor V3 manuals under docs/, as summarized in
# docs/WUKONG_PORT.md. Only the no-wiring HDMI milestone pins are constrained.

set_property -dict { PACKAGE_PIN M21 IOSTANDARD LVCMOS33 } [get_ports clk_50mhz]
create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]

# PS/2 keyboard on PMOD J14 using the Digilent Pmod PS/2 signal layout.
# Both signals are open-drain and idle high.
set_property -dict { PACKAGE_PIN P23 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ps2_data]
set_property -dict { PACKAGE_PIN T24 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ps2_clk]
set_false_path -from [get_ports {ps2_clk ps2_data}]

# Keep the reusable PS/2 RTL vendor-neutral. These four registers form the
# two-stage clock and data synchronizers inside the KEYBOARD instance.
set_property ASYNC_REG TRUE [get_cells -quiet -hier -filter {
    NAME =~ */KEYBOARD/KB_CLK_reg* ||
    NAME =~ */KEYBOARD/KB_CLK_B_reg ||
    NAME =~ */KEYBOARD/KB_DATA_reg ||
    NAME =~ */KEYBOARD/KB_DATA_B_reg
}]

# Digilent Pmod MicroSD on J13 (standard Type-2 SPI layout).
set_property -dict { PACKAGE_PIN N22 IOSTANDARD LVCMOS33 } [get_ports sd_cs_n]
set_property -dict { PACKAGE_PIN N21 IOSTANDARD LVCMOS33 } [get_ports sd_mosi]
set_property -dict { PACKAGE_PIN R20 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports sd_miso]
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 } [get_ports sd_sck]
set_false_path -from [get_ports sd_miso]

# Onboard CH340N USB-to-UART bridge. TX is the FPGA-to-PC direction used by
# the passive diagnostic console; RX (F3) is deliberately left unused.
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports uart_tx]

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
