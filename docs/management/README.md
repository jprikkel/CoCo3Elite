# Management subsystem bring-up

The management subsystem is independent of the emulated CoCo. It will own SD
FAT32, the HDMI overlay, input arbitration, mount metadata, and later USB host
services. It must never add timing-dependent work to the 6809, GIME, or FDC
paths.

## First smoke test

`rtl/third-party/ultraembedded-riscv` is an unmodified vendored snapshot of
`ultraembedded/riscv`, pinned at `7ae6f803e30f78c6ea3121e73c3adf50ff912730`
under its BSD-3-Clause license. It intentionally has no nested Git metadata:
the parent repository contains the exact upstream source needed for a build.
`rtl/management/ultraembedded_manager_smoke.v` uses its provided 64 KiB
TCM/AXI wrapper. A small loader writes a four-word
RV32IM program at the documented `0x2000` boot vector before releasing the CPU.
The program performs one AXI-Lite write of `0x53` to `0x80000000`; the local
test peripheral captures it.

Run:

```powershell
.\scripts\test_ultraembedded_manager_smoke.ps1
```

A passing result proves that the upstream core fetches from the TCM, executes
the boot program, and reaches a local management MMIO peripheral. It is not
connected to J13, USB, HDMI, the CoCo keyboard, or the CoCo bitstream.

For a target-specific resource and timing check without adding it to the CoCo
top level, run:

```powershell
.\scripts\synth_ultraembedded_manager_smoke.ps1
```

The initial Artix-7 out-of-context result at 50 MHz is 3,318 LUTs (5.23%),
2,607 registers (2.06%), 16 RAMB36s (11.85%), and 4 DSPs (1.67%), with
`+7.739 ns` setup slack. These include the 64 KiB TCM and the test loader; the
normal CoCo image has not yet been changed.

## Hardware smoke image

`build_wukong_manager_smoke.ps1` creates a separate bitstream that drives only
the Wukong 50 MHz input and the CH340N FPGA-to-PC UART pin. It runs the same
RV32IM TCM/MMIO test and sends `RV32 OK` at 115200 8-N-1. It does not drive
HDMI, SD, PS/2, or any CoCo hardware, and it cannot access a disk.

`test_wukong_manager_smoke_uart.ps1` decodes the complete banner in simulation
before the hardware image is loaded.

## Firmware-driven SD/FAT32 bring-up

`build_wukong_manager_sd_fat32.ps1` creates a separate image using J13 for the
Digilent Pmod MicroSD and the FPGA-to-PC UART. It compiles
`firmware/management/rv32_sd_fat32_list.c`, generates a loader ROM under
`build/`, writes that firmware into the upstream core's 64 KiB TCM through its
documented AXI port, and releases the CPU.

The project-owned MMIO peripheral exposes UART data/status plus single-byte SPI
control, transfer, and receive registers. A transfer-store response is delayed
until its SPI byte completes, so the firmware owns SD commands, FAT32 parsing,
and directory output; no filesystem policy lives in HDL.

With an SDSC, SDHC, or SDXC card containing a 512-byte-sector FAT32
superfloppy or first MBR partition, it prints `RV32 SD`, `FAT32 ROOT`,
root-directory 8.3 filenames, the raw end of `README.TXT`, its final text
characters, and `END` at 115200 baud. `README.TXT` is the media-integrity
sentinel: its final non-line-ending characters must be ASCII `42`; CR/LF after
that text is accepted and shown in the raw-tail hex dump. The firmware handles
SDSC byte addressing through CMD16 and SDHC/SDXC logical block addressing.
`ERR xx` identifies the first initialization, card, or layout error. This
read-only diagnostic is not a CoCo image, file browser, or mount implementation.

```powershell
.\scripts\test_manager_sd_mmio.ps1
.\scripts\test_manager_sd_fat32_firmware.ps1
```

## Integrated CoCo disk browser milestone

The normal `COCO3_ELITE` build now boots the RV32 management firmware alongside
the CoCo. Firmware owns SD SPI and FAT32 traversal, discovers root-directory
8.3 `.DSK` files with the supported 161,280-byte geometry, and loads the selected
image into the drive-0 dual-port cache. The FPGA FDC serves CoCo sector transfers
from that cache; completed writes are flushed to the existing FAT32 file.

F12 opens a 48-by-20 character HDMI overlay. Up/Down change the selection,
Enter reloads drive 0 from the selected image, and Esc/F12 closes the overlay.
The CoCo CPU is halted at its adapter while the menu is open and menu keystrokes
are not delivered to the CoCo matrix. The overlay bypasses narrow-mode video
alignment delay and addresses the CoCo font with full seven-bit ASCII.

Hardware validation on 2026-09-10 confirmed correct `DIR`, `LOADM`, execution,
save/reload persistence, ZENIX operation, and mounting every compatible DSK on
the test FAT32 card. Long filenames, subdirectories, drives 1-3, safe eject,
and generalized image geometry remain follow-on work.

## Import policy

Keep imported HDL in `rtl/third-party`; keep all project-owned wrappers and
peripherals in `rtl/management`; keep manager firmware in
`firmware/management`. The imported CPU must stay unmodified. Any upstream
update must record its exact commit, preserve its license, and rerun this smoke
test before it enters the normal build.
