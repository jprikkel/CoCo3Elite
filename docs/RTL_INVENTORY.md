# CoCo3Elite RTL inventory and Wukong boundary

The active source list is defined by [build_wukong.tcl](../scripts/build_wukong.tcl).
This inventory describes the current layout; it supersedes the original Phase 1
proposal for `boards/wukong/` and `vivado/`, which are not current directories.

## Active implementation

| Area/files | Role |
| --- | --- |
| `rtl/wukong/wukong_top.v`, `clocking.v` | Mode selection, MMCM/reset, HDMI raster alignment, audio sample clock, physical output |
| `rtl/wukong/coco3_boot_system.v` | Full machine, keyboard controls, SD probe, filters, UART integration |
| `rtl/core/coco3_boot_machine.v` | CPU09 bus, ROM/RAM decode, GIME/SAM/PIA/MMU, cartridge, timer, FDC |
| `rtl/core/coco3_128k_ram.v` | Dual-port 128 KiB BRAM shared by CPU/video |
| `rtl/core/coco3_system_rom.v`, `coco3_disk_rom.v`, `coco3_diagnostic_cartridge.v` | Prepared, user-supplied ROM memories |
| `rtl/core/coco3_char_rom.v`, `coco3gen.mem` | Portable character generator |
| `rtl/core/coco3_diagnostic_rom.v`, `coco3_diagnostic.mem` | Repository-owned CPU diagnostic |
| `rtl/core/coco3_synthetic_video_ram.v` | Synthetic text for `COCO_VIDEO` |
| `rtl/core/coco3_keyboard_matrix.v`, `rtl/cocokey.v`, `rtl/PS2_Key/ps2_keyboard.v` | PS/2 scan reception and CoCo matrix translation |
| `rtl/CPU09/cpu09l_128.vhd` | Inherited VHDL `cpu09`, compiled for real boot and CPU diagnostic |
| `rtl/coco3vid.v` | Inherited CoCo renderer with portable character ROM and native-text fetch/scroll corrections |
| `rtl/core/coco3_gime_timer.v` | Partial GIME timer/interrupt implementation |
| `rtl/core/coco3_fdc.v`, `coco3_disk_image.v` | Minimal WD1773-compatible interface; optional read-only embedded DSK backend |
| `rtl/core/sd_spi_init.v`, `sd_spi_read_sector0.v` | J13 initialization and sector-zero probe only; no FAT32 mounting |
| `rtl/wukong/ntsc_artifact_filter.v`, `crt_filter.v` | Streaming artifact colors, scanlines, glow |
| `rtl/wukong/coco3_uart_debug.v`, `uart_tx.v` | Passive USB serial logging |
| `rtl/wukong/coco_video_source.v`, `coco3_diagnostic_system.v` | Synthetic-video and CPU-diagnostic wrappers |
| `rtl/wukong/hdmi/` | Local raster/test pattern and Artix-7 serializer; legacy local encoder retained |
| `rtl/wukong/wukong_hdmi_tx.sv` | Experimental packet wrapper behind `HDMI_AUDIO`; no launcher mode defines that symbol |
| `rtl/third_party/hdl-util-hdmi/` | Vendored channel encoding and HDMI raster/packet/serialization library |
| `constraints/wukong.xdc` | V3 clock, HDMI, PS/2, J13 SPI, and UART pins and timing constraints |

`HDMI_COCO_AUDIO` uses the library instance in `wukong_top.v`, not the
experimental `HDMI_AUDIO` wrapper. Library modes use 25.2/126 MHz clocks;
local fallback modes use 25/125 MHz. Real boot uses `NEW_SRAM` and CPU enables
with 128 KiB BRAM; no DE1 SRAM clock/arbitration block is required.

## Inherited sources outside the active machine

`rtl/coco3fpga_dw.v` is the original CoCo3FPGA DE1 top. `CoCo3IO.v`, `sound.v`,
and `paddles.v` are include fragments for that design. The legacy SPI SD module
is `rtl/SPI/SDCard.v`; it is not the current J13 probe. T65 and the UART cores
remain under their own `rtl/` directories and are not the Wukong storage or
USB debug implementation. DriveWire is not being ported.

`legacy-quartus/` preserves the original QPF/QSF, generated Altera RAM/FIFO/
clock wrappers, QIP manifests, MIF data, black boxes, and instantiation
examples. These are not compiled by Vivado. Some historical QSF inputs are
missing; see [the legacy project notes](../legacy-quartus/README.md).

## Ownership and limitations

Keep board adaptation in `rtl/wukong/` and portable machine logic in `rtl/core/`.
Preserve imported CPU/peripheral and third-party boundaries. The active design
has no FAT32 file service, management CPU/GUI, writable disks, physical floppy,
external-memory controller, physical joystick ADC, printer/cassette/RS-232 PAK,
or DriveWire backend. Optional embedded DSK inputs are untracked.

The implementation is a partial CoCo 3 compatibility layer, not a complete
replacement for every legacy peripheral. See [current status](CURRENT_IMPLEMENTATION.md)
and [diagnostic compatibility](DIAGNOSTIC_COMPATIBILITY_PLAN.md) for hardware
video/audio issues and regression coverage.
