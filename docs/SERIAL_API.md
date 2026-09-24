# Serial API

The CoCo 3 Elite debug serial port provides a small request/response API for
hardware testing and automation. It can inject CoCo keyboard and function-key
input, reset the emulated machine, query its current state, reset the SD-card
browser to `/`, and capture the final 640 by 480 video frame.

This document describes the protocol implemented by
`firmware/management/rv32_sd_mount.c` and the current Wukong bitstream.

## Transport

- Port: the Wukong board's CH340N USB serial interface, normally `COM5` on the
  development machine.
- Default configuration: 460800 baud, 8 data bits, no parity, one stop bit
  (`8N1`). Management commands, diagnostic traces, frame captures, and raw
  flux transfers all use this rate.
- Flow control: none.
- Requests: case-sensitive ASCII command lines terminated by CR, LF, or CRLF.
- Normal responses: ASCII lines terminated by CRLF.
- Maximum request length: 63 characters, excluding the line terminator.
- Hexadecimal request values accept upper- or lower-case digits. Responses use
  upper-case hexadecimal.

The receive path belongs to the RV32 management firmware. The transmit pin is
shared by management responses and the CoCo diagnostic trace. Repeating trace
output is **off by default** and must be explicitly enabled. A host
must therefore ignore unrelated lines while waiting for the expected response.
Match complete prefixes such as `PONG`, `OK KEY`, or `STATUS PC=` instead of
assuming that the next received line is the reply.

`CAPTURE` and `FLUX` are exceptions: the manager claims the transmit pin for
the entire binary transfer so diagnostic text cannot be inserted into a
payload.

## Command summary

| Request | Successful response | Purpose |
| --- | --- | --- |
| `PING` | `PONG` | Check that the management processor is responsive. |
| `STATUS` | `STATUS PC=.... I0=.. I1=.. VM=.. VR=..` | Read a compact CPU and GIME status snapshot. |
| `FLOPPY` | `FLOPPY ...` or `FLOPPY DISABLED` | Read the optional J13 physical-floppy probe. |
| `FLOPPY START` | `OK FLOPPY START` | Select the physical drive and start its motor for at most 10 seconds. |
| `FLOPPY HOME` | `OK FLOPPY HOME` | Seek toward TRACK0 with an 85-step hardware limit. |
| `FLOPPY STOP` | `OK FLOPPY STOP` | Immediately deselect the physical drive and stop its motor. |
| `FLOPPY DIR 0` / `FLOPPY DIR 1` | `OK FLOPPY DIR n` | Set the electrical DIR level without rebuilding. |
| `FLOPPY SIDE 0` / `FLOPPY SIDE 1` | `OK FLOPPY SIDE n` | Set the electrical side-select level without rebuilding. |
| `FLOPPY STEP` | `OK FLOPPY STEP` | Issue one bounded STEP pulse while the motor/select interval is active. |
| `FLOPPY READ tt ss` | `FLOPPY SECTOR T=tt S=ss DATA=... OK` | Seek, decode, and report the first 16 bytes of one DECB sector (`tt` and `ss` are hex). |
| `FLOPPY MOUNT` | `OK FLOPPY MOUNT D0 READ ONLY` | Route Disk BASIC drive 0 to the physical read-only drive. |
| `FLOPPY UNMOUNT` | `OK FLOPPY UNMOUNT` | Disconnect the physical backend from Disk BASIC drive 0. |
| `FLUX nnnn` | `FLUX BEGIN ...`, binary intervals, `FLUX END ...` | Capture one indexed revolution and transfer one interval window at 460800 baud. |
| `FLUX TRACK` | `FLUX BULK BEGIN ... INDEXED=1`, binary intervals, `FLUX BULK END ...` | Capture and transfer one complete index-to-index revolution. |
| `FLUX BULK` | `FLUX BULK BEGIN ... INDEXED=0`, binary intervals, `FLUX BULK END ...` | Capture a timed 205 ms window when an index pulse is unavailable. |
| `TRACE SNAP` | `OK TRACE SNAP`, then one `PC=... Q=...` line | Request one complete diagnostic snapshot. |
| `TRACE ON` | `OK TRACE ON` | Start one complete diagnostic snapshot per second. |
| `TRACE OFF` | `OK TRACE OFF` | Stop repeating snapshots (the power-on default). |
| `TRACE STATUS` | `TRACE ON` or `TRACE OFF` | Query whether repeating snapshots are enabled. |
| `ROOT` | `OK ROOT` | Reset the SD browser's current directory to `/`. |
| `RELEASE` | `OK RELEASE` | Release all serially injected keys and function keys. |
| `RESET` | `OK RESET` | Release injected input and request a cold CoCo reset. |
| `KD nn` | `OK KEY` | Press CoCo matrix key `nn`. |
| `KU nn` | `OK KEY` | Release CoCo matrix key `nn`. |
| `SH 0` or `SH 1` | `OK SHIFT` | Disable or enable forced Shift. |
| `SO 0` or `SO 1` | `OK SHIFT` | Disable or enable physical-Shift suppression. |
| `FK nn` | `OK FUNCTION` | Change one injected function-key state. |
| `CAPTURE` | `FRAME BEGIN ...` plus binary data and CRC | Capture the final displayed frame. |

