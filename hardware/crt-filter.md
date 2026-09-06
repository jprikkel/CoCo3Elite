# CoCo3Elite HDMI CRT Filter

The Wukong HDMI pipeline includes an optional streaming CRT presentation
filter after NTSC artifact-color generation. F9 toggles horizontal scanlines,
and F10 independently toggles phosphor bloom/glow. Both are disabled after
FPGA reset, and full bypass mode preserves the incoming RGB
and video timing exactly apart from the filter's registered pipeline stage.

The tuned hardware preset uses horizontal-scanline mask layout 7, mask intensity
72, bloom size 6, bloom threshold 100, no corner mask, no vignette, black level 0, and white
level 255. These are RTL control ports rather
than constants inside the filter so the planned management GUI can adjust them
at runtime.

## Phosphor masks

The `mask_layout` input selects one of 24 layouts (0 through 23). The layouts
include bypass/uniform, alternating vertical and horizontal slots, checkerboard,
three-phase RGB-style columns, three-line masks, diagonal triads, two- and
four-pixel dot masks, sparse grille lines, and several staggered variants.
`mask_intensity` controls how strongly the darker phosphor positions attenuate
the image.

## Other controls

- `bloom_size` and `bloom_threshold` control thresholded horizontal phosphor
  bloom. Level 6 blends four completed neighboring pixels for a stronger,
  softer glow. The streaming implementation uses nearby completed pixels and does not
  require a framebuffer.
- `corner_radius` applies a rounded-bezel corner mask.
- `vignette_size` and `vignette_strength` darken the image near its edges.
- `black_level` and `white_level` clamp the displayed tonal range.

The rounded corners and vignette provide streaming CRT geometry. True barrel
distortion changes both source coordinates and therefore needs a full-frame
buffer or an external-memory video path. It is not implemented in the current
BRAM-only design, particularly because optional embedded test disks
substantially increase XC7A100T block-RAM use. Barrel remapping can be added after
the management/video architecture has a framebuffer backend.

The management GUI is not implemented; only F9/F10 toggles are available at
runtime. See [video/audio status](video-post-processing.md) for the active HDMI path.
