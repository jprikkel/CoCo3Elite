# CoCo3Elite SD-card disk interface

The [SD-card and USB support plan](../docs/SDCARD_SUPPORT_PLAN.md) is the current
implementation roadmap. It supersedes the scope, order, and architecture choices
in the earlier proposal below, including its root-only/read-only restrictions.
It includes writable DSKs, cartridge/BAS/BIN loading, an FPGA management
processor, and USB storage/input expansion. Registers below remain proposals.

## Current implementation

MicroSD currently supports SPI initialization and physical sector-zero reads
only—not FAT32 DSK mounting. `rtl/core/sd_spi_init.v` initializes the card;
`sd_spi_read_sector0.v` issues CMD17 for sector zero and checks its final
`55 AA` signature. A successful signature check is not filesystem recognition.
The probe repeats the read approximately once per second. A failed command is
reported as an error, then the SPI engines retry initialization, so removing
and reinserting a card can be observed without reconfiguring the FPGA. This is
still only a diagnostic checkpoint, not a general block-device or mounted-file
backend.

The Digilent Pmod MicroSD is on J13: pin 1/N22 chip select, pin 2/N21 MOSI,
pin 3/R20 MISO, pin 4/T22 clock, pin 5 ground, pin 6 3.3 V. See the
[PMOD pinout](wukong-pmod-pinout.md). The boot machine exposes probe status
at `$FF60` and detail at `$FF61`; after initialization these reflect the
sector-zero reader. No card-detect input is wired.

The minimal FDC already exposes `$FF40` and `$FF48-$FF4B`. Its only image
backend is optional read-only block ROM: `-EmbeddedTestDisks` embeds local,
untracked `disks/fpgatest.dsk` as drive 0 and `disks/games.dsk` as drive 1.
Without that switch sector operations report not-ready. See
[disk preparation](../disks/README.md). Neither path implements writes.

Everything below is a future design proposal. FAT32 parsing, named-file
mounting, four mount slots, a management CPU, F12 overlay, mount registers,
BASIC syntax extensions, and the physical-floppy backend are not implemented.
F12 currently maps to CoCo `@`. Copying a DSK to an SD card does not mount it.

## Proposed goal

The planned storage service will mount ordinary CoCo `.DSK` files from a FAT32
card, replacing the optional embedded test backend. DriveWire and HDB-DOS
containers are outside this plan. A future backend interface would also allow
a physical floppy through a protected PMOD adapter.

The intended Disk Extended Color BASIC syntax is:

```basic
DRIVE 0,"JOUST.DSK"
DRIVE 1,"UTILS.DSK"
DRIVE 2,PHYSICAL
DRIVE 0,UNLOAD
```

After an image is mounted, existing commands such as `DIR`, `LOAD`, `LOADM`,
`SAVE`, and `RUN` continue to use the normal Disk BASIC drive number.

## Proposed initial scope

- FAT32 media using either an MBR partition or a FAT32 superfloppy layout
- Four mount slots, drives 0 through 3
- Files in the root directory
- Case-insensitive DOS 8.3 filenames
- Headerless 161,280-byte images (35 tracks, 18 sectors, 256 bytes/sector)
- Read-only sector access
- Per-drive selection of an SD image or physical-floppy backend

Subdirectories, long filenames, JVC headers, image creation, and writable
images are later milestones. Restricting the first implementation keeps an
unexpected reset or card removal from corrupting the FAT filesystem.

The first SD milestone does not implement the physical backend, but its
internal interface and drive configuration must not assume that every drive
is backed by a file.

## Storage backends

Each CoCo drive number has an independent backend assignment:

| Backend | Purpose |
| --- | --- |
| Unmounted | Report drive-not-ready |
| SD image | Access a mounted FAT32 `.DSK` or later `.SDF` file |
| Physical | Access a real floppy through the external Shugart adapter |

The proposed BASIC interface is:

```basic
DRIVE 0,"JOUST.DSK"
DRIVE 1,"UTILS.DSK"
DRIVE 2,PHYSICAL
DRIVE 3,UNLOAD
```

`DRIVE n,PHYSICAL` assigns the physical interface to drive `n`. Only one CoCo
drive may own a single physical interface at a time unless later hardware
provides multiple physical drive-select outputs. Reassigning it automatically
disconnects its previous logical drive.

The WD1773 command engine owns the CPU-visible registers, status, DRQ, and
interrupt behavior. It sends a common internal request containing drive,
side, track, sector, command, and data to the selected backend. Consequently,
software that accesses the controller registers directly does not depend on
the Disk BASIC mount code after a backend has been selected.

## Architecture

The preferred architecture uses a separate management subsystem, inspired by
the division of responsibilities in products such as the Ultimate 64 but
implemented specifically for CoCo3Elite:

- A small soft CPU and firmware own SD initialization, FAT32, directory
  browsing, configuration, and `.DSK` file metadata.
- An FPGA overlay engine presents a setup/file-browser GUI over HDMI. F12
  opens and closes it without changing the CoCo display mode.
- A keyboard arbiter sends PS/2 events either to the CoCo matrix or to the
  management subsystem. While the GUI is open, arrow keys move the selection,
  Enter activates the selected item, and Esc returns to the preceding screen.
  These navigation keystrokes are consumed by the GUI rather than leaking into
  the running CoCo program.
- A mailbox connects the management CPU to the CoCo-facing hardware. Mount
  table changes are atomic so the emulated machine never observes a partially
  mounted image.
- The WD1773-compatible controller remains FPGA hardware and exposes normal
  registers at `$FF40` and `$FF48` through `$FF4B`. It sends sector requests to
  whichever backend is assigned to the selected drive.
