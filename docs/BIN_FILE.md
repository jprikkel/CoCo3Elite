# Direct BIN file loading

Status: implemented and hardware validated on the Wukong board.

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
- A destination that overlaps the active loader mailbox at `$FF62-$FF64`.
- A load that exceeds the implemented 128 KiB physical-memory model.
- Additional bytes after the final record, unless a documented format permits
  them.

ToolShed's `decb binbust` documentation is the reference for the record model,
and files produced by `decb copy -2 -b` should be used as fixtures.

## Implemented architecture

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
10. The trampoline disables the temporary cartridge, retains Disk BASIC's
    initialized all-RAM mapping and stack, enables IRQ/FIRQ
    as BASIC does before its command loop, and jumps to the execution address
    from the BIN trailer.

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
| Control | CoCo write | Byte acknowledge and loader complete |
| Detail | CoCo read | Error code or remaining-record state |

A 16-byte asynchronous FIFO is implemented. SD sectors remain in firmware's
existing 512-byte buffer. The 6809 polls when the FIFO is empty; SD latency is
never exposed as an unconstrained combinational wait on the CPU bus. The data
register does not consume a byte by itself: after the 6809 samples it, the
loader writes an explicit acknowledge to the control register. This preserves
the byte for the complete multi-clock 6809 peripheral-read cycle.

The current CoCo-side registers are `$FF62` (status), `$FF63` (data), and
`$FF64` (control). The RV32-side FIFO registers are `0x8000026C` (data),
`0x80000270` (control), and `0x80000274` (status).

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

## Hardware validation

Hardware testing on 2026-09-14 confirmed direct SD-card loading and execution
for a broad selection of DECB binaries. Tested working programs include
Daggorath, Cashman, Trapfall, Donkey Devil, Downland, Mud Pies, Bash, Berserk,
Grabber, Astro, Joust, Defender, Zaxxon, Nebula, Galagon, Time Bandit,
Microbes, and P-51.

The first hardware implementation reached each declared execution address but
entered programs with the loader's private stack and with IRQ/FIRQ masked.
Programs that polled hardware directly often worked, while programs dependent
on interrupts either returned to BASIC, produced a continuous sound, or
stalled. The loader now preserves the stack established by the cold-start ROM,
uses a private stack only while receiving records, restores the original stack,
and enables IRQ/FIRQ before transferring control. The private stack grows below
`$FE80`; an earlier `$FEFF` stack corrupted `$FEFD/$FEFE` on every byte-fetch
subroutine call. The MC6809 regression test checks the complete execution
contract and verifies that the top of the vector page remains unchanged.

A second path-specific defect was isolated with programs that displayed
correctly after Disk BASIC `LOADM`/`EXEC`, but produced sound with a blank or
corrupt screen when launched directly. Color BASIC dispatches a plain `EXEC`
with `A=$00`, `B=$44`, `X=$ABAB`, `DP=$00`, the zero flag set, and the normal
BASIC stack. The temporary loader instead leaked its own transfer-loop register
values into the program. The final trampoline now stores the transfer address
in BASIC's `$009D` EXEC vector and reproduces the ROM's register/flag handoff
before performing the same indirect jump. Serial telemetry subsequently showed
that forcing `$FFDE` here changed Disk BASIC's initialized all-RAM state before
program entry. The trampoline now retains `$FFDF`; the regression checks this
state in addition to stack, interrupt, and vector-page integrity.

A program that deliberately returns to BASIC may still require startup
parameters or trailing data that are not represented by a standard DECB
postamble. A remaining video difference must be reproduced through both DSK
and direct-BIN loading before it is classified as GIME/MMU compatibility work.

## Current implementation limits

- Only standard DECB `LOADM` records are accepted; raw binaries are rejected.
- `$FE00-$FEFF` is reserved while loading for scratch state, the loader stack,
  and the final unmap/jump trampoline, so a BIN that loads or executes there is
  rejected before the CoCo state changes.
