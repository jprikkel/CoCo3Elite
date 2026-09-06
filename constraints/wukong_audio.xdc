# HDMI audio modes divide the 25.2 MHz pixel clock by 525 and route the result
# through a BUFG. This file is loaded only for builds that instantiate that
# audio clock tree.
create_generated_clock -name hdmi_audio_clk \
    -source [get_pins clocking_i/pixel_bufg_i/O] \
    -divide_by 525 [get_pins hdmi_audio_bufg_i/O]
