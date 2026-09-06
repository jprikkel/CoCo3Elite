# CoCo3Elite QMTECH Wukong V3 port notes

## Board target and active interfaces

This source set targets the QMTECH Wukong V3 board populated with an Artix-7
`XC7A100T` in the FGG676 package. The standalone `TEST_PATTERN` needs only the
oscillator and HDMI. Real-ROM modes also use J14 PS/2, J13 MicroSD probing, and
the onboard USB UART. DDR3, SDRAM, Ethernet, and physical joystick ADCs are
not integrated. See [current implementation](CURRENT_IMPLEMENTATION.md).

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

The local `TEST_PATTERN` uses 640x480 progressive timing:

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

Both outputs and feedback use global buffers. In local modes, four 10:1
serializers emit the
three TMDS channels and forwarded pixel clock using `OSERDESE2`; `OBUFDS`
drives the differential pins.

Reset has no external dependency. Loss of MMCM lock asynchronously clears the
lock synchronizer and startup counter. After lock is synchronized into the
pixel domain, reset remains asserted for 256 pixel clocks. The raster then
starts at coordinate (0,0) and continuously displays color bars, a checker
region, a 64-pixel grid, and a white border.

The three library modes (`HDMI_LIBRARY_TEST`, `HDMI_COCO_TEST`, and
`HDMI_COCO_AUDIO`) instead select these MMCM parameters:

```text
VCO = 50 MHz / 5 * 63 = 630 MHz
pixel = 630 MHz / 25 = 25.2 MHz
serializer = 630 MHz / 5 = 126 MHz
```

Their 800x525 raster runs at 60 Hz. Real CoCo library modes resynchronize the
source at HDMI x=781, y=18 and delay 512-pixel narrow-mode RGB by 64 pixels.
Full-width modes occupy all 640 pixels; there is no implemented 720x480 margin
mode. The library owns HDMI encoding/serialization in these modes; local modes
use `tmds_serializer.v` with OSERDESE2. Board outputs use OBUFDS in both paths.
The CPU uses enables in the BRAM machine rather than the legacy PH2_CLK block.

`HDMI_COCO_AUDIO` enables 48 kHz stereo packet generation, but the latest
recorded hardware build is silent. Other supported modes do not enable audio.
The separate experimental `HDMI_AUDIO` wrapper is not selected by the launcher.

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

## Peripheral pin constraints

| Signal | Connector | Package pin |
| --- | --- | --- |
| PS/2 data | J14 pin 1 | P23 |
| PS/2 clock | J14 pin 3 | T24 |
| MicroSD chip select | J13 pin 1 | N22 |
| MicroSD MOSI | J13 pin 2 | N21 |
| MicroSD MISO | J13 pin 3 | R20 |
| MicroSD clock | J13 pin 4 | T22 |
| FPGA UART transmit | Onboard CH340N | E3 |

These are already assigned in `constraints/wukong.xdc`; UART RX/F3 is unused.
PS/2 inputs have pull-ups, asynchronous input false paths, and receiver
synchronizer attributes. MISO has a pull-up and asynchronous input false path.
Neither PS/2 clock nor SPI clock is declared as a new external timing clock.
See [keyboard wiring](../hardware/keyboard-ps2.md) for voltage requirements.

The MicroSD path currently supports initialization and sector-zero reads only,
not FAT32 DSK mounting. Optional read-only embedded disks are separate local,
untracked inputs. The [build-mode table](CURRENT_IMPLEMENTATION.md#build-modes)
is the reference for filenames and source selection; Tcl arguments are part,
mode, and the embedded-test-disk flag (0 or 1).
