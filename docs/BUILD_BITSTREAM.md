# Building the Wukong bitstream

This procedure builds the complete CoCo3Elite image for the Wukong
`XC7A100T` board. Run every command from the repository root in PowerShell.
The supported build keeps its final output at:

```text
build\wukong\wukong_coco3_elite.bit
```

Do not commit ROMs, copyrighted software, generated disk contents, firmware
binaries, or bitstreams. The build regenerates its intermediate files from
source and local inputs.

## 1. Prerequisites

Install AMD Vivado with Artix-7 device support. The scripts default to Vivado
2025.2 and its bundled RISC-V toolchain at:

```text
C:\AMD\2025.2\Vivado\bin\vivado.bat
C:\AMD\2025.2\gnu\riscv\nt\bin
```

The repository supplies ToolShed `decb` under `tools\toolshed` for creating
CoCo disk images. The diagnostic-disk helper scripts also require the
repository's assembler tools and their local source inputs.

Close interactive Vivado and xsim sessions that have this repository open
before starting a batch build. They can lock generated files under `build\`
and cause an otherwise valid build or test to fail with an access-denied
error.

If PowerShell blocks the scripts, enable locally downloaded scripts for the
current account:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Use the `-Vivado` or `-VivadoBin` parameters when the tools are installed in a
different location. The target part defaults to `xc7a100tfgg676-2`.

## 2. Generate the ROM inputs

Place legally obtained local images at these paths:

| Input | Requirement | Purpose |
| --- | --- | --- |
| `roms\coco3.rom` | Raw 32 KiB ROM or supported legacy CoCo3FPGA image | CoCo 3 system ROM |
| `roms\disk11.rom` | Canonical 8 KiB Disk Extended Color BASIC 1.1 ROM | Disk cartridge ROM |
| `roms\ziadiag.ccc` | Raw 2, 4, or 8 KiB image | F3 diagnostic cartridge |

Generate and validate the memory initialization files:

```powershell
& .\scripts\prepare_coco3_rom.ps1
& .\scripts\prepare_disk_rom.ps1
& .\scripts\prepare_diagnostic_cartridge.ps1
```

The first two commands produce `build\roms\coco3.mem` and
`build\roms\disk11.mem`. The system-ROM importer checks its layout and reset
vector. The Disk BASIC importer also requires the known SHA-1
`10BDC5AA2D7D7F205F67B47B19003A4BD89DEFD1`. Each importer prints the source
digest so a build can be tied to known local inputs.

The final `COCO3_ELITE` build always imports `roms\ziadiag.ccc` again into its
private staging tree. The manual diagnostic-cartridge command is still useful
as an early validation step.

See [the ROM input policy](../roms/README.md) for accepted formats. These
binary inputs and generated `.mem` files are intentionally ignored by Git.

## 3. Prepare disk images

There are two disk workflows. The normal SD-card build does not embed a DSK
file in the bitstream. The optional embedded workflow is useful as a fixed,
read-only fallback.

### FAT32 SD-card disks

Format an SD card as FAT32, either as a FAT32 superfloppy or with FAT32 in the
first MBR partition. Copy headerless CoCo DSK files into its root directory.
The current manager supports:

- DOS 8.3 names ending in `.DSK`;
- exactly 161,280 bytes per image;
- 35 tracks, 18 sectors per track, and 256 bytes per sector;
- up to 16 root-directory DSK entries;
- drive 0 mounting through the F12 browser;
- sector writes flushed back into the existing mounted FAT32 file.

Long filenames, subdirectories, other geometries, and assigning drives 1-3
are not yet supported. Use F12 after boot, Up/Down to select a file, Enter to
mount it as drive 0, and Esc or F12 to close the menu.

An existing valid DSK can simply be copied to the card. To create a blank
35-track image and add files with ToolShed:

```powershell
$decb = '.\tools\toolshed\decb.exe'
& $decb dskini '.\disks\custom.dsk' -3
& $decb copy '.\path\PROGRAM.BAS' -t '.\disks\custom.dsk,PROGRAM.BAS'
& $decb copy -2 -b '.\path\PROGRAM.BIN' '.\disks\custom.dsk,PROGRAM.BIN'
& $decb dir '.\disks\custom.dsk,'
```

Only add software that may legally be redistributed. DSK and game binaries
should normally remain local and untracked.

### Project diagnostic disk

To regenerate `disks\fpgatest.dsk` from the repository diagnostics:

```powershell
& .\scripts\create_test_disk.ps1
```

This command replaces that DSK. It requires local copies of
`roms\MEMT2023.BIN` and `roms\SYSINFO.BIN`, assembles the project video
helpers, copies the BASIC tests, and prints the resulting directory.

### Optional embedded disks

The build can convert and embed two local 161,280-byte images:

```powershell
& .\scripts\build_wukong.ps1 -Mode COCO3_ELITE -EmbeddedTestDisks `
    -Drive0Disk 'disks\fpgatest.dsk' `
    -Drive1Disk 'disks\games.dsk'
