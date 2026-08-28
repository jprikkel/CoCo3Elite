# QMTECH Wukong V3 port notes

## Standalone HDMI checkpoint

This source set targets the QMTECH Wukong V3 board populated with an Artix-7
`XC7A100T` in the FGG676 package. It is deliberately independent of all legacy CoCo
RTL, DDR3, SD, Ethernet, serial, PS/2, buttons, switches, and PMOD connectors.

Pin provenance is the vendor V3 material stored in this repository:

- `docs/QMTECH_Artix-7_XC7A100T_Wukong_Board_V3_User_Manual(Hardware)_V01.pdf`
- `docs/QMTECH_Artix-7_XC7A100T_Wukong_Board_V3_User_Manual(Experiments)-V01.pdf`
- `docs/QMTECH_Artix-7_XC7A100T_Wukong_Board_V3_User_Manual(Vivado2018.3)-V01.pdf`

The following V3 pins are used by the hardware-verified HDMI build:

| Signal | Positive pin | Negative pin | Standard |
|---|---:|---:|---|
| 50 MHz oscillator | M21 | - | LVCMOS33 |
| TMDS data 0 (blue/control) | E1 | D1 | TMDS_33 |
| TMDS data 1 (green) | F2 | E2 | TMDS_33 |
| TMDS data 2 (red) | G2 | G1 | TMDS_33 |
| TMDS clock | D4 | C4 | TMDS_33 |

The HDMI DDC, CEC, and hot-plug pins are intentionally unused. A DVI-compatible
TMDS display path does not require them for this fixed test image.

## Video and clock architecture

The initial mode uses standard 640x480 progressive timing:

- 640 active pixels, 16 front porch, 96 negative sync, 48 back porch
- 480 active lines, 10 front porch, 2 negative sync, 33 back porch
- 800 x 525 total
- 25.000 MHz pixel clock, approximately 59.52 Hz refresh
- 125.000 MHz serializer clock with double-data-rate output (250 Mb/s/lane)

An `MMCME2_BASE` derives both clocks from the 50 MHz oscillator:

```text
VCO = 50 MHz / 1 * 15 = 750 MHz
pixel = 750 MHz / 30 = 25 MHz
serializer = 750 MHz / 6 = 125 MHz
```

Both outputs and feedback use global buffers. Four 10:1 serializers emit the
three TMDS channels and forwarded pixel clock using `OSERDESE2`; `OBUFDS`
drives the differential pins.

Reset has no external dependency. Loss of MMCM lock asynchronously clears the
lock synchronizer and startup counter. After lock is synchronized into the
pixel domain, reset remains asserted for 256 pixel clocks. The raster then
starts at coordinate (0,0) and continuously displays color bars, a checker
region, a 64-pixel grid, and a white border.

This clock block is only the HDMI checkpoint clocking. It makes no decision
about the later CoCo `PH_2` architecture.

## Vivado part selection

`scripts/build_wukong.tcl` accepts a part name as its first Tcl argument. The
default is `xc7a100tfgg676-2`, matching the setting used for the verified
bitstream. The V3 manual describes an `XC7A100T-1FGG676C`; check the marking on
the fitted FPGA before relying on speed-grade-specific timing. A different
speed grade can be passed as the first Tcl argument without changing the board
pin assignments.

The four V3 PMOD connector pinouts are recorded in
`hardware/wukong-pmod-pinout.md`. J13 is assigned to the external Digilent
Pmod MicroSD and J14 to the PS/2 keyboard.
