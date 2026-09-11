# CoCo 3 Elite - A Tandy Color Computer 3 compatible computer

CoCo 3 Elite is a recreation of the classic Tandy Color Computer 3 with modern
features such as HDMI video, SD-card storage, Atari joystick ports, modern
keyboards, and USB support. Original software, games, music, and disk images
run with minimal changes, and original peripherals such as cartridges,
cassette, joysticks, serial/RS232 devices, and floppy drives can be supported
natively.

*Note: The CoCo 3 Elite project is not endorsed by or associated with Tandy(TM)
or Radio Shack(TM).*

![Extended Color BASIC running on the QMTECH Wukong V3](docs/images/wukong-coco3-basic.png)

CoCo3Elite is currently based on the AMD/Xilinx Vivado FPGA Artix-7 QMTECH
Wukong V3 board. Hardware peripherals are primarily supported via standard
PMOD adapters and can be mixed and matched for the desired physical hardware.

The current port targets the Wukong V3 fitted with an Artix-7 `XC7A100T` in
the FGG676 package. The hardware-verified build boots a 128 KiB CoCo 3 system
ROM from block RAM and displays Extended Color BASIC over the board's HDMI
connector with 48 kHz stereo HDMI packets carrying the CoCo's mono DAC output.

## Repository layout

```text
CoCo3Elite/
|-- rtl/              Verilog and VHDL sources
|   |-- core/         Portable CoCo memory, ROM, and boot-machine modules
|   |-- third-party/  Licensed upstream CPU, CoCo, peripheral, and HDMI RTL
|   `-- wukong/       Wukong top level, clocking, HDMI, and system integration
|-- constraints/      Board-specific XDC constraints
|-- scripts/          Vivado build, ROM preparation, and simulation scripts
|-- ip/               Vivado-generated IP
|-- tb/               Testbench sources
|-- build/            Generated ROM images, reports, checkpoints, and bitstreams
|-- roms/             User-supplied ROM inputs; ROM binaries are ignored by Git
|-- hardware/         Wukong interface pinouts and external wiring guides
`-- docs/              Porting notes, bring-up results, and board documentation
```

Generated content under `build/` is not committed.

Hardware interface documentation is maintained under [`hardware/`](hardware/):

- [QMTECH Wukong V3 board overview](hardware/wukong-board.md)
- [Wukong V3 PMOD pinout](hardware/wukong-pmod-pinout.md)
- [PS/2 keyboard interface](hardware/keyboard-ps2.md)
- [USB host prototype and proposed wiring](hardware/usb-host-interface.md)

*Hardware checkpoint: Disk Extended Color BASIC 2.1 with corrected GIME colors and
vertical centering, running from block RAM and displayed over HDMI on the
QMTECH Wukong V3.*

The RV32 manager mounts compatible root-level FAT32 `.DSK` files as drive 0,
supports selection through the F12 overlay, and flushes completed sector writes
back to the mounted image. Optional embedded DSK files remain local, read-only,
and untracked. The onboard USB connection is currently a passive UART
diagnostic link, not a USB host.

The [SD-card and USB support plan](docs/SDCARD_SUPPORT_PLAN.md) describes the
proposed filesystem browser, writable DSK images, cartridge/BAS/BIN loading,
FPGA management processor, and USB storage/input expansion.

## Requirements

- Windows PowerShell
- AMD Vivado with support for the Artix-7 `XC7A100T`
- A legally obtained CoCo system ROM

The launcher defaults to Vivado 2025.2 at:

```text
C:\AMD\2025.2\Vivado\bin\vivado.bat
```

Pass `-Vivado` to the build script if Vivado is installed elsewhere.

## ROM preparation

CoCo ROM images may be obtained from the vetted
[RetroBIOS Tandy CoCo collection](https://github.com/Abdess/retrobios/tree/main/bios/Tandy/CoCo).
ROM binaries are inputs to the build and must remain uncommitted.

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

Prepare the appropriate ROM first, then build the hardware-verified CoCo 3
image from the repository root:

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

## Documentation and references

- [Current Wukong implementation and known issues](docs/CURRENT_IMPLEMENTATION.md)
- [Wukong port notes](docs/WUKONG_PORT.md)
- [Hardware bring-up record](docs/BRINGUP.md)
- [Original CoCo3FPGA project](https://github.com/richard42/CoCo3FPGA)
- [RetroBIOS Tandy CoCo ROM collection](https://github.com/Abdess/retrobios/tree/main/bios/Tandy/CoCo)

See [LICENSE](LICENSE) for the source-code license. ROM images may have separate
terms and are intentionally not distributed by this repository.

The long-term target family includes boards based on the Artix-7 `XC7A15T`,
`XC7A50T`, and `XC7A100T`. The RTL is being kept portable across those devices;
the Wukong V3 `XC7A100T` is the currently implemented and hardware-verified
board target.

The current build names are `COCO3_ELITE`, `HDMI_TEST_PATTERN`, and
`BASIC_6809_DVI_TEST`. The last image is hardware-verified and displays
`CPU09`, `RESET VECTOR PASSED`, and `STAGE 2 RUNNING` in green on black.