## Basic commands

### Liveness

Request:

```text
PING
```

Response:

```text
PONG
```

### Machine status

Request:

```text
STATUS
```

Example response:

```text
STATUS PC=E09B I0=7C I1=20 VM=80 VR=7E
```

The fields are:

- `PC`: current 6809 program-counter snapshot.
- `I0`: GIME `$FF90` INIT0 register.
- `I1`: GIME `$FF91` INIT1 register.
- `VM`: GIME `$FF98` video-mode register.
- `VR`: GIME `$FF99` video-resolution register.

This is a snapshot, not an instruction trace. Software can advance between the
individual hardware samples used to form the response.

### Detailed trace and video-cache metadata

`TRACE SNAP` returns a single detailed `PC=...` line; `TRACE ON` repeats that
line once per second until `TRACE OFF`. Neither `STATUS` nor the default boot
state enables repeating output. `RESET` disables it. The `Q=` field is
eight hexadecimal digits encoding `{miss_count[11:0], last_x[9:0],
last_y[9:0]}` for the most recently completed HDMI frame. Positions refer to
the GIME video-memory fetch, before the downstream RGB/narrow-mode delay.
The count saturates at `FFF`; a zero count means no upper-SDRAM cache misses
were observed in that frame. This is passive telemetry: it does not wait or
change the fetched pixel. `scripts/capture_serial_debug.ps1` enables the
repeating trace only for its capture interval and disables it on exit; use
`-Passive` to observe without changing trace state.

The final `J=` byte reports the physical J10 input as `0PBBDLRU`: port
selection (`P`, 1 right/0 left), button 2, button 1, right, left, down, and up.
Contact bits are active high in this decoded field. With J10 idle after reset,
`J=40` is expected. Grounding J10 pin 1 changes it to `J=41`; F7 changes the
port bit and therefore an otherwise-idle value to `J=00`.

The two physical button contacts feed independent CoCo 3 PIA inputs. The PIA
matrix order is right Button 1, left Button 1, left Button 2, then right
Button 2. F7 moves both contacts to the selected joystick port; Button 2 is
never reported as Button 1 on the opposite port.

### Physical-floppy probe

The optional read-only J13 floppy build exposes its synchronized input state
and event counters with:

```text
FLOPPY
```

Example response:

```text
FLOPPY INDEX=0 TRACK0=1 READ=1 ACTIVE=0 HOME=0 DONE=0 OK=0 STEPS=00 DIR=1 SIDE=1 INDEX_COUNT=00000003 READ_EDGES=000012A4
```

`INDEX` and `TRACK0` are decoded active-high states. `READ` is the synchronized
raw read-data level and `ACTIVE` reports drive select/motor state.
`INDEX_COUNT` counts active-low index pulses and
`READ_EDGES` counts both transitions of the read-data signal; both counters
saturate at `FFFFFFFF`. `FLOPPY START` enables only select and motor. An FPGA
watchdog forces them off after 10 seconds even if firmware stalls, while
`FLOPPY STOP` turns them off immediately and aborts an active seek. Direction
and side are runtime levels selected by `FLOPPY DIR n` and `FLOPPY SIDE n`.
`FLOPPY STEP` produces one 20 us active-low STEP pulse only while START is
active. This allows cautious movement in either direction without another
bitstream build. `FLOPPY HOME` waits 500 ms for spin-up, uses the currently
selected DIR level, pulses STEP low for 20 us at 6 ms intervals, and stops on
TRACK0 or after 85 pulses. The FPGA, not firmware, enforces the step limit and
STOP path. All write signals remain absent.

