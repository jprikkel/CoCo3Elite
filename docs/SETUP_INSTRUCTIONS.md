
## Requirements

- An Artix-7 FPGA board, prefferably QMTECH Wukong V3
- Diligent PS/2 PMOD (or USB alternative) and 3.3V compatible PS/2 Keyboard
- HDMI Monitor and cable
- JTAG Programmer - Diligent
- USB PMOD Connector and USB Drive or SDCARD PMOD Connector and an SDCARD
- Windows and PowerShell
- AMD Vivado with support for the Artix-7 `XC7A100T`
- A legally obtained CoCo system ROM and Disk Extended Basic

The launcher defaults to Vivado 2025.2 at:

```text
C:\AMD\2025.2\Vivado\bin\vivado.bat
```

Pass `-Vivado` to the build script if Vivado is installed elsewhere.

## ROM preparation

If you have a CoCo 3, ROM images may be obtained from the vetted
[RetroBIOS Tandy CoCo collection](https://github.com/Abdess/retrobios/tree/main/bios/Tandy/CoCo).
ROM binaries are inputs to the build and must remain uncommitted to this repository.

For the CoCo 3 build, place a compatible system image at `roms/coco3.rom` and
the standard 8 KiB Disk Extended Color BASIC 1.1 cartridge image at
`roms/disk11.rom`, then run from the repository root:

```powershell
& .\scripts\prepare_coco3_rom.ps1
& .\scripts\prepare_disk_rom.ps1
```

The importer accepts either a raw 32 KiB CoCo 3 image or the historical
32,258-byte CoCo3FPGA flash format. It validates the reset vector, prints the
source SHA-256 digest, and writes `build/roms/coco3.mem` for Vivado.
The disk importer validates the canonical Disk BASIC 1.1 SHA-1 and writes
`build/roms/disk11.mem`. ROM binaries and generated memory files are ignored
by Git.

## Building a bitstream

For the complete ordered workflow—ROM import, disk preparation, RV32
management firmware, FPGA build, regressions, and JTAG programming—see
[Building the Wukong bitstream](docs/BUILD_BITSTREAM.md).

To build a hardware-verified CoCo 3 image type the following from the repository root:

```powershell
& .\scripts\build_wukong.ps1 -Mode COCO3_ELITE
```

On success, program the board with:

```text
build/wukong/wukong_coco3_elite.bit
```

The build performs synthesis, implementation, design-rule checks, timing
analysis, and bitstream generation. It refuses to generate a bitstream if the
design has negative timing slack.

Other selectable modes are:

| Mode | Output | Transport and purpose |
|---|---|---|
| `COCO3_ELITE` | `wukong_coco3_elite.bit` | Complete CoCo 3 over HDMI with 48 kHz audio; default build |
| `HDMI_TEST_PATTERN` | `wukong_hdmi_test_pattern.bit` | hdl-util pattern over HDMI with silent audio packets and no sound test |
| `BASIC_6809_DVI_TEST` | `wukong_basic_6809_dvi_test.bit` | CPU09 and 128 KiB block-RAM diagnostic over video-only, DVI-compatible TMDS |

All three modes use the board's HDMI connector. See
[Wukong HDMI bring-up](docs/BRINGUP.md) for the instantiated hardware,
audio behavior, and hardware checks for each image.

For example, to use another Vivado installation or compatible FPGA part:

```powershell
& .\scripts\build_wukong.ps1 `
    -Vivado 'D:\AMD\Vivado\2025.2\bin\vivado.bat' `
    -Part 'xc7a100tfgg676-2' `
    -Mode COCO3_ELITE
```

Scripts also require updating permissions under Windows PowerShell. Run the commands below as
Administrator in PowerShell.

1. If PowerShell blocks script execution with an execution-policy error, allow scripts for your user account:

  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

2. If vivado executables are blocked use the command below:

  New-CIPolicy `
  >>   -Level Hash `
  >>   -FilePath "$env:USERPROFILE\Desktop\VivadoAllow.xml" `
  >>   -UserPEs `
  >>   -ScanPath C:\AMD\2025.2\Vivado\bin\unwrapped\win64.o\xsim.exe
