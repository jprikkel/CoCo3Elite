# SD-card, file loading, and USB support plan

Status: active implementation on `sdcard-support`, based on `ab27a47`.
The first integrated FAT32/DSK browser milestone was hardware-validated on
2026-09-10; later capabilities remain planned as identified below.
User preference: keep management processing inside the FPGA and add only the
external hardware needed for USB.

Implementation checkpoint: the open ultraembedded RV32 core now runs the SD and
FAT32 management firmware in the normal CoCo bitstream. It discovers compatible
161,280-byte root-directory `.DSK` files, caches the selected drive-0 image,
services WD1773 reads and writes, and flushes changed sectors back to the mounted
FAT32 file. F12 opens a centered firmware-populated HDMI menu; Up/Down select an
image, Enter mounts it as drive 0, and Esc/F12 closes the menu. Menu keys are
blocked from the CoCo while the overlay is active. Hardware validation confirmed
correct directory listings, `LOADM`/execution (including ZENIX), saving and
reloading files, and selection of every compatible DSK present on the test card.

The earlier isolated SPI/MMIO transport, RISC-V driver compile check, and
MicroBlaze V synthesis prototype also remain available. See
[USB FPGA-side preparation and wiring](../hardware/usb-host-interface.md) for
the exact implemented scope and reproduction commands. No module is available;
USB enumeration, CPU firmware boot, filesystems and CoCo integration remain
pending. The working CoCo bitstream is unchanged.

## Recommendation

Use a small RISC-V management processor inside the FPGA, running C firmware
with FatFs for filesystems. Keep CoCo CPU, GIME, video, audio, and floppy bus
timing in RTL. Continue using the J13 Pmod MicroSD connection. Add an external
MAX3421E USB host controller over a separate SPI interface when USB work begins.
Run TinyUSB host firmware on the management processor for USB mass storage,
keyboards, mice, and supported game controllers.

Evaluate **NEORV32 and AMD MicroBlaze V** before freezing the CPU choice.
NEORV32 is the provisional preference for a portable open HDL/firmware build;
MicroBlaze V provides AMD's RISC-V/Vivado/Vitis integration. Use VexRiscv as a
performance alternative and PicoRV32 as a compact baseline. The companion
[processor evaluation](MANAGEMENT_PROCESSOR_EVALUATION.md) compares ARM,
RISC-V, classic MicroBlaze, and others, and records what the C64 Ultimate uses.
These are candidate components, not cores already validated in this design.

The MAX3421E includes a USB transceiver and low-/full-speed host controller
behind SPI. It needs firmware and a powered USB connector. TinyUSB lists a
MAX3421E host driver and host support for MSC, HID, and hubs; porting its board,
SPI, interrupt, and timing hooks to our soft processor remains project work.
USB throughput and simultaneous device operation must be measured in an early
prototype. See [MAX3421E][max3421] and [TinyUSB][tinyusb].

## Required user behavior

| Requirement | Planned result |
| --- | --- |
| Select DSK files from ordinary PC media | Browse folders on FAT32 SD cards, select an image, and mount it as drive 0, 1, 2, or 3. No special raw-card layout or bitstream rebuild. |
| Read and save mounted disks | Existing Disk BASIC `DIR`, `LOAD`, `LOADM`, `SAVE`, and `SAVEM` use the selected image; successful writes persist in that same DSK file. |
| Load CoCo cartridge files | Select a raw `.ROM`/`.CCC` image, load it into cartridge memory, and choose Mount or Run. Run performs the selected cartridge launch sequence. |
| Run loose BAS/BIN files | Select Load or Run directly in the file browser without manually creating a DSK; the service supplies a temporary virtual Disk BASIC volume to the normal loader. |
| Use USB storage | The same browser and loaders work with a USB flash drive as another volume. SD and USB can be present together. |
| Use USB input devices | USB keyboard controls CoCo/menu; mouse controls the menu; supported joystick/gamepad reports map to the existing CoCo joystick interface. |

FAT32/exFAT describe storage filesystems. USB MSC describes storage transport;
USB HID describes input devices. A FAT32 choice does not enable keyboards or
joysticks: the USB host hardware and HID firmware do that independently.

## Current design and constraints

- `rtl/core/sd_spi_init.v` and `sd_spi_read_sector0.v` provide initialization
  and a sector-zero probe only. A `55 AA` signature is not filesystem detection.
