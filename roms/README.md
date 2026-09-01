# CoCo 3 system ROM

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

## Diagnostic cartridge and utilities

`ziadiag.ccc` is the 8 KiB ZIA Computing diagnostic cartridge built from
[varmfskii/cocodiag on GitHub](https://github.com/varmfskii/cocodiag), which is
licensed under GPL-3.0. That repository contains the cartridge source code and
documentation for its tests. The importer maps the image through the
`$C000-$DFFF` cartridge window and writes
`build/roms/diagnostic_cart.mem`.

Pressing F3 presents the cartridge to the already initialized CoCo and then
emulates the PIA1 CB1/CART edge used by an autostart ROM-Pak. The system ROM's
FIRQ cartridge-start path transfers control to the cartridge; the FPGA does
not replace the 6809 reset vector with `$C000`. Ctrl+Alt+Delete performs a
normal reset, deselects the cartridge, and returns to Disk Extended Color
BASIC.

ZIA Diag deliberately performs March RAM tests and extensive GIME MMU probing
before displaying its main menu. It therefore exposes RAM/MMU timing and
aliasing errors that lighter BASIC tests may not find. The original Tandy
diagnostic image remains available locally for comparison but is not the
default F3 cartridge.

The cartridge main screen, keyboard, memory, ROM, joystick, and sound tests
are useful with the current Wukong implementation. Its GIME video test remains
a compatibility test and currently exposes incomplete video-mode behavior.
The printer, RS-232, and cassette tests require physical CoCo-compatible
interfaces that are not implemented. The Wukong USB UART is a passive FPGA
debug console and is not connected as the CoCo bit-banged serial port.

`MEMT2023.BIN` and `SYSINFO.BIN` are copied as machine-language files into the
generated FPGA diagnostic disk. They can be launched using `LOADM` followed by
`EXEC`, according to each utility's normal usage. MemTest2023+ is a continuous
memory tester and does not return to BASIC; reset the machine to exit. Both
utilities exercise GIME behavior beyond the current partial implementation, so
they are compatibility tests rather than known-good acceptance tests for now.