- SD-image and physical-floppy implementations share the same backend
  contract. Programs that access the WD1773 directly therefore remain
  compatible after a drive has been mounted.

Disk BASIC ROM changes are optional convenience features rather than the
filesystem implementation. A future `DRIVE 0,"JOUST.DSK"` command can send a
request through the mailbox, while the management firmware performs the FAT32
work. The first usable interface will be the on-screen file browser.

This separation also keeps higher-level filesystem code in C or C++ firmware,
where it is easier to test, while timing-sensitive SPI, video overlay, mailbox,
and floppy-controller behavior stays in HDL.

## Implementation plan

1. Specify the management CPU, BRAM budget, mailbox registers, mount-table
   records, keyboard-event interface, and the common sector-backend transaction.
2. Implement the first visible GUI shell: F12 toggles the HDMI overlay; Up,
   Down, Left, and Right navigate; Enter selects; and Esc backs out. Verify that
   the CoCo receives normal keyboard input with the GUI closed and receives none
   of the GUI navigation events while it is open. The initial menu may contain
   placeholder System, Drives, and About entries.
3. Provide a reliable SD SPI block device to the management CPU and test card
   insertion, removal, timeout, and sector reads independently of Disk BASIC.
   The implementation must provide clocks while the card is deselected between
   command transactions, tolerate a card that remained initialized across an
   FPGA-only reconfiguration, parse CMD58 to distinguish SDHC block addressing
   from byte addressing, and use bounded response/data-token timeouts. Because
   the Digilent Pmod has no card-detect signal, availability must be established
   by successful command responses rather than a hard-wired presence bit.
4. Add read-only FAT32 and DOS 8.3 directory support in management firmware,
   followed by a serial/debug listing command.
5. Extend the GUI shell into a file browser; allow a selected
   `.DSK` file to be assigned to drives 0 through 3.
6. Connect the mount table to the WD1773-compatible controller and verify
   `DIR`, `LOAD`, `LOADM`, direct sector access, and multi-drive operation.
7. Add safe writes to already allocated image sectors, then long filenames,
   subdirectories, and additional image formats.
8. Implement the protected PMOD physical-floppy adapter and backend, allowing
   each logical drive to select either an SD image or the physical mechanism.

USB mass storage is a later hardware option. The Wukong board's onboard USB
connection is a USB-to-UART bridge, not a USB host, so USB storage would need
an external host controller or a different board interface.

Any future imported management code must be reviewed for its actual license
and compatibility. Copied or adapted code must be kept in a separate,
clearly named source directory with its original copyright and GPL notices,
license text, provenance, and a record of local modifications. Project-specific
interfaces should sit outside that directory so the imported component can be
updated and audited independently. Only the portions needed by the management
subsystem should be imported; unrelated C64 platform code and dependencies
should remain upstream.

## Proposed Wukong extension registers (not implemented)

The proposed mount service would use addresses outside the WD1773 register window so normal
disk software cannot accidentally issue mount commands.

| Address | Read | Write |
| --- | --- | --- |
| `$FF62` | Mount status | Command |
| `$FF63` | Error/detail | Target drive, 0-3 |
| `$FF64` | Filename buffer position | Reset filename buffer |
| `$FF65` | Filename byte at position | Append filename byte |

Commands written to `$FF62` are:

| Value | Operation |
| --- | --- |
| `$01` | Mount the buffered filename on the target drive |
| `$02` | Unmount the target drive |
| `$03` | Query the target drive |

Mount status values are:

| Value | Meaning |
| --- | --- |
| `$00` | Idle or unmounted |
| `$01` | Busy |
| `$80` | Mounted and ready |
| `$E1` | SD card unavailable |
| `$E2` | FAT32 volume unavailable |
| `$E3` | Invalid drive number |
| `$E4` | Invalid filename |
| `$E5` | File not found |
| `$E6` | Unsupported image format or size |
| `$E7` | FAT chain error |
| `$E8` | Card removed during operation |

The protocol is deliberately independent of HDB-DOS and DriveWire. A future
ROM or machine-language utility can use the same registers without depending
on the BASIC command parser.

## Physical-floppy target

The physical backend targets a single Shugart-compatible floppy interface
first. Expected signals include drive select, motor enable, direction, step,
side select, write gate, write data, read data, track zero, index, and write
protect. Ready or disk-change may be added if sufficient pins are available.

A floppy drive must not connect directly to Wukong PMOD pins. The external
adapter must provide 3.3 V level compatibility and suitable active-low,
open-collector drive circuitry, while the floppy mechanism receives its own
power. The final allocation may span more than one PMOD because a single
four-signal connector cannot carry the complete interface.

The physical backend will add read-data separation/PLL, FM/MFM decoding and
encoding, CRC handling, index synchronization, head-step timing, and guarded
write support. Pin assignment and adapter design follow completion of the
read-only SD-image milestone.

## Sector translation

For the initial image format:

```text
image sector = track * 18 + (sector - 1)
byte offset  = image sector * 256
```

The backend translates the byte offset through the mounted file's FAT32
cluster chain. It must not assume that a `.DSK` file is physically contiguous
on the SD card.

## Safe-write milestone

Write support requires more than accepting WD1773 write-sector commands. The
backend must update data sectors without altering the image length, complete
the SD write before reporting success, reject writes after media removal, and
preserve unrelated bytes and filesystem consistency. Fixed-size images avoid
allocation changes, but ordinary filesystem writes may still update directory
metadata. Flush filesystem and block-device buffers before reporting success;
see the current plan for reset/removal and power-loss limits. Until those
conditions are tested, the controller reports write-protect status.