The physical-floppy build also contains a hardware MFM track decoder and a
4,608-byte cache for the 18 decoded 256-byte sectors. For example, hexadecimal
track `11` is decimal track 17 and sector `03` is the first DECB directory
sector:

```text
FLOPPY READ 11 03
FLOPPY SECTOR T=11 S=03 DATA=50 52 4F 20 20 20 20 20 42 41 53 00 00 20 00 22 OK
```

The decoder requires valid ID and data CRCs. It retries one complete indexed
revolution before returning `ERR`.

### Physical drive as Disk BASIC drive 0

`FLOPPY MOUNT` advertises a read-only drive 0 and routes FDC read-sector
requests through the physical seek, capture, MFM decode, and sector cache.
Normal Disk BASIC commands then work without copying the full disk into RAM:

```text
FLOPPY MOUNT
```

At the CoCo prompt, use the ordinary commands:

```basic
DIR
RUN"PRO"
LOADM"PROGRAM"
EXEC
```

Writes deliberately fail while the physical backend is mounted. Use
`FLOPPY UNMOUNT` to restore the normal SD-image drive-0 state. The tested TEAC
occasionally ignored the first inward STEP following a direction reversal, so
firmware implements inward seeks by re-homing and approaching the target in
the proven outward direction. This is slower but deterministic for read-only
media.

The hardware regression helper mounts the drive, injects an unshifted Disk
BASIC command, and rejects any `FDC ERR` response:

```powershell
.\scripts\test_physical_floppy_disk_basic.ps1 -Port COM5 -BasicCommand dir
.\scripts\test_physical_floppy_disk_basic.ps1 -Port COM5 -BasicCommand 'run"pro"'
```

### Raw physical-floppy flux capture

`FLUX` records falling-edge intervals from the active-low read-data signal.
Capture is index-aligned, clocked at exactly 25.2 MHz, and performed in FPGA
logic before transmission. This decouples timing-sensitive sampling from UART
latency. The FPGA stores up to 1024 16-bit intervals in one BRAM while also
counting and hashing the complete revolution. The hexadecimal argument is the
number of initial intervals to skip, allowing the host to reconstruct a long
track from index-aligned windows captured on successive revolutions.

The normal transfer form is:

```text
FLUX 0000
FLUX BEGIN CLK=25200000 SIDE=1 DIR=1 OFFSET=0000 TOTAL=B91C COUNT=0400 CYCLES=004CCC1A MIN=0025 MAX=012C HASH=090D7215
<COUNT little-endian uint16 interval values>
FLUX END CRC32=1BB4938B
```

`CLK` is decimal; all other numeric response fields are hexadecimal. Each
interval is a count of 25.2 MHz capture clocks. The CRC-32 covers only the
binary payload, using the reflected polynomial `0xEDB88320`, initial value
`0xFFFFFFFF`, and final XOR `0xFFFFFFFF`.

The UART remains at 460800 throughout the request. Flux capture is still
buffered because this link rate is not fast enough to carry every live
read-data edge without loss.

Use the host tool to capture all windows, validate every CRC, and write raw,
forward, reverse, and metadata files:

```powershell
.\scripts\capture_physical_floppy_flux.ps1 -Port COM5 -Side 1 -Direction 1 -Name track00-side1
```

The `.flux16le` file contains little-endian 16-bit clock intervals. The two
CSV files contain the same sequence in temporal and reversed temporal order,
which is useful when comparing media read from the opposite head after it is
physically flipped. The JSON sidecar records capture settings and every
index-aligned chunk. Because the BRAM holds 1024 intervals, a reconstructed
track combines matching offsets from successive revolutions; it is intended
for diagnostics and decoder development, not archival imaging.

`FLUX TRACK` is the preferred whole-track command. It waits for an index edge,
captures one uninterrupted index-to-index revolution, and stops at the next
index edge. `FLUX BULK` is the fallback for physically flipped media whose
index aperture is no longer visible; it captures a timed 205 ms window instead.