- `rtl/core/coco3_fdc.v` has a minimal read-only WD1773-style register interface.
  Under `EMBEDDED_TEST_DISKS` it still instantiates two BRAM disk images despite
  the obsolete introductory comment. It has no asynchronous sector interface,
  write transfer engine, or complete physical-controller timing model.
- `coco3_boot_machine.v` currently ties CPU HALT inactive. `cpu09.v` provides
  project-owned MC6809 adaptation; the third-party MC6809 must remain unchanged.
- Main RAM is 128 KiB dual-port BRAM. Both ports already serve CPU/video; a
  management loader needs explicit arbitration rather than an assumed free port.
- Cartridge support is currently a fixed diagnostic ROM and launch mechanism.
  A writable cartridge memory and selectable mapping must be added.
- The 2026-09-08 routed report for the embedded-disk build uses 5,973/63,400 LUTs
  and 124.5/135 BRAM tiles. This is an existing-build measurement, not a new
  synthesis result. Stream disk sectors instead of retaining complete images
  in BRAM, then measure the reclaimed memory before sizing management firmware.
- J13 is SD and J14 is PS/2. J10/J11 are candidate USB expansion connectors.
  PMOD power is 3.3 V; USB host VBUS requires a separate suitable 5 V supply.
  The onboard CH340N USB connector is only a UART bridge.
- Existing documentation contains stale CPU09 paths and earlier diagnostic
  failures. Base integration decisions on active RTL and current hardware
  results, including the user-confirmed ZENIX/ZENVID and MemTest pass.

Local references: [board](../hardware/wukong-board.md),
[PMOD pins](../hardware/wukong-pmod-pinout.md),
[build source list](../scripts/build_wukong.tcl), and
[earlier SD proposal](../hardware/sd-disk-interface.md).

## Architecture alternatives

| Approach | SD/files and loaders | USB expansion | Assessment |
| --- | --- | --- | --- |
| RTL state machines only | Possible for limited FAT32; long names, fragmented files, writes, and loaders greatly expand verification work | Still needs host hardware plus enumeration and class handling | Keep RTL for transfers and timing; unsuitable as the full management service. |
| FPGA soft processor + firmware | Reuses filesystem libraries; supports browser, loaders, configuration, and recovery | MAX3421E with a firmware host stack | Recommended; meets the user's FPGA preference. Budget firmware BRAM and scheduling explicitly. |
| External management MCU | Native USB-host-capable MCU can run filesystem and USB stacks with little FPGA memory use | Integrated host controller plus connector/power circuitry; RP2040 is one candidate [reference][rp2040] | Technically viable fallback, but adds the management board the user prefers to avoid. |
| Existing CoCo 6809 runs management | Could run a utility/driver and use a simple SD block interface | Host stack would occupy CoCo CPU and memory while games run | Useful as a mailbox client, not the owner of background storage/USB. |
| Linux SBC or large Linux soft SoC | Broad filesystem and device support | Mature USB drivers, given suitable host hardware | Much larger boot, memory, integration, and maintenance scope than required. Revisit only if broad NTFS/ext4 or vendor-specific USB support becomes essential. |

For the recommended option, start bare-metal with a bounded event loop. An RTOS
is optional if measurements justify it; neither Linux nor a new operating
system for the CoCo is required. The Artix design would instantiate a soft
processor, not acquire a Zynq-style hardened processing system.

## Division of work

```text
J13 SD card <-> FPGA SD SPI engine ----+
                                      |
USB devices/hub <-> MAX3421E <-> SPI --+--> RISC-V management firmware
                                             | FatFs / TinyUSB / browser
                                             | file and mount services
                            +----------------+----------------+
                            |                                 |
                    sector buffers/mailbox           overlay/input/loader
                            |                                 |
                       FDC RTL                     cartridge RAM / CoCo RAM
                            |                                 |
                            +--------- CoCo MC6809/GIME -------+
```

The firmware exclusively owns each filesystem and its open files. The FDC asks
for image bytes through a sector interface; it must not independently traverse
FAT chains or write raw blocks behind the filesystem's cache. Both SD and USB
implement one block-device API: initialize, status, capacity/sector size,
read, write, and sync. Mount records refer to a volume and file handle, so any
of the four CoCo drives can use either medium.

Define an RTL request/response contract with request ID, mount generation,
drive, operation, geometry/offset, length, buffer ownership, completion, and
error. Use shared dual-port buffers, bounded queues, interrupts, and proper
clock-domain crossings. Complete a mount change atomically after active I/O
has drained. Reject responses from old mounts or reset epochs. A watchdog
failure reports not-ready and releases input; it must not leave the CPU hung.

