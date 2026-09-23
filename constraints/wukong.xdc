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

# Passive Atari/C64-style digital joystick on PMOD J10. Each contact is
# active-low and closes to ground. J10 pin 8 is an optional second button and
# must only be connected through a passive-switch adapter.
set_property -dict { PACKAGE_PIN D5 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_up_n]
set_property -dict { PACKAGE_PIN G5 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_down_n]
set_property -dict { PACKAGE_PIN G7 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_left_n]
set_property -dict { PACKAGE_PIN G8 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_right_n]
set_property -dict { PACKAGE_PIN E5 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_button1_n]
set_property -dict { PACKAGE_PIN E6 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports joystick_button2_n]
set_false_path -from [get_ports {joystick_up_n joystick_down_n joystick_left_n joystick_right_n joystick_button1_n joystick_button2_n}]

# MicroSD pins are selected by exactly one of the shared wukong_sd_*.xdc
# fragments. The normal build defaults to the onboard socket.

# Onboard 32 MB Winbond W9825G6KH-6 SDR SDRAM. Pin assignments are from the
# official QMTECH Wukong V3 Test10_SDRAM project. The controller uses a
# synchronous 126 MHz 5x pixel clock and forwards an inverted copy so commands
# setup at the SDRAM pins. CAS latency two and strict
# video-request priority keep each fixed-schedule GIME fetch inside its window.
set_property -dict { PACKAGE_PIN G22 IOSTANDARD LVCMOS33 } [get_ports sdram_clk]
set_property -dict { PACKAGE_PIN H22 IOSTANDARD LVCMOS33 } [get_ports sdram_cke]
set_property -dict { PACKAGE_PIN L25 IOSTANDARD LVCMOS33 } [get_ports sdram_cs_n]
set_property -dict { PACKAGE_PIN K26 IOSTANDARD LVCMOS33 } [get_ports sdram_ras_n]
set_property -dict { PACKAGE_PIN K25 IOSTANDARD LVCMOS33 } [get_ports sdram_cas_n]
set_property -dict { PACKAGE_PIN J26 IOSTANDARD LVCMOS33 } [get_ports sdram_we_n]
set_property -dict { PACKAGE_PIN J25 IOSTANDARD LVCMOS33 } [get_ports {sdram_dqm[0]}]
set_property -dict { PACKAGE_PIN K23 IOSTANDARD LVCMOS33 } [get_ports {sdram_dqm[1]}]

set_property -dict { PACKAGE_PIN R26 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[0]}]
set_property -dict { PACKAGE_PIN P25 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[1]}]
set_property -dict { PACKAGE_PIN P26 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[2]}]
set_property -dict { PACKAGE_PIN N26 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[3]}]
set_property -dict { PACKAGE_PIN M24 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[4]}]
set_property -dict { PACKAGE_PIN M22 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[5]}]
set_property -dict { PACKAGE_PIN L24 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[6]}]
set_property -dict { PACKAGE_PIN L23 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[7]}]
set_property -dict { PACKAGE_PIN L22 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[8]}]
set_property -dict { PACKAGE_PIN K21 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[9]}]
set_property -dict { PACKAGE_PIN R25 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[10]}]
set_property -dict { PACKAGE_PIN K22 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[11]}]
set_property -dict { PACKAGE_PIN J21 IOSTANDARD LVCMOS33 } [get_ports {sdram_address[12]}]
set_property -dict { PACKAGE_PIN M25 IOSTANDARD LVCMOS33 } [get_ports {sdram_bank[0]}]
set_property -dict { PACKAGE_PIN M26 IOSTANDARD LVCMOS33 } [get_ports {sdram_bank[1]}]

set_property -dict { PACKAGE_PIN D25 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[0]}]
set_property -dict { PACKAGE_PIN D26 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[1]}]
set_property -dict { PACKAGE_PIN E25 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[2]}]
set_property -dict { PACKAGE_PIN E26 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[3]}]
set_property -dict { PACKAGE_PIN F25 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[4]}]
set_property -dict { PACKAGE_PIN G25 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[5]}]
set_property -dict { PACKAGE_PIN G26 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[6]}]
set_property -dict { PACKAGE_PIN H26 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[7]}]
set_property -dict { PACKAGE_PIN J24 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[8]}]
set_property -dict { PACKAGE_PIN J23 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[9]}]
set_property -dict { PACKAGE_PIN H24 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[10]}]
set_property -dict { PACKAGE_PIN H23 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[11]}]
set_property -dict { PACKAGE_PIN G24 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[12]}]
set_property -dict { PACKAGE_PIN F24 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[13]}]
set_property -dict { PACKAGE_PIN F23 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[14]}]
set_property -dict { PACKAGE_PIN E23 IOSTANDARD LVCMOS33 } [get_ports {sdram_data[15]}]

# Onboard CH340N USB-to-UART bridge. TX carries diagnostics and management
# replies; RX feeds the RV32 automation command service.
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports uart_rx]
set_false_path -from [get_ports uart_rx]

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
