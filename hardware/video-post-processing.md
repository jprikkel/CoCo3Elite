# HDMI Video Post-Processing

The Wukong HDMI output applies optional streaming video processing after the
CoCo 3 video generator. The processing order is:

1. CoCo 3 RGB video generation
2. NTSC artifact-color decoding
3. CRT phosphor glow and scanline filtering
4. HDMI TMDS encoding and serialization

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
