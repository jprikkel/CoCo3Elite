# CoCo3Elite for QMTECH Wukong V3

CoCo3Elite is an AMD/Xilinx Vivado port derived from
[richard42/CoCo3FPGA](https://github.com/richard42/CoCo3FPGA). The original
Quartus/DE1 sources remain available as a reference. The implemented and
hardware-tested target is the QMTECH Wukong V3 with an Artix-7 XC7A100T in
the FGG676 package; other Artix-7 boards are future portability targets.

The machine boots Disk Extended Color BASIC 2.1 with 128 KiB of block RAM,
a user-supplied 32 KiB system ROM, and an 8 KiB Disk BASIC ROM. PS/2 keyboard,
keyboard joysticks, F3 diagnostic-cartridge autostart, passive USB UART
logging, and optional read-only embedded disks are implemented.

![CoCo BASIC on the QMTECH Wukong V3](docs/images/wukong-coco3-basic.png)

*Earlier hardware checkpoint: Extended Color BASIC over HDMI.*

The current full build is `HDMI_COCO_AUDIO`. Digital 32/40/80-column placement
is regression-tested, but wide text can be clipped by monitor overscan and
some graphics borders remain incorrect. HDMI audio packets appear in
simulation; the latest recorded hardware build is silent. MicroSD currently
supports initialization and sector-zero reads only—not FAT32 DSK mounting.
See [current implementation and limitations](docs/CURRENT_IMPLEMENTATION.md).

## Repository layout

```text
CoCo3Elite/
|-- rtl/                 Inherited CoCo RTL and project integration
|   |-- core/            Portable memory, machine, keyboard, timer, FDC, SD probe
|   |-- wukong/          Board top, clocking, HDMI, filters, UART
|   |-- third_party/     Vendored HDMI library; preserve upstream documentation
|   `-- CPU09/, T65/, PS2_Key/, UART*/  Inherited CPU/peripheral sources
|-- constraints/         Wukong V3 pin and timing constraints
|-- scripts/             Build, ROM/disk preparation, and regression launchers
|-- tb/                  HDL regressions, basic/ diagnostics, asm/ video helper
|-- roms/                Untracked local ROM and diagnostic-binary inputs
|-- disks/               Optional, untracked local DSK inputs
|-- build/               Ignored reports, staged memories, simulations, bitstreams
|-- hardware/            Board, wiring, video/audio, and storage documentation
|-- docs/                Implementation, compatibility, historical tests, PDFs
|-- tools/               Bundled ToolShed, asm6809, and PuTTY utilities
|-- ip/                  Reserved for generated Vivado IP
`-- legacy-quartus/      Original Quartus project and generated support files
```

## ROM and disk preparation

Run commands from the repository root using Windows PowerShell and Vivado
with Artix-7 support. The launcher defaults to
`C:\AMD\2025.2\Vivado\bin\vivado.bat`; pass `-Vivado` to override it.

Supply legally obtained `roms/coco3.rom`, `roms/disk11.rom`, and the ZIA
cartridge `roms/ziadiag.ccc`. All three real-ROM build modes require these
inputs. The launcher prepares the diagnostic cartridge automatically; prepare
the system and Disk BASIC memories first:

```powershell
& .\scripts\prepare_coco3_rom.ps1
& .\scripts\prepare_disk_rom.ps1
& .\scripts\build_wukong.ps1 -Mode HDMI_COCO_AUDIO
```

The system importer accepts raw 32 KiB or historical 32,258-byte CoCo3FPGA
flash format, checks the reset vector, and reports SHA-256. The Disk BASIC
importer requires the canonical 8 KiB Disk BASIC 1.1 ROM. See
[ROM inputs and checksums](roms/README.md) for details. ROM binaries and
prepared memories remain untracked.

DSK files are optional, untracked, and read-only when embedded. To include
`disks/fpgatest.dsk` as drive 0 and `disks/games.dsk` as drive 1:

```powershell
& .\scripts\build_wukong.ps1 -Mode HDMI_COCO_AUDIO -EmbeddedTestDisks
```

Both must be raw 161,280-byte images. See [disk preparation](disks/README.md)
for generating the diagnostic disk and its local binary prerequisites.
Without the switch, no disk backend is mounted. An SD card does not supply
a replacement backend yet; writes and FAT32 mounting are unsupported.

## Build modes

The default mode is `TEST_PATTERN`. Outputs are under `build/wukong/`.

| Mode | Bitstream | Purpose |
| --- | --- | --- |
| `TEST_PATTERN` | `wukong_hdmi_test.bit` | Local test raster, DVI-compatible video |
| `HDMI_LIBRARY_TEST` | `wukong_hdmi_library_test.bit` | Experimental library raster; current RGB source is undriven |
| `HDMI_COCO_TEST` | `wukong_hdmi_coco_test.bit` | Real CoCo on the library raster without audio |
| `HDMI_COCO_AUDIO` | `wukong_hdmi_coco_audio.bit` | Current full path with HDMI audio packets; hardware audio issue remains |
| `COCO_VIDEO` | `wukong_coco_video.bit` | Synthetic legacy CoCo text, no CPU |
| `CPU_DIAGNOSTIC` | `wukong_cpu_diagnostic.bit` | Repository-owned CPU/128 KiB BRAM diagnostic ROM |
| `COCO3_BOOT` | `wukong_coco3_boot.bit` | Real CoCo with local raster, no HDMI audio |

Vivado runs synthesis, optimization, placement, physical optimization, routing,
DRC and timing reports, then bitstream generation. The flow rejects absent
timed paths or negative worst-path slack. Review the generated reports before
programming via JTAG. Check the fitted FPGA speed grade: the default
`-Part 'xc7a100tfgg676-2'` differs from the -1 device described in the manual.

## Hardware and controls

PS/2 on J14 uses **pin 1/P23 for data and pin 3/T24 for clock**. The verified
HP KB-0133 runs at 3.3 V; other keyboards may need level translation.
MicroSD uses a Digilent Pmod on J13. The USB connector is a CH340N serial
bridge, not a USB host or DriveWire storage connection.

F3 starts ZIA diagnostics; Ctrl+Alt+Delete resets to Disk BASIC. F6 toggles
CPU speed, F7/F8 toggle right/left keyboard joysticks, F9 scanlines, F10 glow,
and F11 artifact color. F12 currently types `@`; the management overlay is
planned. See the [complete keyboard map](hardware/keyboard-ps2.md).

## Documentation

- [Current implementation and regression scripts](docs/CURRENT_IMPLEMENTATION.md)
- [Wukong board](hardware/wukong-board.md) and [PMOD pinout](hardware/wukong-pmod-pinout.md)
- [Clocking and port notes](docs/WUKONG_PORT.md)
- [Core integration status](docs/WUKONG_CORE_INTEGRATION.md)
- [Bring-up and acceptance](docs/BRINGUP.md)
- [Storage status and roadmap](hardware/sd-disk-interface.md)
- [HDMI video and audio](hardware/video-post-processing.md)
- [Diagnostic compatibility](docs/DIAGNOSTIC_COMPATIBILITY_PLAN.md)
- [Cartridge video probe](docs/CARTRIDGE_VIDEO_PROBE.md)
- [RTL inventory](docs/RTL_INVENTORY.md)

See [LICENSE](LICENSE). Imported components and ROM inputs have their own
license/provenance requirements; ROM and disk images are not distributed here.