- LOADM records may write ordinary CoCo hardware registers, matching Disk
  BASIC behavior. Writes to the temporary loader mailbox at `$FF62-$FF64` are
  rejected because they would corrupt the active transfer.
- The postamble must use the conventional `$FF` marker. Its two dummy bytes
  are ignored, matching Disk BASIC `LOADM`; this accepts older loaders such as
  Zenix that store a nonzero value there.
- Bytes after the first valid execution postamble are treated as disk granule
  padding and are neither validated nor sent to the CoCo. Disk-dependent
  programs that use meaningful trailing payload still require a mounted or
  temporary virtual disk path.
- Banked CoCo 3 programs may use the generic `C3B1` container documented below.
  Firmware validates its structure and CRC, then a reusable 6809 loader applies
  its physical MMU placement records. The production firmware contains no
  program-specific signatures, decryption, or patches.
- The original Zenix image is encrypted and disk-dependent, so it is converted
  offline with `scripts/patch_zenix_bin.ps1`. The tool removes score-file I/O,
  bypasses its disk copy check, reproduces the check's menu-unlock edits, and
  preserves `DISKDEINIT`'s `$FFD9` double-speed restore after removing disk I/O.
  It writes a new generic C3B1 file; it never modifies the source BIN or a DSK.
  The converted file is copyrighted output and must not be committed.
- Zenix's 6,816-byte trailing planet payload is separate from the main program.
  Full diskless play still requires converting or servicing that read-only data;
  it must not be implemented by silently writing a source `.DSK` image.
- Both standard DECB and C3B1 records are completely validated before the
  temporary loader cartridge starts.
- The same validator and FIFO boundary can later accept bytes from serial or
  Ethernet without changing the 6809 loader.

### Generic banked CoCo 3 BIN (`C3B1`)

The C3B1 format is intended for programs that cannot be represented by ordinary
16-bit DECB load records because their data occupies multiple MMU banks.

The 16-byte header is:

| Offset | Size | Meaning |
| --- | ---: | --- |
| 0 | 4 | ASCII magic `C3B1` |
| 4 | 4 | Big-endian payload length |
| 8 | 4 | Big-endian IEEE CRC32 of the payload |
| 12 | 4 | Reserved; must be zero |

The payload uses the banked records consumed by
`coco3_banked_bin_loader.asm`. Each record starts with zero, a big-endian
length, and a logical address. When that address is discontinuous, the next
word is a physical MMU placement descriptor included in the record length.
The final record has length four, logical address zero, placement zero, and a
final execution descriptor. The validator rejects malformed sizes, missing
data, extra bytes, and CRC mismatches before resetting the CoCo.

To make a local, read-only Zenix test file:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_zenix_bin.ps1 `
  -InputPath C:\path\to\ZENIX.BIN `
  -OutputPath C:\path\to\ZENIX-PATCHED.BIN
```

Do not add `ZENIX-PATCHED.BIN` to the repository.

### Galactus diskless high scores

The original `GALACTUS.BIN` is a valid single-record DECB binary, but its
startup routine reads track 18, sector 10 from drive 0. On the original game
disk that sector is the 256-byte `HIGHSCOR.BIN` file. Without the companion
disk, the program returns to BASIC even though the main BIN loaded correctly.

`scripts/patch_galactus_bin.ps1` produces a diskless copy. It leaves the
original score decode, checksum, register handling, and cleanup code intact.
Only the call to Disk BASIC's `DSKCON` is redirected to a local stub that puts
the original disk's complete 256-byte default-score sector in the expected
buffer—eight encoded bytes followed by 248 zero bytes—and reports success. The
obsolete score-save entry supplies the stub space, making later save attempts
harmless and non-persistent. Gameplay code, the `$2600` load address, and the
`$2617` execution address are unchanged.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\patch_galactus_bin.ps1 `
  -InputPath C:\path\to\GALACTUS.BIN `
  -OutputPath C:\path\to\GALACTUS-PATCHED.BIN
```

The tool accepts only the verified 20,000-byte source image with CRC32
`7DCEEB92`. Do not add the original or patched copyrighted binary to the
repository.

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
