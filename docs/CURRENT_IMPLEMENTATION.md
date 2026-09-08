# Current Wukong implementation

This document describes the code currently used by the QMTECH Wukong V3
port. It is a snapshot of the implementation on 2026-09-06, not a list of
future goals. Historical bring-up notes and plans remain useful context, but
this file is the starting point for understanding the active design.

## Source ownership and modification policy

The repository contains three distinct classes of source:

| Area | Purpose | Local modification policy |
| --- | --- | --- |
| `rtl/wukong/` | Wukong top level, clocking, HDMI adaptation, filters, UART, and board integration | Project-owned; changes for this port belong here |
| `rtl/core/` | Portable CPU-facing memory, GIME register, timer, keyboard, cartridge, disk, and SD support added by this port | Project-owned; keep board-independent where practical |
| `rtl/third-party/coco3fpga/` | GIME video generator, keyboard decoder, and retained original Quartus reference files | Preserve as the upstream reference; prefer wrappers and focused compatibility fixes outside these files |
| `rtl/third-party/CPU09/` | CPU09 processor core | Preserve under its upstream license |
| `rtl/third-party/hdl-util-hdmi/` | Vendored [hdl-util/hdmi](https://github.com/hdl-util/hdmi) encoder and packet implementation | Do not modify locally; adapt signals in `rtl/wukong/` |

The active FPGA top level is `rtl/wukong/wukong_top.v`. It selects a source
and output path with build-time definitions supplied by
`scripts/build_wukong.tcl`.

## Hardware status

The implemented board target is the Wukong V3 with an Artix-7
`XC7A100T-FGG676-2`.

Hardware-verified functions include:

- CoCo 3 boot from a user-supplied system ROM in block RAM.
- Disk Extended Color BASIC 2.1.
- 128 KiB system RAM in FPGA block RAM.
- Stable 32-, 40-, and 80-column text with working mode changes.
- PS/2 keyboard on J14, including Break, soft reset, function-key controls,
  and keyboard-emulated left and right joysticks.
- ZIA diagnostic cartridge autostart through F3 and the system-ROM cartridge
  path.
- CH340N UART diagnostic output through the board USB serial interface.
- Read-only embedded Disk BASIC images when explicitly enabled at build time.
- Optional NTSC artifact colors, horizontal scanlines, and CRT glow.
- The standalone `BASIC_6809_DVI_TEST` image, displaying `CPU09`,
  `RESET VECTOR PASSED`, and `STAGE 2 RUNNING` in green on black through its
  DVI-compatible video path.

Open hardware issues in the current working implementation are:

- HDMI audio is hardware-verified. Some displays mute sustained digital
  silence and need roughly two seconds of nonzero samples before unmuting,
  especially after the display is power-cycled.
- CoCo-compatible graphics modes can show a black area at the left where the
  programmed graphics border/background color is expected. Text positioning
  is currently correct, so this must be diagnosed without shifting or cropping
  the complete raster again.
- The ZIA diagnostic cartridge's video tests are substantially improved but
  are not yet a complete substitute for testing every physical CoCo interface.
- SD hardware initialization and a raw sector-zero probe exist, but FAT32
  parsing and mounting named `.DSK` files from the card are not implemented.
- Printer, cassette, RS-232 PAK, physical floppy, and expanded external memory
  interfaces are not implemented.

## End-to-end architecture

```text
50 MHz board oscillator
        |
        +--> Wukong MMCM --> 25.2 MHz pixel clock
        |                 `-> 126 MHz TMDS serialization clock
        |
        `--> wukong_top
              |
              +--> coco3_boot_system
              |      |
              |      +--> cpu09 + coco3_boot_machine
              |      +--> 128 KiB dual-port BRAM
              |      +--> system, Disk BASIC, and diagnostic ROMs
              |      +--> GIME/SAM/PIA/timer/FDC compatibility logic
              |      +--> COCO3VIDEO + portable character ROM
              |      +--> NTSC artifact filter --> CRT filter
              |      `--> PS/2, SD probe, joysticks, and UART
              |
              +--> Wukong raster alignment and narrow-mode centering
              `--> hdl-util HDMI encoder --> TMDS serializer --> HDMI pins
```

The base machine uses no DDR3. CPU and video accesses share the inferred
dual-port 128 KiB memory in `rtl/core/coco3_128k_ram.v`.

## CPU, ROM, and memory

`rtl/core/coco3_boot_machine.v` is the CPU-facing integration boundary. It
instantiates the VHDL `cpu09` core and implements the subset of CoCo 3 memory
and peripheral behavior needed by the current port:

- 128 KiB dual-port block RAM.
- GIME MMU task and page registers.
- GIME initialization, video, palette, border, timer, and interrupt state.
- Minimal SAM and PIA behavior used by the ROM, keyboard, joysticks, sound,
  monitor sensing, and cartridge startup.
- System ROM, Disk BASIC ROM, and an optional diagnostic cartridge ROM.
- A minimal WD1773-compatible read-only controller.

ROM files are user inputs and are not committed. The preparation scripts
validate and convert them into `$readmemh` files under `build/roms/`.

F3 does not replace the 6809 reset vector with a cartridge vector. It presents
the diagnostic ROM-Pak to the initialized machine and generates the delayed
CART/FIRQ event expected by the CoCo system ROM. Ctrl+Alt+Delete deselects the
cartridge and performs a guarded soft reset back to Disk BASIC.

## Video path

The active HDMI build deliberately keeps the inherited CoCo video generator
and the third-party HDMI encoder separated by Wukong-owned adaptation logic.
The sequence is:

1. `COCO3VIDEO` reads 16-bit video words from the second BRAM port and emits a
   9-bit logical/direct color plus sync, blanking, and active-video signals.
2. `coco3_boot_system.v` maps GIME palette values from `R2 G2 B2 R1 G1 B1`
   into 8-bit RGB channels. Direct-color modes follow the four intensity
   mappings in the original design.
3. `ntsc_artifact_filter.v` optionally converts qualifying CoCo-compatible
   one-bit graphics pairs. F11 controls this stage.
4. `crt_filter.v` optionally applies scanlines and horizontal glow. F9 controls
   scanlines and F10 controls glow.
5. `wukong_top.v` aligns the CoCo raster to the library-owned HDMI raster. It
   applies a 64-pixel delay in narrow modes so a 512-pixel CoCo display is
   centered within the 640-pixel HDMI active width.
6. The unmodified hdl-util encoder generates VIC 1 HDMI/DVI timing, data
   islands, TMDS symbols, and the serialization input stream.

The HDMI mode is 640 by 480 active pixels in an 800 by 525 total raster at a
25.2 MHz pixel clock. The CoCo video source and HDMI transport currently run
from the same pixel clock; no framebuffer or asynchronous line buffer is used.

The remaining graphics-border bug is at this adaptation boundary. It should
be debugged by recording the source color, video-active state, selected border
color, HDMI coordinates, and final RGB for the same scanline. Changing HDMI
counter phase or cropping without that trace risks regressing the verified
40/80-column placement.

See [HDMI Video Post-Processing](../hardware/video-post-processing.md) for the
filter algorithms and controls.

## HDMI audio path

The CoCo audio source is the six-bit DAC value retained by
`coco3_boot_machine.v`. Joystick comparator sweeps are kept separate so they
do not become an audible ticking sound. In `wukong_top.v`, the DAC is centered
around 32 and expanded to signed 16-bit stereo samples. The HDMI library is
configured for 48 kHz, 16-bit, two-channel audio and generates its Audio
Sample, Audio Clock Regeneration, and Audio InfoFrame packets.

The current RTL produces a continuous audio clock with alternating 262- and
263-pixel-clock half periods:

```text
25,200,000 / 525 = 48,000 samples/second
```

The clock is routed through a BUFG and constrained by
`constraints/wukong_audio.xdc`. `HDMI_TEST_PATTERN` sends the same 48 kHz HDMI
packet stream with zero-valued samples and no audible test signal.

## Keyboard and runtime controls

The signal path is:

```text
J14 --> ps2_keyboard.v --> cocokey.v --> coco3_keyboard_matrix.v --> PIA0
```

Important FPGA controls are:

| Key | Function |
| --- | --- |
| F3 | Start the embedded diagnostic cartridge |
| F6 | Toggle the board turbo override |
| F7 | Toggle W/S/A/D/F control of the right joystick |
| F8 | Toggle arrow/Space control of the left joystick |
| F9 | Toggle horizontal scanlines |
| F10 | Toggle CRT glow |
| F11 | Toggle NTSC artifact-color decoding |
| Ctrl+Alt+Delete | Guarded CoCo soft reset |

CoCo software selects the normal approximately 0.9 MHz rate with the SAM
`$FFD8` strobe and the double-speed approximately 1.8 MHz rate with `$FFD9`.
F6 independently forces double speed for debugging and compatibility testing.

The complete PC-to-CoCo key mapping and electrical connection are documented
in [PS/2 Keyboard Interface](../hardware/keyboard-ps2.md).

The 115200-baud UART PC snapshot includes a `V=` field of 40 hex digits.
From left to right it contains FF98 (2 digits), FF99 (2), FF9B (2),
FF9D/FF9E (4), FF9F (2), the sixteen packed six-bit palette registers
(24, palette 15 first and palette 0 last), and the current video RAM word (4).
All fields are captured together once per second. The RAM word is an
instantaneous fetch sample, not a framebuffer dump.

## Disk and SD behavior

The minimal controller in `rtl/core/coco3_fdc.v` exposes the CoCo disk latch at
`$FF40` and WD1773-compatible registers at `$FF48` through `$FF4B`.

With `-EmbeddedTestDisks`, the build converts and embeds:

| CoCo drive | Repository input | Generated memory file |
| --- | --- | --- |
| 0 | `disks/fpgatest.dsk` | `build/disks/fpgatest.mem` |
| 1 | `disks/games.dsk` | `build/disks/games.mem` |

These are read-only, 35-track images. Without the option, sector commands do
not silently fall through to an embedded image.

The J13 SD path currently performs SPI initialization and a diagnostic read of
physical sector zero. It does not yet connect FAT32 files to the FDC backend,
so inserting an SD card does not mount drives. The planned architecture is in
[SD-card Disk Interface](../hardware/sd-disk-interface.md).

## Build modes

Run all commands from the repository root. The launcher defaults to Vivado
2025.2 at `C:\AMD\2025.2\Vivado\bin\vivado.bat`.

| Mode | Output bitstream | Transport | Audio | Description |
| --- | --- | --- | --- | --- |
| `COCO3_ELITE` | `build/wukong/wukong_coco3_elite.bit` | HDMI | 48 kHz stereo CoCo DAC | Complete CoCo 3 system and the default build |
| `HDMI_TEST_PATTERN` | `build/wukong/wukong_hdmi_test_pattern.bit` | HDMI | 48 kHz stereo silence | hdl-util color pattern and HDMI packet test with no sound generator |
| `BASIC_6809_DVI_TEST` | `build/wukong/wukong_basic_6809_dvi_test.bit` | DVI-compatible TMDS | None | Hardware-verified CPU09, reset-vector, ROM, RAM, and basic GIME-video diagnostic |

All modes drive the physical HDMI connector. The two HDMI modes instantiate
the hdl-util encoder with HDMI data islands enabled. `BASIC_6809_DVI_TEST` uses the
local video-only TMDS encoder, so it is DVI-compatible and carries no audio.
Detailed contents and hardware checks for each image are documented in
[Wukong HDMI bring-up](BRINGUP.md).

The current full build command is:

```powershell
& .\scripts\build_wukong.ps1 -Mode COCO3_ELITE -EmbeddedTestDisks
```

Omit `-EmbeddedTestDisks` when disk images should not be included. Vivado runs
inside `build/wukong/`; checkpoints, reports, staged initialization files, and
the bitstream remain under `build/`.

The Tcl flow uses up to eight host threads, runs synthesis, optimization,
placement, physical optimization, and routing, and refuses to write a
bitstream when the worst timed path has negative slack.

## Regression tests

Focused PowerShell launchers under `scripts/` cover the principal boundaries:

| Test | Coverage |
| --- | --- |
| `test_boot_machine.ps1` | CPU boot and machine bus behavior |
| `test_boot_video.ps1` | Boot video and palette/border mapping |
| `test_fdc_read.ps1` | WD1773-compatible embedded-image reads |
| `test_gime_border.ps1` | GIME border register behavior |
| `test_gime_timer.ps1` | GIME timer behavior |
| `test_sync_wait.ps1` | Real CPU VSYNC polling and GIME read-to-clear status at both speeds; HVEN fill and MMU restoration |
| `test_zenix_video.ps1` | Zenix 320x225/16-color HVEN addressing, pixel decode, RAM-bank crossing, and raster output |
| `test_uart_video_trace.ps1` | Complete 66-byte video-state message decoded from the UART wire |
| `test_gime_vector_page.ps1` | ROM/RAM vector-page mapping |
| `test_hdmi_window.ps1` | 32/40/80-column HDMI placement, screen captures, and packet presence |
| `test_native_text_fetch.ps1` | Native text byte selection and fetch timing |
| `test_native_text_scroll.ps1` | Native text rows and vertical scrolling |
| `test_ps2_keyboard.ps1` | PS/2 reception and CoCo matrix mapping |
| `test_sd_spi_init.ps1` | SD SPI initialization state machine |
| `test_system_rom.ps1` | Prepared ROM layout and reset vector |
| `test_video_probe.ps1` | Diagnostic cartridge video register sequences |

`test_hdmi_window.ps1` writes simulated 640 by 480 captures for the three text
widths under `build/sim/hdmi_window/`. These captures verify digital placement
at the encoder input; they do not model a monitor's overscan, aspect-ratio
selection, or HDMI audio acceptance.

## Rules for the next implementation change

To avoid repeating the recent video/audio regressions:

1. Change only Wukong-owned integration or portable-core files unless a defect
   is conclusively demonstrated in inherited code.
2. Do not modify the vendored hdl-util source. Adapt its documented interface.
3. Reproduce one problem per build and keep audio and raster-position changes
   separate.
4. Add a regression that observes the failing boundary before altering it.
5. Preserve a named, hardware-verified bitstream checkpoint for comparison.
6. Record both the source commit and bitstream SHA-256 for every physical test.
