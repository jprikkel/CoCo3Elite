# HDMI Video Post-Processing

The Wukong HDMI output applies optional streaming video processing after the
CoCo 3 video generator. The processing order is:

1. CoCo 3 RGB video generation
2. NTSC artifact-color decoding
3. CRT phosphor glow and scanline filtering
4. HDMI timing, TMDS encoding, and Artix-7 serialization

All stages operate as pipelines and delay their synchronization and active-video
signals along with the pixels. They do not use a framebuffer.

## NTSC artifact-color decoding

F10 enables or disables artifact-color decoding. It is enabled after FPGA
reset. F11 Settings selects Off, Thin, Classic, MAME, XRoar, or Two pass decoding and
one of four artifact color models. The decoder targets the CoCo's 256-pixel,
one-bit graphics patterns.
Each logical source pixel occupies two 25 MHz HDMI pixel clocks. The decoder
groups two adjacent logical pixels into a four-clock artifact cell and applies
this mapping:

| Source pair | Output |
|---|---|
| `00` | Black/source background |
| `11` | White |
| `01` | Artifact color A (blue by default) |
| `10` | Artifact color B (orange/red by default) |

Classic mode covers both logical pixels in the pair. This models the loss
of individual black and white transitions in an NTSC composite signal and
avoids retaining digital gaps inside an artifact-colored shape. Reversing the
artifact phase exchanges colors A and B. Thin mode colors only the asserted
source half of a transition, retaining the original digital line thickness.

The independently selectable color models are blue/orange, cyan/red,
green/magenta, and violet/lime. They set the phase-color pair used by Thin,
Classic, and Two pass styles. MAME style uses the six-logical-pixel window plus
first/second-output selector required by the 128-entry correction table in
MAME's `src/devices/video/mc6847.cpp`. XRoar style uses the phase-aware
five-logical-pixel cross-colour LUT from `src/vo_render.c` in XRoar. A common
six-HDMI-clock center delay keeps RGB and sync timing aligned while switching
styles live. This is a streaming implementation and adds neither a framebuffer
nor block RAM.

Two pass applies the Thin decoder first, then fills exactly one black output
pixel only when its immediate neighbors are the same blue or orange artifact
phase. White/white, white/chroma, opposite-phase, and gaps wider than one pixel
are unchanged.

The MAME table is derived from BSD-3-Clause source. The XRoar table is derived
from GPL-3.0-or-later source; distribution of a bitstream containing it must
follow the repository's GPL obligations.

For compatibility with native CoCo 3 color modes, a `00` pair passes through
the source RGB value. A true monochrome black pair therefore remains black,
while a colored background is not incorrectly forced to black.

## CoCo 2 palette themes

F11 Settings selects sixteen mappings for CoCo-compatible four-color output.
Every mapping retains exactly four simultaneously active colors:

| Setting | Color 0 | Color 1 | Color 2 | Color 3 |
| --- | --- | --- | --- | --- |
| Original | Native VDG green | Native VDG yellow | Native VDG blue | Native VDG red |
| Base | `#000000` | `#C48A52` | `#783C18` | `#186828` |
| C64 | `#588D43` | `#B8C76F` | `#352879` | `#68372B` |
| Atari | `#489848` | `#E8D878` | `#4040C0` | `#D82800` |
| CGA | `#101010` | `#40C8D0` | `#D050A0` | `#E8E8E0` |
| Earth | `#000000` | `#783C18` | `#186828` | `#B82820` |
| Amber | `#000000` | `#583000` | `#D09020` | `#FFDF80` |
| Cool adventure | `#101820` | `#285080` | `#50C8C8` | `#F0E0B0` |
| CoCo artifact | `#181818` | `#3060E0` | `#E06020` | `#D8D0B8` |
| Forest | `#101810` | `#286040` | `#80B850` | `#E8E090` |
| Fire | `#180C10` | `#702020` | `#D06028` | `#F0D058` |
| Ice | `#101018` | `#303878` | `#68A8D8` | `#E8F0F0` |
| Purple dusk | `#241830` | `#604878` | `#C07088` | `#F0C898` |
| Game Boy | `#182018` | `#405838` | `#88A850` | `#D0D890` |
| Ocean/sunset | `#101838` | `#2858A0` | `#E06858` | `#F0D898` |
| Neutral grayscale | `#101010` | `#505050` | `#A8A8A8` | `#F0F0F0` |

This is a final display mapping: it does not write
the GIME palette registers and is bypassed in native CoCo 3 modes and in the
monochrome artifact-compatible mode.

## CoCo text-color themes

F11 Settings separately offers Original, C64, Atari, VT100, VT220 amber,
VT220 green, IBM, Apple II, Amstrad, and Paperwhite themes. Each preset sets
the foreground, background, and border of the MC6847 32-column alpha screen.
The theme is display-only and deliberately does not recolor bitmap text drawn
inside a graphics mode.

## CRT phosphor glow

Horizontal phosphor bloom/glow remains implemented but has no function-key
toggle in the current build. Bright
pixels above the configured threshold are blended into completed neighboring
pixels. The current level-6 preset uses four previous pixels with decreasing
weights. This is a streaming, left-to-right approximation rather than a
framebuffer-based symmetric convolution.

## Horizontal scanlines

F9 independently enables or disables horizontal scanlines. The current mask
uses two full-brightness output rows followed by one attenuated row. Scanlines
alter brightness only; they do not change source coordinates.

## Available CRT controls

The CRT module exposes 24 phosphor-mask layouts and controls for mask intensity,
bloom size and threshold, corner radius, vignette size and strength, and black
and white levels. Rounded corners and vignetting are disabled in the current
preset. Barrel distortion is not implemented because coordinate remapping
would require line storage or a framebuffer.

See [HDMI CRT Filter](crt-filter.md) for the current preset and the detailed
phosphor-mask options.

## HDMI output library

TMDS channel encoding uses the vendored
[hdl-util/hdmi](../rtl/third-party/hdl-util-hdmi/README.md) SystemVerilog
library. Both hdl-util build modes generate true HDMI data islands and use the
library serializer. `COCO3_ELITE` carries the CoCo DAC samples;
`HDMI_TEST_PATTERN` carries digital silence while displaying its color pattern.

## HDMI audio

The boot machine exports a held six-bit sound DAC value. As on the physical
CoCo, writes to PIA1 port A reach this audio latch only while PIA1 CB2 enables
sound and the analog multiplexer selects the DAC. Joystick polling also sweeps
PIA1's DAC to measure each axis, but those comparator writes are excluded from
the audio latch so continuous `JOYSTK` calls do not produce ticking. The HDMI
wrapper subtracts the midpoint, attenuates the result to one-quarter of the
16-bit PCM range, and duplicates the mono signal into the left and right HDMI
channels. A fractional accumulator resamples the held DAC level at an average
rate of exactly 48 kHz from the 25 MHz pixel clock. The upstream audio sample,
audio clock regeneration, Audio InfoFrame, packet selection, and packet ECC
modules generate the HDMI data islands. Initial volume is deliberately
conservative because hand-generated CoCo DAC waveforms can otherwise be loud.
The build defaults to `COCO3_ELITE`. Its 48 kHz clock is carried on a BUFG
and declared as a generated clock in `constraints/wukong_audio.xdc`.

## Open video issues

- The library-owned HDMI raster can leave a short horizontal green line to
  the left of the first character row in 40- and 80-column modes. Raster
  dimensions, frame resynchronization, centering, and CoCo blanking are
  correct enough for stable mode changes, but the remaining one-line artifact
  still needs a pipeline/phase investigation.
