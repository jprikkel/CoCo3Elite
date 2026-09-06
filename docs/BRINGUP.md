# Wukong HDMI bring-up

## Supported builds

Run the build launcher from the repository root. It defaults to the complete
CoCo 3 image:

```powershell
& .\scripts\build_wukong.ps1
```

The supported modes are:

| Mode | Output | Video transport | Audio | Purpose |
| --- | --- | --- | --- | --- |
| `HDMI_COCO_AUDIO` | `build/wukong/wukong_hdmi_coco_audio.bit` | HDMI | CoCo DAC as 48 kHz, 16-bit stereo | Complete CoCo 3 system |
| `HDMI_LIBRARY_TEST` | `build/wukong/wukong_hdmi_library_test.bit` | HDMI | Silent 48 kHz, 16-bit stereo packets | HDMI transport and raster test |
| `CPU_DIAGNOSTIC` | `build/wukong/wukong_cpu_diagnostic.bit` | DVI-compatible TMDS through the HDMI connector | None | CPU09, reset-vector, ROM, and 128 KiB block-RAM diagnostic |

All three images use the board's HDMI connector and differential TMDS pins.
`HDMI_COCO_AUDIO` and `HDMI_LIBRARY_TEST` are true HDMI streams with data
islands. `CPU_DIAGNOSTIC` sends video-only, DVI-compatible TMDS and has no
HDMI packets or audio.

The full build requires prepared CoCo 3 and Disk BASIC ROMs. Run:

```powershell
& .\scripts\prepare_coco3_rom.ps1
& .\scripts\prepare_disk_rom.ps1
& .\scripts\build_wukong.ps1 -Mode HDMI_COCO_AUDIO
```

Vivado runs synthesis, optimization, placement, routing, timing analysis, and
DRC before writing a bitstream. Generated files remain under `build/wukong/`.

### `HDMI_COCO_AUDIO`

This is the default and the complete machine. It instantiates CPU09, 128 KiB
of dual-port block RAM, the CoCo 3 and Disk BASIC ROMs, GIME/SAM/PIA
compatibility logic, PS/2 keyboard input, keyboard-emulated joysticks, the
six-bit sound DAC, diagnostic cartridge support, the minimal read-only FDC,
the MicroSD initialization and sector-zero probe, and UART diagnostics.

`COCO3VIDEO` supplies the CoCo raster. The Wukong integration maps its colors,
optionally applies NTSC artifact color, scanlines, and CRT glow, and aligns it
to the hdl-util 640 by 480 VIC 1 raster. Narrow 512-pixel modes are centered in
the 640-pixel active area.

The hdl-util encoder emits full HDMI video and data islands. The held six-bit
CoCo DAC value is centered, scaled to signed 16-bit PCM, duplicated into left
and right channels, and sent at 48 kHz.

Adding `-EmbeddedTestDisks` includes the configured read-only DSK images.
They are optional and untracked. The MicroSD interface does not mount FAT32
DSK files; it currently initializes the card and reads physical sector zero
only.

### `HDMI_LIBRARY_TEST`

This image isolates the HDMI clocking, hdl-util encoder, serializer, output
pins, raster geometry, and monitor compatibility from the CoCo system. It
displays a 640 by 480 pattern with color regions, a checkerboard area, a grid,
and a white active-area border. It does not instantiate the CPU, machine RAM,
ROMs, GIME machine, keyboard, cartridge, FDC, or SD controller.

The output is full HDMI. It includes the normal Audio Sample, Audio Clock
Regeneration, and Audio InfoFrame traffic at 48 kHz with two 16-bit channels.
Every sample is zero, so this mode tests HDMI audio transport without
producing a tone or other test sound.

### `CPU_DIAGNOSTIC`

This small standalone system instantiates CPU09, a diagnostic ROM, 128 KiB of
dual-port block RAM, the portable character ROM, and `COCO3VIDEO`. It checks
CPU execution, reset-vector handling, and RAM byte lanes, then reports status
through the generated video display. It does not include the complete CoCo
machine, system or Disk BASIC ROMs, keyboard, audio, disk, SD, cartridge, UART,
or video post-processing filters.

Its local encoder emits video-only, DVI-compatible TMDS through the physical
HDMI connector. It does not generate HDMI data islands or audio packets.

## Hardware checks

For the full image, confirm that Extended Color BASIC boots, PS/2 input works,
and `SOUND 100,100` is audible. The transmitter sends audio packets
continuously. Some displays mute digital silence and may require a sustained
tone before their speakers unmute, especially after the display is power
cycled.

For an HDMI transport check without the CoCo, build `HDMI_LIBRARY_TEST` and
confirm a stable 640 by 480 color pattern. This mode sends valid 48 kHz,
16-bit, two-channel HDMI audio packets containing silence; it intentionally
does not generate a test sound.

The `CPU_DIAGNOSTIC` image is hardware-verified. It displays `CPU09`,
`RESET VECTOR PASSED`, and `STAGE 2 RUNNING` in green text on a black
background. This confirms that the CPU reaches the second diagnostic stage
and that the DVI-compatible video path is visible on the tested display.