```

Embedded disks consume FPGA memory and are fixed at build time. Use the
normal non-embedded build for writable, selectable SD-card images.

## 4. Build the management firmware

The production management firmware is source-controlled at:

```text
firmware\management\rv32_start.S
firmware\management\rv32_sd_mount.c
firmware\management\rv32_tcm.ld
```

It runs on the vendored ultraembedded RV32IM soft CPU and owns SD SPI, FAT32
directory traversal, DSK loading and writeback, and the F12 disk browser.

The supported firmware build is part of `build_wukong.ps1`. Before Vivado
synthesis starts, the launcher:

1. compiles and links the firmware with `riscv64-unknown-elf-gcc.exe` using
   `rv32im_zicsr`, the `ilp32` ABI, and the project linker script;
2. converts the ELF to a raw binary with
   `riscv64-unknown-elf-objcopy.exe`;
3. converts the binary into `rv32_sd_mount_program.vh` for the FPGA firmware
   loader;
4. includes that generated program in the synthesized design.

The temporary outputs are:

```text
build\wukong\firmware\rv32_sd_mount.elf
build\wukong\firmware\rv32_sd_mount.bin
build\wukong\rv32_sd_mount_program.vh
```

They are removed after a successful normal build. Pass `-KeepIntermediates`
to retain them for disassembly or size analysis. Do not commit them.

Useful firmware and management-path preflight tests are:

```powershell
& .\scripts\test_ultraembedded_manager_smoke.ps1
& .\scripts\test_manager_sd_mmio.ps1
& .\scripts\test_manager_sd_fat32_firmware.ps1
& .\scripts\test_fdc_manager_integration.ps1
& .\scripts\test_fdc_sd_write.ps1
```

The FAT32 firmware test builds the standalone directory-listing diagnostic;
the normal bitstream launcher always rebuilds the production mount firmware.

## 5. Build the bitstream

For the normal SD-card-enabled CoCo image:

```powershell
& .\scripts\build_wukong.ps1 -Mode COCO3_ELITE
```

`COCO3_ELITE` is the default, so the following is equivalent:

```powershell
& .\scripts\build_wukong.ps1
```

For a non-default Vivado installation:

```powershell
& .\scripts\build_wukong.ps1 `
    -Vivado 'D:\AMD\Vivado\2025.2\bin\vivado.bat' `
    -Part 'xc7a100tfgg676-2' `
    -Mode COCO3_ELITE
```

The build runs synthesis, optimization, placement, physical optimization,
routing, DRC, and timing analysis. It writes the bitstream only when the
worst timed path has non-negative slack. On success, it cleans large staging
files unless `-KeepIntermediates` was supplied, while retaining the stable
bitstream and reports under `build\wukong`.

Verify the expected output and record its digest:

```powershell
Get-Item '.\build\wukong\wukong_coco3_elite.bit'
Get-FileHash -Algorithm SHA256 '.\build\wukong\wukong_coco3_elite.bit'
Select-String -Path '.\build\wukong\timing_summary.rpt' `
    -Pattern 'All user specified timing constraints are met'
```

Do not copy or rename the primary build output inside the build script. Tools
and programming scripts expect the stable path
`build\wukong\wukong_coco3_elite.bit`.

## 6. Run regressions

At minimum, run the boot, input, FDC, management, and video-path tests relevant
to a full image:

```powershell
& .\scripts\test_boot_machine.ps1
& .\scripts\test_ps2_keyboard.ps1
& .\scripts\test_fdc_read.ps1
& .\scripts\test_fdc_manager_integration.ps1
& .\scripts\test_fdc_sd_write.ps1
& .\scripts\test_manager_sd_mmio.ps1
& .\scripts\test_boot_video.ps1
& .\scripts\test_hdmi_window.ps1
```

The complete set of focused launchers is under `scripts\test_*.ps1`. Some
tests regenerate ROM or disk fixtures and therefore require the same local
inputs as the production build.

## 7. Program and check the board

Connect the Wukong board over JTAG and program the standard output with:

```powershell
& .\scripts\program_wukong_coco3_sd_mount.ps1
```

The programming script requires exactly one connected `xc7a100t` device. It
does not rebuild the image.

For hardware acceptance, verify:

- Disk Extended Color BASIC reaches its prompt;
- the PS/2 keyboard and Ctrl+Alt+Delete reset work;
- F12 opens the disk browser and mounts a root-level compatible DSK;
- `DIR`, `LOADM`, `RUN`, and disk writes operate on the selected image;
- HDMI video is stable and both six-bit DAC and PIA PB1 single-bit sound are
  audible;
- the UART diagnostic stream remains active at 115200 baud.

Before removing the SD card, stop software that may be writing to the mounted
image. A successful FDC write is acknowledged only after firmware flushes the
modified sector back to the card, but there is not yet a general safe-eject
command.
