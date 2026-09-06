# CoCo3Elite Wukong core integration

The Wukong V3 port has completed standalone video, CPU/BRAM diagnostics,
real-ROM boot, and keyboard integration. See the
[current implementation](CURRENT_IMPLEMENTATION.md) for build modes,
hardware results, and known limitations.

## Active integration boundary

`rtl/wukong/wukong_top.v` selects the display path. The full machine is
`rtl/wukong/coco3_boot_system.v`, with CPU-facing integration in
`rtl/core/coco3_boot_machine.v`. It integrates CPU09 with 128 KiB dual-port
BRAM, system and cartridge ROMs, partial GIME/SAM/PIA behavior, MMU registers,
timer/interrupt logic, keyboard matrix, joystick emulation, held sound DAC,
and a minimal read-only WD1773-compatible controller.

`rtl/coco3vid.v` supplies the CoCo renderer with a portable character ROM and
explicit BRAM fetch timing. NTSC artifact and CRT filters precede the Wukong
HDMI adapter. `HDMI_COCO_TEST` and `HDMI_COCO_AUDIO` align the CoCo source to
the library-owned 800x525 raster at 25.2 MHz. Earlier fallback modes retain
the 25 MHz local raster path. The current full mode is `HDMI_COCO_AUDIO`;
its audio packets are observed in simulation, but the latest recorded
hardware build is silent.

The original DE1 top level, `rtl/coco3fpga_dw.v`, remains a behavioral reference.
Its external SRAM arbitration, Altera primitives, T65 disk subsystem, and
DriveWire integration are not the active Wukong architecture.

## Completed and partial milestones

| Subsystem | Current implementation |
| --- | --- |
| Standalone video | `TEST_PATTERN`, `HDMI_LIBRARY_TEST`, and `COCO_VIDEO` checkpoints |
| CPU and memory | `CPU_DIAGNOSTIC`; 128 KiB BRAM, no external-memory controller |
| Real boot | User-prepared 32 KiB system ROM and 8 KiB Disk BASIC ROM; Disk Extended Color BASIC 2.1 |
| Keyboard | Hardware-verified PS/2: J14 pin 1/P23 data, pin 3/T24 clock |
| Diagnostic cartridge | F3 presents ZIA ROM-Pak through CART/FIRQ; guarded Ctrl+Alt+Delete returns to Disk BASIC |
| Disk controller | Optional read-only embedded `fpgatest.dsk` (drive 0) and `games.dsk` (drive 1), enabled with `-EmbeddedTestDisks` |
| MicroSD | J13 SPI initialization and physical sector-zero reads only; no FAT32 DSK mounting |
| Audio | Six-bit DAC to 48 kHz stereo HDMI packets; hardware audio regression remains open |
| Joysticks | F7 right W/S/A/D/F and F8 left arrows/Space emulation; no physical ADC interface |
| USB UART | Passive 115200-baud debug output, independent of storage |

ROM inputs, DSK files, and generated memory images remain untracked. The build
launcher requires local `roms/ziadiag.ccc` for all three real-ROM modes and
prepares it automatically; see [ROM workflow](../roms/README.md).

## Remaining work

Resolve HDMI sink audio acceptance and graphics-border behavior while preserving
the verified digital 32/40/80-column placement. Full-width text can still be
clipped by monitor overscan. GIME/MMU compatibility remains partial, and
MemTest2023+ and SYSINFO are compatibility probes, not passing acceptance tests.

[The storage roadmap](../hardware/sd-disk-interface.md) proposes a management
CPU, F12 overlay, FAT32 browser, mount table, and physical-floppy backend. None
is implemented; F12 currently maps to CoCo `@`. External audio, joystick ADC,
RTC, RS-232 PAK, printer, cassette, SDRAM, and DDR3 support remain future work.
DriveWire is outside the Wukong scope.

Keep hardware-specific adaptation in `rtl/wukong/` and portable compatibility
logic in `rtl/core/`. Preserve imported source boundaries. Each future hardware
change needs a focused regression, passing implementation/timing checks, and a
recorded physical test with ROM and bitstream hashes.
