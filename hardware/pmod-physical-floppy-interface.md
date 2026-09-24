# Read-only physical floppy interface

## Scope

This document defines the proposed first physical-floppy interface for
CoCo3Elite. It connects the Wukong V3 **J13 PMOD** to the
[Adafruit Floppy FeatherWing with 34-pin IDC connector, product 5679][product].
The first implementation is deliberately limited to one drive and read-only
operation. The Adafruit board is a FeatherWing, not a PMOD, so a short custom
cable or passive interposer is required.

![Adafruit Floppy FeatherWing](https://cdn-shop.adafruit.com/970x728/5679-00.jpg)

*Product photograph: Adafruit Industries. See the [product page][product],
[pinout guide][pinouts], and [open PCB design files][pcb].*

The repository-owned connection drawing is shown below. It is a logical wiring
diagram, not a mechanical footprint or PCB fabrication drawing.

![J13 to Adafruit Floppy FeatherWing read-only wiring](pmod-physical-floppy-read-only-wiring.svg)

## Why J13

The normal build now uses the Wukong onboard MicroSD socket, leaving J13 free.
J10 remains assigned to the Atari-style joystick and J14 remains assigned to
the PS/2 keyboard. J11 remains available for the proposed cassette/audio
interface. A build that selects the alternate J13 PMOD MicroSD mapping cannot
also use the physical floppy interface.

Five drive-control outputs and three status/data inputs fit exactly in J13's
eight FPGA signal positions. The omitted signals are not needed to prove
read-only sector access:

- `DEN` is left unconnected. The FeatherWing pull-up selects double density.
- `WRITE GATE` and `WRITE DATA` are left unconnected.
- `WRITE PROTECT`, `DISK CHANGE`, and `READY` are omitted from the first
  interface. Read-only policy is enforced by wiring, not just HDL.

## J13-to-FeatherWing wiring

The FeatherWing names in this table are the labels on the standard Feather
header. The **Feather pad** column gives the numbered through-hole pad in
Adafruit's published PCB design; it is distinct from the 34-pin floppy IDC
number. The active-low names describe the drive-side Shugart signals after the
FeatherWing's level translators. The FPGA-facing signals are 3.3 V logic.

| J13 pin | FPGA pin | Direction at FPGA | Feather label / signal | Feather pad | Floppy IDC pin | Function |
| ---: | --- | --- | --- | ---: | ---: | --- |
| 1 | N22 | Output | `A0` / `Sel` | 5 | 12 | Select the single drive in the Adafruit prototype (DS1) |
| 2 | N21 | Output | `A2` / `En` | 7 | 16 | Spindle motor enable |
| 3 | R20 | Input | `D9` / `RD` | 21 | 30 | Raw read-data transitions |
| 4 | T22 | Output | `A3` / `Dir` | 8 | 18 | Step direction |
| 5 | GND | Power return | `GND` | 4 | — | Common signal ground |
| 6 | 3.3 V | Logic power | `3V` | 2 | — | FeatherWing logic and level-shifter supply |
| 7 | P20 | Output | `A4` / `Stp` | 9 | 20 | Head-step pulse |
| 8 | N23 | Output | `D6` / `Sid` | 20 | 32 | Side/head select |
| 9 | P21 | Input | `D10` / `Trk` | 22 | 26 | Track-zero sense |
| 10 | R21 | Input | `A5` / `Idx` | 10 | 8 | Index pulse |
| 11 | GND | Power return | `GND` | 4 | — | Common signal ground |
| 12 | 3.3 V | Logic power | `3V` | 2 | — | Same 3.3 V rail as pin 6 |

Use both PMOD grounds. Pins 6 and 12 are the same Wukong 3.3 V rail; a
fabricated interposer may join both to the FeatherWing `3V` rail. Confirm J13
pin 1 from the Wukong silkscreen before applying power.

Do not connect the following FeatherWing header pins in this read-only cable:

| FeatherWing pin | Signal | Required state |
| --- | --- | --- |
| `A1` | `Den` | Leave open; onboard pull-up requests double density |
| `D12` | `WG` | Leave open and set the board switch to `NoWr` |
| `D13` | `WD` | Leave open |
| `D11` | `Pr` | Leave open in the first prototype |
| `D5` | `CH` | Leave open |

## Power and electrical safety

The Wukong PMOD pins and FeatherWing host side use 3.3 V logic. The
FeatherWing supplies the required drive-side 5 V-compatible level translation;
never bypass it or wire a 34-pin drive signal directly to the FPGA.

The PMOD connector must **not** power the floppy mechanism. Provide a separate,
regulated drive supply:

- Most 3.5-inch drives require 5 V with enough startup current. Adafruit
  recommends allowing approximately 2 A.
- Many 5.25-inch drives require both 5 V and 12 V.
- Join the drive-supply ground to the FeatherWing/Wukong signal ground.
- Do not connect the drive supply's 5 V or 12 V rail to J13.
- Do not hot-plug the drive power or 34-pin ribbon cable.

Keep the FeatherWing write-enable switch in the **`NoWr`** position. Because
`WG` and `WD` are absent from this cable, an FPGA or firmware fault cannot
assert the write path.

## Ribbon cable and drive selection

The FeatherWing connects `Sel` to 34-pin IDC `SELECT1` (pin 12). It does not
connect the other drive-select lines. Use one drive on the straight,
**untwisted** portion of a PC floppy ribbon cable as described by Adafruit.
Verify cable keying and continuity: some older mechanisms have missing or
nonstandard connector keys.

### DS0 requirement for the final PMOD hardware

The Adafruit FeatherWing is suitable for development, but its fixed DS1 routing
does not match an unmodified Tandy CoCo drive. Tandy drives are normally
configured as **DS0** and listen on 34-pin IDC pin 10. The current prototype
therefore requires either moving the drive's select jumper from DS0 to DS1 or
using a passive adapter that reroutes FeatherWing IDC pin 12 to drive IDC pin
10 while leaving drive pin 12 disconnected. FPGA polarity or firmware changes
cannot correct this physical pin-routing difference.

The final CoCo3Elite floppy PMOD/interposer shall:

- route its active-low drive-select output to **DS0 / IDC pin 10** by default;
- work with a normally configured Tandy drive without changing its jumper;
- optionally provide a clearly labeled DS0/DS1 jumper or switch for non-Tandy
  mechanisms;
- prevent DS0 and DS1 from being driven simultaneously; and
- retain the straight, untwisted ribbon-cable convention.

Until that hardware exists, all Adafruit FeatherWing tests in this document
refer to DS1 unless an explicit pin-12-to-pin-10 adapter is installed.

A 3.5-inch 720K-capable mechanism with double-density media is convenient for
initial electrical tests. Reading original CoCo 5.25-inch media requires a
suitable 5.25-inch mechanism and its required 5 V/12 V supply.

## FPGA implementation boundary

The physical backend should preserve the existing FDC sector request/response
contract:

```text
CoCo WD1773 command
    -> existing coco3_fdc sector request
    -> physical backend selects, seeks, and waits for index
    -> read-data pulse capture and 250-kbit/s MFM clock recovery
    -> ID/data address-mark detection and CRC-16 verification
    -> existing 256-byte FDC sector buffer
    -> completion or not-ready / CRC / record-not-found status
```

Timing-sensitive pulse capture, clock recovery, and MFM decoding belong in
RTL. The management CPU may select the backend, manage motor timeout policy,
and expose diagnostics, but it must not poll GPIO for individual flux pulses.

The first target is ordinary 160K Disk Extended Color BASIC media: 35 tracks,
one side, 18 sectors per track, and 256 bytes per sector. Side selection is
wired from the beginning so 360K, two-sided OS-9 media can follow without a
hardware change.

## Safe inactive states

The future floppy-specific XDC and top-level wrapper must ensure that reset and
FPGA configuration leave the drive inactive:

| Signal | Reset state |
| --- | --- |
| Select | Inactive/high |
| Motor enable | Inactive/high |
| Step | Inactive/high; no transition during reset release |
| Direction | Stable before any step pulse |
| Side select | Side 0 |

Input pins should use 3.3 V LVCMOS constraints and only the pull behavior
required by the FeatherWing interface. Do not reuse the J13 SD-card constraint
fragment for this build; a separate, mutually exclusive floppy constraint
fragment is required.

## Bring-up sequence

1. Continuity-test every interposer connection with all equipment unpowered.
2. Power only the Wukong and FeatherWing. Verify inactive control outputs and
   sensible pulled-up input states over the serial debug interface.
3. Connect the unpowered drive and ribbon cable, then apply the external drive
   supply. Confirm index pulses and track-zero state without moving the head.
4. Add bounded seek-to-track-zero and single-step tests with serial telemetry.
5. Capture raw read-data pulse intervals from one revolution and compare them
   against simulation fixtures.
6. Add MFM decoding, address-mark detection, sector CRC, and a read-only sector
   command. **Complete.**
7. Connect the physical backend to `coco3_fdc`, run `DIR`, and load files from
   known-good media. **Complete for 35-track, single-sided DECB reads.**
8. Validate reset, missing-media, reversed-cable, CRC-error, and motor-timeout
   recovery before enabling the backend in normal builds.

## Implementation status

The first implementation milestone provides J13 input telemetry plus a bounded
motor/select diagnostic. Build it
with the onboard SD-card slot so J13 is available:

```powershell
.\scripts\build_wukong.ps1 -PhysicalFloppy -SdSlot ONBOARD
```

This build applies `constraints/wukong_floppy_j13.xdc`, synchronizes index,
track-zero, and read-data inputs, and exposes their state through the serial
`FLOPPY` command. `FLOPPY START` selects the drive and enables its motor for a
hard-limited 10 seconds; `FLOPPY STOP` ends the interval immediately. The FPGA
watchdog is independent of firmware.

`FLOPPY HOME` is the first bounded head-motion operation. It waits 500 ms for
spin-up, uses the direction selected at runtime with `FLOPPY DIR 0` or
`FLOPPY DIR 1`, and issues no more than 85 active-low STEP pulses. Each pulse is
20 us with 6 ms between pulses. TRACK0 ends the seek successfully; timeout or
`FLOPPY STOP` removes STEP, motor, and select in hardware. `FLOPPY STEP`
permits one guarded pulse at a time while the drive is active, and `FLOPPY
SIDE 0/1` changes the side-select level. These runtime controls avoid rebuilding
the bitstream while diagnosing older mechanisms. All write signals remain
absent.

The next milestone is also implemented: the FPGA can capture one complete
index-to-index revolution of raw read-data timing from either selected head.
It stores up to 48 KiB of two-clock interval samples, plus complete-turn counts,
minimum/maximum spacing, and an order-sensitive hash. The management firmware
uploads the track over the CH340N serial link at 460800 baud with CRC-32.
`scripts/capture_physical_floppy_disk.ps1` validates transfers, retries without
stepping when necessary, saves per-track native data and JSON metadata, and
assembles a standard SCP image. See `docs/SERIAL_API.md` for the protocol.

An optional indexless recovery path is now implemented for physically flipped
media. `FLUX BULK` records one contiguous 205 ms interval stream in a 48 KiB
FPGA track buffer, and `scripts/capture_physical_floppy_disk.ps1 -Indexless`
steps through the requested tracks and creates an SCP image. Greaseweazle's
`gw convert --reverse` option restores the temporal direction of flipped media.
Only one track is buffered at a time; the host receives it before the next
step, so this does not reserve RAM for an entire floppy image. To fit the track
buffer, the optional physical-floppy bitstream omits serial video-frame capture
while retaining the normal HDMI output. Ordinary builds are unaffected.

The current read-only integration also decodes MFM in FPGA logic. A 4,608-byte
sector cache holds one 18-sector track, and the RV32 firmware services the
existing emulated FDC sector buffer from that cache. `FLOPPY MOUNT` maps the
physical mechanism to Disk BASIC drive 0; writes are rejected. Hardware tests
successfully ran `DIR`, read the `PRO.BAS` directory entry, crossed from track
17 to its data on track 16, and issued `RUN"PRO"` through the normal CoCo FDC
path. The saved TEAC track-16 and track-17 captures both decode byte-for-byte
against the recovered DSK in simulation.

The known-good recovered media is checked in under
`disks/physical-floppy/` as `teac-fd55bv-pro-bas.dsk` and
`teac-fd55bv-pro-bas.scp`. The DSK is the decoded 35-track, single-sided DECB
image used by the captured-track regression; the SCP preserves the original
full-disk flux capture for decoder and interoperability testing.

Hardware validation with a working drive recovered a normal-orientation CoCo
DECB disk in one revolution per track. All 35 tracks captured at approximately
199.6 ms per revolution, and Greaseweazle decoded all 630 of 630 sectors into a
161,280-byte DSK image. A known-faulty drive showed progressively poorer reads
toward the inner tracks, demonstrating that CRC validation and missing-track
reporting reject bad hardware data instead of silently producing an image.
For reliability, inward seeks currently re-home and approach the target in the
outward direction. The tested TEAC ignored the first inward STEP after one
direction reversal; absolute HOME-to-track seeks and outward sequential steps
were reliable. This policy is intentionally conservative and can be optimized
after testing more mechanisms.

Write support is a separate future design. It requires at least `WG`, `WD`, and
write-protect sensing, so it will require another connector or an active
interposer and a new safety review.

## Tested-drive operating notes

The observations below describe the two physical mechanisms used during
bring-up. They are diagnostic results, not reasons to add model-specific RTL.
Both mechanisms use the same Shugart-style active-low control and read signals;
no model-dependent signal-polarity change has been required.

### Tandy FD-502 / Mitsumi D502 mechanism

- A stock Tandy installation normally configures the drive as **DS0**. The
  Adafruit FeatherWing prototype exposes only DS1, so the tested mechanism had
  to be jumpered to DS1 before it could be selected. The final CoCo3Elite PMOD
  hardware must instead select DS0 by default.
- The alternate physical head is independently verified as operational. A
  Greaseweazle wrote all 40 tracks of a Commodore 1541 image through physical
  head 1 with `--reverse --tracks=h=0:hswap`; every track verified, and a real
  Commodore 1541 subsequently read the disk when it was inserted upside down.
  This proves that physical head 1, its read/write electronics, radial
  stepping, and cross-drive alignment are usable.
- Adafruit defines SIDE HIGH as physical head 0 and SIDE LOW as physical head
  1. Consequently, CoCo3Elite's raw electrical command `FLOPPY SIDE 0` selects
  physical head 1; `FLOPPY SIDE 1` selects physical head 0. This is the inverse
  of treating the API value as a head number. Earlier captures labelled
  "head1" but made with `PhysicalSide 1` actually exercised physical head 0.
- The earlier normal-orientation `PhysicalSide 1` captures produced valid CoCo
  MFM sectors near the outer tracks but declined steadily toward the inner
  tracks, with tracks 20 through 34 eventually decoding no sectors. Those
  results now point specifically to the physical-head-0 path, media surface,
  or their alignment rather than to a general drive-mechanism failure.
- Earlier indexless `PhysicalSide 0` attempts recorded no useful transitions,
  but they do not outweigh the later cross-drive write/read validation. Repeat
  that FPGA test with a known-written surface, the latch fully closed, and the
  disk orientation recorded before diagnosing an interface or head fault.
- TRACK0 was not sufficiently stable for the host to require it after the
  drive was deselected. The FPGA's bounded HOME operation did detect and latch
  TRACK0 before stopping, so `OK=1` is the authoritative HOME result.
- Indexed revolutions were close to 200 ms, showing that spindle speed and
  INDEX timing were reasonable.
- For a flipped disk read through physical head 1, select `PhysicalSide 0`, use
  indexless capture if the jacket's index aperture is unavailable, and apply
  Greaseweazle `--reverse` during conversion. `hswap` changes the physical
  head; `--reverse` changes the temporal direction of the captured flux. They
  solve different parts of a flipped-disk operation.

### TEAC FD-55BV mechanism

- The tested FD-55BV was initially configured as DS0. While it remained DS0,
  `FLOPPY START` asserted the FPGA output but produced no new INDEX pulses or
  READ DATA transitions because the FeatherWing was driving DS1. Moving the
  drive jumper to DS1 made INDEX and READ DATA active immediately.
- HOME reached track zero after 16 steps in the initial test. Like the FD-502
  test mechanism, this drive did not retain a live TRACK0 indication after
  motor/select were removed. The FPGA-latched `OK=1` result must therefore be
  accepted even when a later idle `FLOPPY` status reports `TRACK0=0`.
- With a normally inserted single-sided CoCo disk and the runtime electrical
  setting `FLOPPY SIDE 1`, every track captured at approximately 199.6 ms per
  revolution. Greaseweazle decoded 18 of 18 sectors on each of tracks 0 through
  34: 630 of 630 sectors total.
- A single indexed revolution per track was sufficient for a complete image.
  The resulting DECB DSK was 161,280 bytes.

### Signal interpretation summary

| Signal or control | FD-502 test behavior | FD-55BV test behavior |
| --- | --- | --- |
| Drive select | Required DS1 jumper for the FeatherWing prototype; Tandy default is DS0 | No INDEX or READ DATA at DS0; worked after changing to DS1 |
| Motor enable | Active-low prototype control worked | Active-low prototype control worked |
| STEP | 20 us active-low pulse with 6 ms spacing moved the head | Same timing worked; HOME completed after 16 steps |
| DIR | `1` toward track zero and `0` away worked during testing | Same interpretation worked |
| TRACK0 | Unstable or absent after deselection; use latched HOME result | Deasserted after deselection; use latched HOME result |
| INDEX | Approximately 200 ms per revolution when selected | Approximately 199.6 ms per revolution when selected |
| READ DATA | One active-low pulse per flux transition; defective-head quality declined radially | Same interpretation; one revolution decoded every sector |
| SIDE | Electrical `0` selects physical head 1; electrical `1` selects physical head 0 | Same mapping; electrical level `1` read the normal CoCo disk orientation through head 0 |

`FLOPPY SIDE 0/1` deliberately reports the electrical level sent to the
FeatherWing. Per Adafruit's interface definition, HIGH selects physical head 0
and LOW selects physical head 1. Therefore API value `1` means physical head 0
and API value `0` means physical head 1. Keep the electrical value, physical
head, media orientation, and image logical head as separate fields in tests and
metadata.

[product]: https://www.adafruit.com/product/5679
[pinouts]: https://learn.adafruit.com/adafruit-floppy-featherwing-with-34-pin-idc-connector/pinouts
[pcb]: https://github.com/adafruit/Adafruit_Floppy_FeatherWing_PCB