Separate filesystem jobs from USB servicing: SD busy polling, directory walks,
and synchronous filesystem calls must yield to the USB task at bounded
intervals. Avoid reentering FatFs while it owns a volume. Test the scheduler
under simultaneous disk writes and HID input, not just idle enumeration.

Initial sizing targets, to validate rather than assume: 50 MHz management clock,
64 KiB instruction storage, 32 KiB data/stack, 8-16 KiB transfer/cache buffers,
and a small text overlay. Measure the linked FatFs/TinyUSB/Unicode footprint;
grow or split these allocations based on actual results. Keep working headroom
for cartridge RAM and GMC sound. If firmware exceeds the reclaimed BRAM,
evaluate onboard SDRAM for management memory before making DDR3 a dependency.
512 KiB CoCo RAM is a separate project, not a prerequisite for SD storage.

## Filesystems and media formats

Use [FatFs][fatfs-app] through its disk I/O interface. Proposed support:

| Format/layout | Delivery |
| --- | --- |
| FAT32, MBR partition or unpartitioned volume | First usable release; cards prepared on Windows or Linux, with fragmented files and ordinary cluster sizes. |
| FAT16 | Include through the same library and qualify representative smaller media. |
| Subdirectories and long filenames | Required for the usable browser, even if the earliest bring-up lists only root 8.3 names. Use UTF-8 paths internally; unsupported display glyphs must not change the selected filename. |
| exFAT | Follow FAT32 writes; include before declaring broad SDXC/USB media support complete. |
| GPT | Qualify with the exFAT milestone; FatFs requires its 64-bit LBA configuration for GPT. |
| NTFS, ext2/3/4, encrypted volumes | Outside the initial deliverable; report unsupported filesystem clearly. |

The [FatFs configuration reference][fatfs-config] documents LFN, exFAT,
partition, Unicode, and sector-size options. Enable only the options tested in
our pinned version. Initially qualify 512-byte device sectors; reject other
sizes explicitly until a 4 KiB-sector adapter and tests are added. Do not infer
filesystem type from card capacity. SD protocol addressing and the filesystem
format are separate concerns. Never format a card automatically.

## Mounted DSK read/write behavior

First support headerless 161,280-byte images: 35 tracks, one side, 18 sectors
per track, 256 bytes per sector. Reject mismatched sizes instead of guessing.
Add other geometries and JVC headers through explicit format handlers later.
DMK/raw-track formats and copy-protection emulation need a different track-level
contract and are not implied by basic DSK support.

For the initial geometry:

```text
file byte offset = (track * 18 + sector - 1) * 256
```

Validate every field and resolve the file offset through the filesystem, even
when its clusters are fragmented. A 256-byte CoCo write can share a 512-byte
media sector with another CoCo sector: serialize the read/modify/write and
preserve the other half. Test alternating writes to both halves and cluster
boundary cases. Do not allow the same image multiple writable mounts.

Refactor the FDC to buffer a whole sector before offering read data and to
collect a whole written sector before backend submission. Implement busy, DRQ,
lost-data, write-protect, not-ready, completion interrupt, force-interrupt, and
bounded timeout behavior against a controller reference. Add write-sector and
qualify multisector commands. Do not let unimplemented commands return false
success. `DSKINI`/write-track formatting is a separate command-coverage milestone;
ordinary saves to existing formatted images must work first.

Measure storage latency against Disk BASIC and direct-FDC programs. Keep video,
audio, and GIME timing running during backend waits. If HALT/DRQ bus control is
needed, implement it at the project adapter and verify actual bus release;
do not globally stop clocks or change the third-party MC6809. Preserve the
regression for first-byte timing that previously caused corrupted filenames.

Initially use write-through completion: finish filesystem writes and flush
through `f_sync`/`CTRL_SYNC` before reporting backend success. Normal FatFs writes
can update directory metadata even when image length stays constant; keeping
a DSK fixed-size avoids allocation changes but does not guarantee metadata-free
writes. Honor short writes and all errors. See [f_sync][fatfs-sync] and
[disk_ioctl][fatfs-ioctl].

