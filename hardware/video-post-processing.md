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

F11 enables or disables artifact-color decoding. It is enabled after FPGA
reset. The decoder targets the CoCo's 256-pixel, one-bit graphics patterns.
Each logical source pixel occupies two 25 MHz HDMI pixel clocks. The decoder
groups two adjacent logical pixels into a four-clock artifact cell and applies
this mapping:

| Source pair | Output |
|---|---|
| `00` | Black/source background |
| `11` | White |
| `01` | Artifact color A (blue by default) |
| `10` | Artifact color B (orange/red by default) |

The decoded value covers both logical pixels in the pair. This models the loss
of individual black and white transitions in an NTSC composite signal and
avoids retaining digital gaps inside an artifact-colored shape. Reversing the
artifact phase exchanges colors A and B.

For compatibility with native CoCo 3 color modes, a `00` pair passes through
the source RGB value. A true monochrome black pair therefore remains black,
while a colored background is not incorrectly forced to black.

## CRT phosphor glow

F10 independently enables or disables horizontal phosphor bloom/glow. Bright
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
[hdl-util/hdmi](../rtl/third_party/hdl-util-hdmi/README.md) SystemVerilog
library. The initial hardware checkpoint combines its unmodified channel
encoder with the existing Wukong raster timing and proven Artix-7 OSERDES
physical layer. This sends DVI-compatible video without HDMI auxiliary data
islands. The project-owned `wukong_hdmi_tx` integration wrapper composes the
unmodified upstream packet modules with that Wukong physical layer for true
HDMI output, but remains experimental and is included only when `HDMI_AUDIO`
is defined.

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
This path is disabled in the default bitstream until its packet timing is
validated in simulation and accepted by the target HDMI sink.

## Open video issues

- The library-owned HDMI raster can leave a short horizontal green line to
  the left of the first character row in 40- and 80-column modes. Raster
  dimensions, frame resynchronization, centering, and CoCo blanking are
  correct enough for stable mode changes, but the remaining one-line artifact
  still needs a pipeline/phase investigation.
