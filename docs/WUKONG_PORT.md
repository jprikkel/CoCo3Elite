# QMTECH Wukong v2 port notes

## Standalone HDMI checkpoint

This source set targets the QMTECH Wukong revision 2 board populated with an
Artix-7 `XC7A100T-2FGG676`. It is deliberately independent of all legacy CoCo
RTL, DDR3, SD, Ethernet, serial, PS/2, buttons, switches, and PMOD connectors.

Pin provenance is the QMTECH v2 material mirrored at
[DavidJRichards/QMTECH_XC7A100T_Wukong_Board](https://github.com/DavidJRichards/QMTECH_XC7A100T_Wukong_Board):

- `Documents/QMTECH-XC7A100T_200T-Wukong-Board-V02-20210426.pdf`
- `board/wukong-xc7a100t.xdc`
- `board/Wukong/1.0/part0_pins.xml`
- `Litex/platforms/qmtech_wukong.py`

The constraint and LiteX platform files independently agree on the following
revision-2 pins:

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

## XC7A200T compatibility

`scripts/build_wukong.tcl` accepts a part name as its first Tcl argument. The
default is `xc7a100tfgg676-2`. A Wukong v2 XC7A200T build can be requested with
the exact part fitted to that board (commonly `xc7a200tfbg676-2`), but package
pin compatibility must be confirmed against its board documentation before
programming.
