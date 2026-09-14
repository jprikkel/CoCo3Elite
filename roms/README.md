# CoCo3Elite ROM inputs

Place a legally obtained CoCo 3 system ROM here as `coco3.rom`. The importer
accepts either a raw 32 KiB image or the historical 32,258-byte CoCo3FPGA flash
format (a two-byte `$8000` load header followed by `$8000-$FDFF`). For the
historical format it reconstructs the vector page used by the original FPGA
design. ROM and binary files in this directory are ignored by Git and must not
be committed.

Prepare the image for Vivado from the repository root:

```powershell
& scripts/prepare_coco3_rom.ps1
```

The script validates the format and reset vector, prints the source SHA-256
digest, and writes `build/roms/coco3.mem`. To require a known source digest,
pass it explicitly:

```powershell
& scripts/prepare_coco3_rom.ps1 -ExpectedSha256 '<64 hex digits>'
```

## Disk Extended Color BASIC ROM

Place the standard 8 KiB Disk Extended Color BASIC 1.1 cartridge ROM here as
`disk11.rom`, then prepare it with:

```powershell
& scripts/prepare_disk_rom.ps1
```

The importer requires the canonical image with SHA-1
`10BDC5AA2D7D7F205F67B47B19003A4BD89DEFD1` and writes
`build/roms/disk11.mem`. The ROM is mapped as an external cartridge at
`$C000-$DFFF`; the binary and generated memory file remain uncommitted.

## Cartridge images and diagnostic tests

The `COCO3_ELITE` build does not embed a fixed cartridge. Put compatible raw
2, 4, or 8 KiB `.CCC` images on a FAT32 SD card and select them through F12.
The manager mirrors smaller images across the 8 KiB `$C000-$DFFF` window,
verifies the download, cold-starts the CoCo, and launches through CART/FIRQ.

The standalone cartridge trace regression uses `roms/ziadiag.ccc` as a local
test fixture. To prepare its simulation image manually, run:

```powershell
& .\scripts\prepare_diagnostic_cartridge.ps1
```

The importer accepts raw 2, 4, or 8 KiB images, mirrors smaller images across
the 8 KiB window, and prints SHA-256. Local ROMs and utilities remain untracked.

`ziadiag.ccc` is the 8 KiB ZIA Computing diagnostic cartridge built from
[varmfskii/cocodiag on GitHub](https://github.com/varmfskii/cocodiag), which is
licensed under GPL-3.0. That repository contains the cartridge source code and
documentation for its tests. The importer writes
`build/roms/diagnostic_cart.mem` for simulation only.

ZIA Diag deliberately performs March RAM tests and extensive GIME MMU probing
before displaying its main menu. It therefore exposes RAM/MMU timing and
aliasing errors that lighter BASIC tests may not find. A separately supplied
Tandy diagnostic image can be imported manually for
comparison by passing it explicitly to the importer or trace script.

The cartridge main screen, keyboard, memory, ROM, joystick, and sound tests
have previously run. HDMI playback is hardware-verified, although some
displays remain muted until sustained nonzero samples arrive after a power
cycle. These are not blanket acceptance results for the latest build. Its GIME video test remains
a compatibility test and currently exposes incomplete video-mode behavior.
The printer, RS-232, and cassette tests require physical CoCo-compatible
interfaces that are not implemented. The Wukong USB UART is a passive FPGA
debug console and is not connected as the CoCo bit-banged serial port.

`MEMT2023.BIN` and `SYSINFO.BIN` are copied as machine-language files into the
generated optional FPGA diagnostic disk by `scripts/create_test_disk.ps1`.
Both utilities must be supplied locally before that script can complete;
it also assembles the project video helper. See [disk workflow](../disks/README.md).
They can be launched using `LOADM` followed by
`EXEC`, according to each utility's normal usage. MemTest2023+ is a continuous
memory tester and does not return to BASIC; reset the machine to exit. Both
utilities exercise GIME behavior beyond the current partial implementation, so
they are compatibility tests rather than known-good acceptance tests for now.