```text
FLUX TRACK
FLUX BULK BEGIN CLK=25200000 SCALE=2 INDEXED=1 SIDE=1 DIR=0 COUNT=B91D CYCLES=004CCF20 MIN=0024 MAX=0138 HASH=81234567
<COUNT unsigned-byte interval values>
FLUX BULK END CRC32=89ABCDEF
```

Each payload byte represents an interval in `SCALE` capture clocks. The FPGA
stores at most 48 KiB, which is enough for one nominal 300 RPM DD track. This
is a one-track timing buffer, not a disk-image cache: buffering is required
because even 460800-baud UART cannot accept live flux transitions without
pauses. The optional physical-floppy build retains this full track buffer.
Serial video-frame capture uses a small distributed-RAM stripe buffer, allowing
flux capture and full-resolution screenshots to coexist without additional
BRAM.

The disk-capture host tool homes once, steps at runtime, rejects tracks with
fewer than 1000 intervals as disconnected-head noise, validates every UART
payload CRC, retries a failed transfer without stepping, writes one native file
per track, and assembles a standard multi-revolution SCP image. Indexed capture
is the default:

```powershell
.\scripts\capture_physical_floppy_disk.ps1 -Port COM5 `
  -LastTrack 34 -PhysicalSide 1 -LogicalHead 0 `
  -RevolutionsPerTrack 1 -CaptureRetries 2 `
  -MotorSpinupMs 3000 -HeadLoadSettleMs 250 `
  -AllowUnstableTrackZero -Name coco-disk
```

Add `-Indexless` only for flipped media that cannot expose index:

```powershell
.\scripts\capture_physical_floppy_disk.ps1 -Port COM5 `
  -LastTrack 34 -PhysicalSide 1 -LogicalHead 0 -Indexless `
  -MotorSpinupMs 3000 -HeadLoadSettleMs 500 `
  -AllowUnstableTrackZero -Name flipped-disk
```

Greaseweazle can reverse a flipped track while converting the SCP image:

```powershell
C:\develop\greaseweazle-1.23\gw.exe convert --format coco.decb `
  --reverse .\build\test-output\floppy-disks\flipped-disk\flipped-disk.scp `
  .\build\test-output\floppy-disks\flipped-disk\flipped-disk.dsk
