# CoCo3Elite RTL inventory and Wukong boundary

The active source list is defined by [build_wukong.tcl](../scripts/build_wukong.tcl).
This inventory describes the current layout and separates the active Wukong
implementation from retained CoCo3FPGA and Quartus reference material.

## Active implementation

| Area/files | Role |
| --- | --- |
| `rtl/wukong/wukong_top.v`, `clocking.v` | Build-mode selection, MMCM/reset, HDMI raster alignment, audio sample clock, and physical outputs |
| `rtl/wukong/coco3_boot_system.v` | Complete machine video integration, keyboard controls, SD probe, filters, and UART integration |
| `rtl/wukong/coco3_diagnostic_system.v` | Standalone CPU09/BRAM diagnostic video source |
| `rtl/wukong/ntsc_artifact_filter.v`, `crt_filter.v` | Streaming artifact colors, scanlines, and CRT glow |
| `rtl/wukong/coco3_uart_debug.v`, `uart_tx.v` | Passive onboard USB serial logging |
| `rtl/wukong/hdmi/test_pattern.v`, `tmds_serializer.v` | HDMI test raster and local DVI-compatible serializer |
| `rtl/core/coco3_boot_machine.v` | CPU09 bus, ROM/RAM decode, GIME/SAM/PIA/MMU, cartridge, timer, and FDC integration |
| `rtl/core/coco3_128k_ram.v` | Dual-port 128 KiB block RAM shared by CPU and video |
| `rtl/core/coco3_system_rom.v`, `coco3_disk_rom.v`, `coco3_diagnostic_cartridge.v` | Prepared system, Disk BASIC, and diagnostic-cartridge memories |
| `rtl/core/coco3_char_rom.v`, `coco3gen.mem` | Portable character generator |
| `rtl/core/coco3_diagnostic_rom.v`, `coco3_diagnostic.mem` | Repository-owned CPU diagnostic |
| `rtl/core/coco3_keyboard_matrix.v` | CoCo keyboard matrix conversion |
| `rtl/core/coco3_gime_timer.v` | Partial GIME timer and interrupt behavior |
| `rtl/core/coco3_fdc.v`, `coco3_disk_image.v` | Minimal WD1773-compatible interface and optional read-only embedded DSK backend |
| `rtl/third-party/CPU09/cpu09l_128.vhd` | Inherited VHDL 6809-compatible CPU used by the full and diagnostic builds |
| `rtl/third-party/coco3fpga/coco3vid.v`, `cocokey.v` | Inherited CoCo raster and keyboard decoding behavior |
| `rtl/third-party/PS2_Key/ps2_keyboard.v` | Inherited PS/2 serial decoder |
| `rtl/third-party/hdl-util-hdmi/` | Vendored HDMI encoder, packet, channel, and serializer library |
| `constraints/wukong.xdc`, `constraints/wukong_audio.xdc` | Wukong V3 pins, timing, PS/2/SPI constraints, and generated HDMI audio clock |

The active build boundaries are:

- `COCO3_ELITE` combines the complete CoCo integration with the hdl-util HDMI
  encoder and continuous 48 kHz audio packets.
- `HDMI_TEST_PATTERN` displays the library test pattern and sends zero-valued
  HDMI audio samples. It does not generate a sound test.
- `BASIC_6809_DVI_TEST` runs the CPU09 and block-RAM diagnostic with the local
  video-only, DVI-compatible serializer.

The first two modes use the hdl-util 25.2/126 MHz HDMI raster and data islands.
The diagnostic mode uses the local 25/125 MHz video-only path. All three drive
the board's physical HDMI connector.

## Retained reference sources

`rtl/third-party/coco3fpga/coco3fpga_dw.v` is the original DE1 top-level and
integration reference. Its retained companion sources include `i2c.v`,
`paddles.v`, and `sound.v`; they are not selected by the active Wukong build.
The retained `rtl/third-party/SPI/SDCard.v` is the original CPU-facing SD
interface, distinct from the current firmware-owned Wukong J13 path. The retained
`rtl/third-party/UART_6551/` sources are a separate 6551-compatible serial
subsystem and are not the onboard USB UART implementation.

`rtl/third-party/coco3fpga/legacy-quartus/` preserves the original Quartus
wrappers, generated Altera memories/FIFOs, QIP metadata, MIF data, black-box
declarations, and project files. These sources are reference material and are
not compiled by Vivado. The historical Quartus project has incomplete input
references; that does not affect the active Wukong source list.

## Ownership and limitations

Keep board adaptation in `rtl/wukong/` and portable machine logic in
`rtl/core/`. Preserve imported CPU, CoCo3FPGA, PS/2, SPI, UART, and HDMI
boundaries under `rtl/third-party/`.

The active design has an RV32-managed FAT32 file service, F12 disk GUI, and
writable drive-0 DSK cache. It has no physical floppy, external-memory controller, physical joystick ADC,
printer/cassette/RS-232 PAK, or DriveWire backend. Optional embedded DSK inputs
are local, read-only, and untracked. HDMI audio is hardware-verified, although
some displays remain muted until sustained nonzero samples arrive after a
power cycle.

See [current implementation](CURRENT_IMPLEMENTATION.md),
[Wukong HDMI bring-up](BRINGUP.md), and
[diagnostic compatibility](DIAGNOSTIC_COMPATIBILITY_PLAN.md) for hardware
status and regression coverage.
