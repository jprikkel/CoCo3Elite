# Digilent Pmod MicroSD on Wukong PMOD J13 (standard Type-2 SPI layout).
# Exactly one wukong_sd_*.xdc fragment must be loaded by a build.
set_property -dict { PACKAGE_PIN N22 IOSTANDARD LVCMOS33 } [get_ports sd_cs_n]
set_property -dict { PACKAGE_PIN N21 IOSTANDARD LVCMOS33 } [get_ports sd_mosi]
set_property -dict { PACKAGE_PIN R20 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports sd_miso]
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 } [get_ports sd_sck]
set_false_path -from [get_ports sd_miso]
