# QMTECH Wukong V3 onboard MicroSD socket in SPI mode.
# Exactly one wukong_sd_*.xdc fragment must be loaded by a build.
# The Wukong V2/V3 FPGA routing names these signals differently from the
# connector-order table: J8 is CMD and L4 is CLK. In SPI mode D3 is CS,
# CMD is MOSI, D0 is MISO, and CLK is SCK.
set_property -dict { PACKAGE_PIN J6 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports sd_cs_n]
set_property -dict { PACKAGE_PIN J8 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports sd_mosi]
set_property -dict { PACKAGE_PIN M5 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports sd_miso]
set_property -dict { PACKAGE_PIN L4 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports sd_sck]
set_false_path -from [get_ports sd_miso]
