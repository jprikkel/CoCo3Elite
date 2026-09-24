# Adafruit Floppy FeatherWing read-only interface on Wukong V3 PMOD J13.
# This fragment is mutually exclusive with constraints/wukong_sd_pmod.xdc.
# The normal physical-floppy build keeps SD on the onboard socket.

# FPGA-to-FeatherWing controls. Safe reset values are driven by
# pmod_floppy_read_only; select, motor, and step are active low.
set_property -dict { PACKAGE_PIN N22 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports floppy_select_n]
set_property -dict { PACKAGE_PIN N21 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports floppy_motor_enable_n]
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports floppy_direction]
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports floppy_step_n]
set_property -dict { PACKAGE_PIN N23 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports floppy_side_select]

# FeatherWing-to-FPGA signals. The FeatherWing already provides 3.3 V level
# translation and pull-ups; FPGA pull-ups preserve an inactive state if the
# interposer is absent during bring-up.
set_property -dict { PACKAGE_PIN R20 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports floppy_read_data_n]
set_property -dict { PACKAGE_PIN P21 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports floppy_track_zero_n]
set_property -dict { PACKAGE_PIN R21 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports floppy_index_n]
set_false_path -from [get_ports {floppy_read_data_n floppy_track_zero_n floppy_index_n}]
