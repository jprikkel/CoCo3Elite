# CoCo3Elite HDMI video post-processing

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
Each logical source pixel occupies two HDMI pixel clocks (25.2 MHz in the library modes). The decoder
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

## HDMI output paths

`HDMI_COCO_TEST` and `HDMI_COCO_AUDIO` use the unmodified
[hdl-util/hdmi library](../rtl/third_party/hdl-util-hdmi/README.md) instance in
`rtl/wukong/wukong_top.v`. Wukong logic resynchronizes the CoCo raster at
HDMI x=781, y=18 and delays narrow-mode RGB by 64 pixels. The library owns
640x480 active timing in an 800x525 frame at 25.2 MHz, with 126 MHz serialization.

`TEST_PATTERN`, `COCO_VIDEO`, `CPU_DIAGNOSTIC`, and `COCO3_BOOT` retain local
raster timing at 25 MHz and 125 MHz serialization. They use the imported TMDS
channel encoder and local serializer for DVI-compatible video without audio.
The separate `wukong_hdmi_tx.sv` packet wrapper is experimental: it requires
`HDMI_AUDIO`, which none of the supported build modes defines.

## HDMI audio

The boot machine exports a held six-bit sound DAC. Writes to PIA1 port A
reach the audio latch only when sound is enabled and the analog multiplexer
selects the DAC. Joystick comparator sweeps do not update this latch.
`HDMI_COCO_AUDIO` subtracts midpoint 32, shifts by eight into signed 16-bit
PCM, and duplicates mono to both channels. One audio-clock pulse per 525
pixel clocks produces 48 kHz from 25.2 MHz. The library supplies Audio Sample,
Audio Clock Regeneration, Audio InfoFrame, and packet/error-correction logic.

The current hardware build is reported silent despite simulated audio and
clock-regeneration packets. `16d121b` is the recorded last hardware-working
audio checkpoint. Packet presence alone does not establish sink acceptance.
`HDMI_COCO_TEST` and the default `TEST_PATTERN` do not enable audio.

## Known limitations

The standalone `HDMI_LIBRARY_TEST` mode is selectable but currently leaves
its RGB source undriven; use `TEST_PATTERN` for the established standalone
display checkpoint.

- Digital tests cover complete 32/40/80-column placement. Wide modes use all
  640 active pixels, so monitor overscan can still clip characters. A 720x480
  transport with margins is proposed, not implemented.
- CoCo-compatible graphics can show a black left area instead of the selected
  border/background. A previously reported short green line near the first
  text row also needs rechecking on a recorded build.
- The renderer and partial GIME behavior do not yet pass every diagnostic
  video mode. Post-processing is a streaming approximation, not full composite
  signal emulation or geometric CRT remapping.

See [current implementation](../docs/CURRENT_IMPLEMENTATION.md) and
[diagnostic compatibility](../docs/DIAGNOSTIC_COMPATIBILITY_PLAN.md) for test
boundaries and hardware evidence. No new hardware verification is implied by
this documentation refresh.