Provide per-image read-only selection, busy/error display, Flush/Eject, and
generation invalidation on removal. An orderly CoCo reset lets management finish
accepted writes; a management reset, FPGA reload, or power loss has different
recovery semantics. FAT/exFAT and commodity flash are not transactional: sync
reduces exposure but cannot promise atomic game saves or survival of arbitrary
power loss. Keep tests on disposable media and use independent image hashes
and filesystem checks after writes/removal tests. Copy-on-write recovery is a
later option, not a hidden substitute for updating the mounted DSK.

## File browser and cartridge loading

The first text overlay is implemented in the existing HDMI path. F12 is
intentionally reassigned from the old CoCo `@` fall-through mapping. The current
browser lists root-directory 8.3 `.DSK` files and assigns the selection to drive
0; navigation consumes input while open. The later browser will add SD/USB
volumes, directories, four mount slots, write status, and Mount, Unmount, Load,
Run, and Eject actions. Track press/release ownership to avoid stuck CoCo keys.
The menu itself need not stop the CoCo; memory-changing loaders must coordinate
with an idle BASIC loader or a controlled bus halt/reset.

Interpret "CC cartridge" as CoCo cartridge images, conventionally `.ROM` or
`.CCC` [XRoar reference][xroar]. A `.CC` suffix alone is not a defined encoding:
allow an explicit raw-cartridge profile where appropriate. Start with verified
8/16 KiB raw mappings, then add 32 KiB and banked images as distinct profiles.
Extension and size cannot identify every cartridge's hardware.

Load the image into writable FPGA cartridge RAM, validate its length/profile,
then switch mapping only while CPU access is safely stopped. Mount makes ROM
available without starting it; Run follows a tested reset/CART launch sequence.
Avoid partial activation if loading fails. Use staging memory when available;
otherwise keep the cartridge disabled and CPU safely held until the validated
load completes or recovery returns to Disk BASIC. Preserve F3 diagnostics and
offer eject back to Disk BASIC. Cartridge-ROM selection must explicitly resolve
its overlap with Disk BASIC; do not imply an MPI already exists.

A ROM file supplies bytes, not its cartridge peripherals. GMC bank switching
and sound require the separately planned GMC hardware model; other mapper,
RAM, or I/O cartridges remain unsupported until their profiles exist. Keep
user game/ROM images untracked and outside source commits.

## Direct BAS and BIN files

The user selects a loose file on SD/USB and chooses Load or Run. First implement
this through a temporary virtual Disk BASIC disk, synthesized sector-by-sector
by management firmware from the selected file. This avoids creating a host DSK
or storing a whole disk in BRAM, while allowing the CoCo ROM's loader to handle
program placement and BASIC tokenization.

Use a free logical drive; if all four are occupied, require the user to choose
which mount to replace temporarily. Preserve its descriptor for restoration.
Assign a stable short CoCo filename distinct from the host long filename, and
invoke `LOAD`/`RUN` for BAS or `LOADM`/`EXEC` for BIN through an explicitly
invoked, tested BASIC helper. Automatic command entry is allowed only after
establishing that BASIC is ready; never inject commands into a running game.
Keep the temporary mount available while a program may reopen its source or
companion files. Only supported, explicitly included companions are visible;
programs requiring disk-specific layouts still need their original DSK.

Recognize ASCII BASIC (Windows/Linux line endings) and supported tokenized Disk
BASIC files, setting their virtual directory type/ASCII flag correctly. Validate
containers rather than assuming every `.BAS` is plain text. A BIN handler must
recognize DECB load records, multiple address segments, and the execution
record; reject truncated records, address overflow, and unknown formats.
Compare fixtures with [ToolShed][toolshed] and an independent emulator. Raw BIN
images need an explicit load address/entry profile, not a guessed `$C000` jump.

Start with files that fit the standard virtual disk and available CoCo RAM;
show a clear size error otherwise. Raw memory injection can later accelerate
BIN loading, but requires complete prevalidation, CoCo bus arbitration, and a
tested entry trampoline. It must not require direct edits to MC6809 internals.
Saving standalone host BAS/BIN files is a later export feature; saving within
mounted writable DSKs is part of this plan's required release.

## USB hardware, storage, and input

Use a MAX3421E module/adapter with 3.3 V logic, USB-A host connector, suitable
clock circuitry, protected/current-limited 5 V VBUS, and no backfeeding of board
power. Reserve a separate SPI channel plus interrupt/reset and power status as
needed on J10/J11. Final pin assignment follows module schematic review; there
is no 5 V supply on the PMOD. Use a powered hub for concurrent flash drive,
keyboard, mouse, and joystick testing.

