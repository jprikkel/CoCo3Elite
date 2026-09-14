# Direct BIN file loading

Status: proposed design. Direct `.BIN` loading from the SD-card management UI
is not implemented yet.

## Purpose

Allow the F12 management browser to load and automatically execute a standard
Disk Extended Color BASIC machine-language `.BIN` file directly from FAT32.
The user should not need to copy the file into a `.DSK` image or type `LOADM`
and `EXEC` manually.

This is a read-only launch feature. It does not add host-file creation,
rewriting, or `SAVEM` support.

## Supported input

The first implementation should accept only the standard DECB `LOADM` binary
format. A file contains one or more data records, each with a five-byte type,
length, and load-address header, followed by a five-byte execution record.
Length, address, file bounds, and the final execution address must all be
validated before the CoCo is launched.

An unadorned raw binary has no load or execution address and is therefore
ambiguous. Reject it with `UNSUPPORTED BIN FORMAT` instead of guessing. A
future sidecar file could supply those addresses if raw-image support becomes
useful.

The parser should reject:

- A truncated header or data record.
- A record whose declared length exceeds the remaining file.
- A missing, malformed, or duplicate execution record.
- A destination that overlaps CoCo I/O at `$FF00-$FFEF`.
- A load that exceeds the implemented 128 KiB physical-memory model.
- Additional bytes after the final record, unless a documented format permits
  them.

ToolShed's `decb binbust` documentation is the reference for the record model,
and files produced by `decb copy -2 -b` should be used as fixtures.

## Recommended architecture

Use a temporary project-owned loader ROM-Pak and a small byte-stream mailbox.
Do not add a program-counter override to the third-party MC6809 and do not add
a third port to the dual-port CoCo RAM.

```text
FAT32 BIN file
      |
      v
RV32 validates DECB records and execution address
      |
      v
small manager-to-CoCo FIFO at unused project MMIO
      |
      v
temporary 6809 loader in cartridge RAM at $C000
      |
      v
CoCo RAM data records -> RAM trampoline -> execution address
```

The existing cartridge storage is sufficient for the small loader. Only the
FIFO, status registers, and final RAM trampoline consume new storage.

## Launch sequence

1. F12 displays `.BIN` entries with a `[BIN]` marker.
2. Firmware opens the file and validates every record without changing CoCo
   state.
3. The current cartridge is disabled.
4. The CoCo receives the same guarded cold reset used by `.CCC` launching.
   The RV32, FAT32 mount, selected disk, and dirty-disk ownership remain alive.
5. Hardware waits for the system ROM to leave and then return to the BASIC idle
   loop around `$A7D3-$A7D7`.
6. Firmware installs the project-owned loader in cartridge RAM and launches it
   through the proven CART/FIRQ path.
7. RV32 streams validated record headers and data through a small FIFO. The
   6809 loader writes the bytes to their logical addresses.
8. If a record targets RAM hidden by ROM, the loader temporarily selects
   all-RAM mode for the store while preserving the mapping expected at entry.
9. The loader copies a short final trampoline into safe low RAM and jumps to
   it.
10. The trampoline disables the temporary cartridge, restores the required ROM
    mapping, and jumps to the execution address from the BIN trailer.

This is analogous to a cassette or `LOADM` transfer, but the SD reader and FIFO
remove the audio encoding and timing delay.

## Mailbox design

Reserve a small project-owned register window outside the standard PIA, GIME,
and FDC registers. The exact address must be checked against all implemented
and planned cartridge hardware before assignment.

Minimum signals are:

| Register | Direction | Purpose |
| --- | --- | --- |
| Status | CoCo read | Data available, transfer complete, error, card removed |
| Data | CoCo read | Next byte from the RV32 FIFO |
| Control | CoCo write | Start, acknowledge, cancel, loader complete |
| Detail | CoCo read | Error code or remaining-record state |

A 16- or 32-byte asynchronous FIFO is enough. SD sectors remain in firmware's
existing 512-byte buffer. The 6809 may poll when the FIFO is empty; SD latency
must never be exposed as an unconstrained combinational wait on the CPU bus.

## Reset and cancellation

- Ctrl+Alt+Delete cancels a transfer, disables the loader cartridge, clears the
  FIFO, and returns to Disk BASIC.
- SD removal during a transfer stops delivery and reports an error. It must not
  execute a partially loaded program.
- F12 should not reopen the menu while the loader owns the cartridge and FIFO.
- A load failure must not alter the currently mounted `.DSK` or mark its cache
  dirty.
- After a program exits or is reset, the temporary loader is no longer mapped.

## Why not write RAM directly from RV32

The 128 KiB CoCo RAM is already dual-port: the MC6809 uses one port and video
uses the other. Direct manager DMA would require arbitration on an active port,
careful MMU translation, and proof that video or CPU reads cannot observe a
half-written value. The loader approach uses ordinary 6809 writes and naturally
follows the machine's logical address map.

Direct DMA may later be added as an optimization, but it is not required for a
fast loader.

## Tests

Add automated tests before hardware validation:

1. Parser tests for one record, multiple records, zero-length edge cases,
   malformed lengths, missing trailer, and I/O overlap.
2. FIFO tests for full, empty, wrap, cancellation, and back-pressure.
3. A boot-system simulation that launches a generated BIN, verifies bytes in
   several RAM regions, observes loader removal, and reaches the declared entry
   point.
4. Reset tests during validation, transfer, and execution.
5. SD-removal tests before and during transfer.
6. Hardware tests using small source-controlled programs generated during the
   test build. Do not commit copyrighted commercial binaries.

Acceptance requires deterministic launch at normal and fast CPU rates, a clean
return to Disk BASIC after reset, and no regression in DSK or CCC operation.

## Relationship to BAS files

ASCII and tokenized BASIC files are a separate problem. They require BASIC
tokenization, program-pointer updates, or controlled keyboard/ROM entry and are
more sensitive to ROM revision. Complete and validate BIN loading before adding
direct `.BAS` execution.

## Relevant implementation files

- [`firmware/management/rv32_sd_mount.c`](../firmware/management/rv32_sd_mount.c)
- [`rtl/management/manager_sd_mmio.v`](../rtl/management/manager_sd_mmio.v)
- [`rtl/core/coco3_boot_machine.v`](../rtl/core/coco3_boot_machine.v)
- [`rtl/core/coco3_sd_cartridge.v`](../rtl/core/coco3_sd_cartridge.v)
- [`rtl/wukong/coco3_boot_system.v`](../rtl/wukong/coco3_boot_system.v)