```

This is the failed-head recovery path: select the working physical head, flip
the disk if necessary, capture without index, and reverse during conversion.
It cannot compensate for a head that produces no flux transitions or for poor
head/media contact. `-AllowUnstableTrackZero` is intentionally opt-in: it uses
the FPGA's latched HOME result when an old drive's live TRACK0 sensor chatters,
while the default path still requires TRACK0 to remain asserted.
`-HeadLoadSettleMs` delays capture after each watchdog refresh because
`FLOPPY START` briefly cycles drive-select; older mechanisms may unload and
reload the head during that refresh.

For example, the following changes direction and issues exactly one step:

```powershell
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyStart
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyDirection -FloppyValue 0
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyStep -FloppySteps 1
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command Floppy
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyStop
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyRead -FloppyTrack 17 -FloppySector 3
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyMount
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FloppyUnmount
```

The Adafruit FeatherWing exposes the Shugart Select1 signal only. Selecting a
mechanism configured as DS0 versus DS1 therefore remains a drive-jumper/cable
choice; it cannot be switched through this API.

The status reply also includes `HOME`, completion-toggle `DONE`, result `OK`,
and hexadecimal `STEPS` fields. Run the guarded seek test with:

```powershell
.\scripts\test_physical_floppy_home.ps1 -Port COM5
```

A normal bitstream built without the optional J13 floppy interface replies:

```text
FLOPPY DISABLED
```

Run a guarded motor/select test from the Windows host with:

```powershell
.\scripts\test_physical_floppy_motor.ps1 -Port COM5 -RunSeconds 6
```

The script always attempts `FLOPPY STOP` in its cleanup path. The independent
FPGA watchdog remains the final safety limit if the host or firmware stops.

### Reset the browser to `/`

Request:

```text
ROOT
```

Successful response:

```text
OK ROOT
```

If no SD card is currently online:

```text
ERR NO SD
```

`ROOT` changes only the management browser's current directory. It does not
open the OSD, mount a disk, unmount a disk, or reset the CoCo. A typical test
sends `ROOT`, pulses F12, and then navigates from a deterministic location.

### Release injected input

Request:

```text
RELEASE
```

Response:

```text
OK RELEASE
```

This clears all 56 matrix-key bits, forced Shift, Shift override, and all eight
function-key slots. Test programs should send `RELEASE` during cleanup even
after a failure so a held key cannot affect the next test.

### Cold reset

Request:

```text
RESET
```

Immediate response:

```text
OK RESET
```

The command releases injected input and pulses the CoCo cold-reset request. It
does not reset the RV32 management processor or intentionally discard its SD
filesystem and disk-cache state. The passive trace normally emits `COCO3 UART
READY` after the emulated machine resets.

## Keyboard injection

`KD` presses one CoCo keyboard-matrix key and `KU` releases it. The argument is
an exactly two-digit hexadecimal index from `00` through `37` (decimal 0-55).
Key states persist until explicitly released, reset, or cleared by `RELEASE`.

Example of pressing and releasing Enter:

```text
KD 30
OK KEY
KU 30
OK KEY
```

### Matrix-key indices

| Hex range | Keys in index order |
| --- | --- |
| `00`-`07` | `@ A B C D E F G` |
| `08`-`0F` | `H I J K L M N O` |
| `10`-`17` | `P Q R S T U V W` |
| `18`-`1F` | `X Y Z Up Down Left/Backspace Right Space` |
| `20`-`27` | `0 1 2 3 4 5 6 7` |
| `28`-`2F` | `8 9 : ; , - . /` |
| `30`-`37` | `Enter Tab Esc Alt Ctrl F1 F2 Shift` |

The arrow, Space, and Ctrl indices are also used by the selectable keyboard to
joystick mapping. For example, after F8 selects right-joystick mapping, `KD 1F`
presses its fire button and `KD 1D` moves it left.

### Shift controls

Forced Shift is independent of matrix key `37`:

```text
SH 1
OK SHIFT
SH 0
OK SHIFT
```

Shift override suppresses matrix key `37`; it is used for CoCo character
combinations that require another modifier without Shift:

```text
SO 1
OK SHIFT
SO 0
OK SHIFT
```

Forced Shift still takes precedence while Shift override is enabled. For normal
text entry, use `SH 1` around a shifted key and return it to `SH 0` afterward.

## Function-key injection

The `FK` argument packs a function-key slot and its desired state into one
byte:

```text
value = (slot << 1) | pressed
```

`pressed` is 1 for key-down and 0 for key-up. The request contains exactly two
hex digits. For example, F12 is slot 7:

```text
FK 0F
OK FUNCTION
FK 0E
OK FUNCTION
```

| Slot | Nominal key | Down | Up | Current FPGA use |
| ---: | --- | --- | --- | --- |
| 0 | F3 | `FK 01` | `FK 00` | Accepted; no current serial consumer. |
| 1 | F6 | `FK 03` | `FK 02` | CPU normal/fast mode control. |
| 2 | F7 | `FK 05` | `FK 04` | Toggle physical J10 joystick between right and left CoCo ports. |
| 3 | F8 | `FK 07` | `FK 06` | Cycle keyboard joystick mapping. |
| 4 | F9 | `FK 09` | `FK 08` | Scanline option. |
| 5 | F10 | `FK 0B` | `FK 0A` | Current F10 function. |
| 6 | F11 | `FK 0D` | `FK 0C` | Open Settings OSD. |
| 7 | F12 | `FK 0F` | `FK 0E` | Open or close management browser. |

Always send both edges. Leaving a function slot pressed prevents a later pulse
from producing a new rising edge.

## Full-frame capture

Request:

```text
CAPTURE
```

Wire response:

```text
FRAME BEGIN 640 480 RGB332 307200\r\n
<exactly 307200 binary bytes>
\r\nFRAME END CRC32 XXXXXXXX\r\n
```

The payload is one byte per pixel, left-to-right and top-to-bottom. RGB332 uses
bits `RRRGGGBB`. The CRC is standard reflected CRC-32 with polynomial
`0xEDB88320`, initial value `0xFFFFFFFF`, and final XOR `0xFFFFFFFF`. It covers
only the 307200 payload bytes, not the header, separator, or trailer.

The host must switch from line parsing to an exact-length binary read after the
header. Do not decode the payload as text and do not search it for newline
characters. After reading the advertised byte count, consume the separator and
match the `FRAME END CRC32` line.

If a capture stripe does not complete, firmware emits:

```text
FRAME ERROR TIMEOUT
```

The host should abandon that capture. See [VIDEO_FRAME_CAPTURE.md](VIDEO_FRAME_CAPTURE.md)
for PNG conversion and reference-image comparison.

## Errors

| Response | Meaning |
| --- | --- |
| `ERR COMMAND` | Unknown command or invalid command syntax/value. |
| `ERR LONG` | Request exceeded the command buffer. Discard input through the next line terminator before retrying. |
| `ERR NO SD` | `ROOT` was requested without an online SD card. |
| `FRAME ERROR TIMEOUT` | Video capture hardware did not complete a stripe. |

Malformed or out-of-range `KD`, `KU`, `SH`, `SO`, and `FK` requests normally return
`ERR COMMAND`. Error responses do not guarantee that earlier persistent key
state was cleared; use `RELEASE` when recovering.

## Asynchronous output

The same TX line carries events and diagnostic telemetry that are not direct
responses. Host software should record these lines but continue waiting for the
specific response to its request.

### Management events

Current firmware can emit:

```text
RV32 SD MOUNT
SD READY - F12
SD OFFLINE
SD REINSERTED - F12
MOUNT ERR XX
MENU OPEN
MENU CLOSE
SETUP OPEN
SETUP CLOSE
MOUNT D0 filename CRC32 XXXXXXXX
CARTRIDGE LOADED filename
BIN READY filename EXEC XXXX
BIN STARTED
BIN LOAD CANCELLED
FDC CACHE dd tt ss cc BUF bb bb bb bb
FDC ERR dd tt ss cc
FDC CPU bb bb bb bb
FDC WRITE OK dd tt ss
FDC WRITE ERR dd tt ss
```

Filenames are variable-length text. Numeric values are hexadecimal. These lines
are useful for tests but are diagnostic interfaces rather than command replies.

### Passive CoCo trace

The FPGA trace unit can emit these event lines:

```text
COCO3 UART READY
CART ON
CART ENTRY C000
```

It also emits approximately one status line per second:

```text
PC=pppp K=k R=rr C=cc S=ss T=tt V=<40 hex> G=<5 hex> M=<32 hex> D=<8 hex> Q=<8 hex> J=<2 hex>
```

The fields are:

- `PC`: sampled 6809 architectural program counter.
- `K`: 1 when a physical PS/2 keyboard key is active; serial injection is not
  included in this particular indicator.
- `R`, `C`: last PIA keyboard row read and column value written.
- `S`: SD status. Bits 7-4 are `1010`, bit 3 is manager-ready, and bits 2-0
  indicate drives 2-0 present.
- `T`: `01` while a cartridge session is enabled, otherwise `00`.
- `V`: 20 bytes: video mode, video resolution, high start-address bits,
  16-bit video offset, horizontal offset, 12 packed palette bytes, and the
  current two-byte video data sample.
- `G`: INIT0, INIT1, then one flags nibble. Flag bits 2-0 are MMU enable, MMU
  task, and all-RAM mode.
- `M`: the sixteen MMU mapping registers in order.
- `D`: SDRAM diagnostics as four bytes: dropped writes, write-FIFO high-water
  mark, maximum refresh debt, and current refresh debt.
- `Q`: completed-frame upper-SDRAM cache misses and last fetch position.
- `J`: decoded J10 port selection and six active-high joystick contacts as
  `0PBBDLRU`.

These periodic lines are deliberately low-rate snapshots. They are intended to
identify hangs, video configuration, MMU state, and memory-controller pressure;
they are not cycle-accurate tracing.

## Host examples

The generic PowerShell client wraps the text commands:

```powershell
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command Ping
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command Status
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command BrowserRoot
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command FunctionKey -Function 12
.\scripts\coco3_serial_test.ps1 -Port COM5 -Command TypeText -Text 'DIR'
```

Capture and convert a frame:

```powershell
.\scripts\capture_video_serial.ps1 -Port COM5 -Name current-screen
```

End-to-end examples that combine `ROOT`, keyboard injection, status checks, and
frame capture are in:

- `scripts/test_zenix_serial.ps1`
- `scripts/test_astro_serial.ps1`

Only one host process should open the COM port at a time. Each automated test
should close the port in a `finally` block and attempt `RELEASE` before closing.