This path is low/full-speed USB, not 480 Mb/s high-speed USB. A drive must work
with the tested host transport; target MSC Bulk-Only Transport/SCSI first.
UAS-only devices are outside initial scope. Device firmware quirks and hub
topology require a published tested-device list.

TinyUSB has an [MSC/FatFs explorer example][usb-files] and a
[combined MSC/HID/hub example][usb-combined]. Use these as integration references;
their existence does not prove our RISC-V/MAX3421E build supports every device.
Adapt the board callbacks and run an early combined-device prototype before
investing in a custom USB PCB.

| Device | Translation and initial limits |
| --- | --- |
| Keyboard | Start with boot-protocol keyboards; map usages/modifiers to shared CoCo matrix and hotkey events. Add report-protocol/NKRO and composite-device handling separately. |
| Mouse | Relative movement/buttons drive menu pointer first. In CoCo applications, map to a selected joystick/mouse protocol; a mouse does not become universally compatible merely by enumeration. |
| Joystick/gamepad | Parse HID report descriptors for axes, buttons, and hats; apply dead zone, calibration, and normalization to the existing CoCo joystick comparator model. Support two logical joysticks and configurable buttons. |
| Vendor-specific gamepads | Xbox/XInput, proprietary receivers, force feedback, and Bluetooth need additional drivers and qualification; generic HID support alone is insufficient. |

Share normalized input events between PS/2, USB, and the overlay. Handle held
keys, repeat, disconnect release, menu focus, and key combinations including
Ctrl-Alt-Del. Storage operations must not starve HID polling or the CoCo video.

## Delivery stages and acceptance gates

1. **Architecture prototype.** Pin candidate dependencies; compare minimal
   NEORV32 and MicroBlaze V builds, firmware footprint, and toolchain integration
   using the companion processor evaluation's criteria.
   Build without embedded disks to measure reclaimed BRAM. Document selected
   CPU, SPI/buffer/mailbox contracts, address conflicts (including future GMC),
   clocks, reset domains, and the USB adapter pin/power plan. No new CoCo-visible
   register address becomes permanent without that address-map review.
2. **Management and USB feasibility.** Bring up processor/timer/diagnostics and
   an SD block read/write test. In parallel, when an adapter is available, prove
   TinyUSB on the soft CPU with a keyboard and flash drive through a hub. Log
   worst service gaps and actual resource usage. Failure here revisits the host
   controller/firmware choice before later USB promises are made.
3. **SD filesystem and browser.** Implement arbitrary block access, SD capacity
   and addressing checks, timeout/removal handling, FatFs read support, folders,
   long names, and the overlay. Accept PC-prepared FAT32 cards with fragmented
   files and matching file hashes. Reconfiguration without card power cycling
   must recover; card availability cannot depend on an unwired detect pin.
4. **DSK read integration.** Add four mounts and buffered asynchronous FDC reads.
   Verify `DIR`, BASIC/BIN loading, drive switching, first/last bytes, and ZENIX
   with the same image used for the known-good embedded build. Run backend
   delay/failure injection and check video/audio/interrupt behavior.
5. **Persistent DSK writes.** Add FDC write transfers, sync, mount locking,
   write protection, eject, and reset/removal recovery. Save/reload BASIC and
   binary files, overwrite/delete files, and verify hashes after eject and
   reinsertion on both Windows and Linux. Compare sectors and allocation with
   ToolShed, including fragmented host files and shared 512-byte blocks.
6. **Cartridge and loose-file launchers.** Implement Load versus Run, cartridge
   mapping, the virtual DECB volume, ASCII/tokenized BAS and segmented BIN
   handling. Use repository-owned fixtures, malformed-file cases, and explicit
   recovery tests. Test autostart/eject and normal disk boot after a cartridge.
7. **Filesystem breadth and USB parity.** Qualify exFAT/GPT, mixed SD/USB mounts,
   long paths, media removal, writable USB images, and the same cartridge/BAS/BIN
   actions from USB. Complete keyboard/mouse/HID joystick mapping and simultaneous
   hub testing. Record unsupported formats and device-specific limitations.
8. **Release validation.** Run existing CPU/reset/GIME/video/FDC/SD regressions
   plus new storage, loader, filesystem, and USB tests. Build a timing-clean
   bitstream, record resource/timing reports and firmware/RTL versions, and
   document card preparation, wiring, mount/eject, loaders, and recovery.

9. **Physical Shugart floppy backend.** Evaluate the [Adafruit Floppy
   FeatherWing with 34-pin IDC connector][adafruit-floppy] as the level-shifted
   drive-side adapter. Define a custom PMOD-to-FeatherWing interposer or
   equivalent breakout, because it is not a direct PMOD module and the full
   Shugart signal set exceeds one PMOD. Reserve two PMODs if needed, retain
   J13/J14 assignments, and provide a separately powered floppy drive. Start
   with one 3.5-inch drive and read-only operation: drive select, motor, track
   select/step, side select, index, track-zero, read-data, and write-protect.
   Add a physical-backend mode to the existing FDC mailbox, then qualify
   index/track timing, raw read-data capture, FM/MFM decode, sector CRC, and
   error recovery against real formatted CoCo media. Only after stable reads,
   add write-gate/write-data with an explicit hardware write-disable default,
   current limiting, and removable-media recovery tests. Do not connect a
   floppy drive directly to FPGA pins; the adapter must provide level
   compatibility and the drive must receive its own 5 V supply (and 12 V when
   required by a 5.25-inch mechanism).

SD read/write delivery (stages 3-5) and the management UI can proceed without
waiting for final USB hardware. The USB feasibility result is a dependency for committing to its
final electrical design and device-support claims, not a prerequisite for SD.
Every stage is a reviewable commit with its relevant tests and hardware results.

Proposed source layout: `rtl/management/` for integration, `firmware/management/`
for project services, `firmware/third-party/` for pinned filesystem/USB sources,
and `rtl/third-party/<selected-cpu>/` for the processor. Record each actual
license and revision; preserve upstream notices. Keep firmware builds reproducible
through the existing PowerShell/Vivado workflow with a documented RISC-V GCC
toolchain. Initially embed firmware initialization in the bitstream so missing
or corrupt removable media cannot prevent the management UI from booting.

## Scope boundaries

This plan covers all seven requested capabilities through staged delivery.
External management MCUs remain an evaluated fallback; the selected direction
keeps firmware execution in the FPGA. Physical floppy hardware, DriveWire,
universal cartridge mapper support, NTFS/ext4, Bluetooth, and a Linux runtime
are separate work. A successful mount or USB enumeration is not by itself
evidence that writes, launchers, or input translation work.

## Primary research references

- [NEORV32 processor/SoC][neorv32]: candidate integrated management processor.
- [PicoRV32][picorv32]: smaller CPU alternative and maintenance status.
- [FatFs application notes][fatfs-app] and [configuration][fatfs-config]:
  filesystem integration, memory use, and format options.
- [FatFs sync][fatfs-sync] and [block-device control][fatfs-ioctl]: flush contract.
- [TinyUSB][tinyusb], [MSC explorer][usb-files], and
  [combined host example][usb-combined]: host drivers and integration examples.
- [Analog Devices MAX3421E][max3421]: USB speeds, SPI, and electrical interface.
- [Raspberry Pi RP2040][rp2040]: external-MCU alternative.
- [XRoar manual][xroar] and [ToolShed][toolshed]: CoCo media/loader references.
- [SD Association specifications][sd-spec]: SD command/protocol reference;
  consult applicable SPI details and card documentation during driver work.

[neorv32]: https://github.com/stnolting/neorv32
[picorv32]: https://github.com/YosysHQ/picorv32
[fatfs-app]: https://elm-chan.org/fsw/ff/doc/appnote.html
[fatfs-config]: https://elm-chan.org/fsw/ff/doc/config.html
[fatfs-sync]: https://elm-chan.org/fsw/ff/doc/sync.html
[fatfs-ioctl]: https://elm-chan.org/fsw/ff/doc/dioctl.html
[tinyusb]: https://docs.tinyusb.org/en/latest/
[usb-files]: https://docs.tinyusb.org/en/latest/examples/host/msc_file_explorer.html
[usb-combined]: https://docs.tinyusb.org/en/latest/examples/host/cdc_msc_hid.html
[max3421]: https://www.analog.com/en/products/max3421e.html
[rp2040]: https://www.raspberrypi.com/products/rp2040/
[xroar]: https://www.6809.org.uk/xroar/doc/xroar.shtml
[toolshed]: https://github.com/nitros9project/toolshed
[sd-spec]: https://www.sdcard.org/downloads/pls/
[adafruit-floppy]: https://www.adafruit.com/product/5679
