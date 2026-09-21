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
- Configuration: 115200 baud, 8 data bits, no parity, one stop bit (`8N1`).
- Flow control: none.
- Requests: case-sensitive ASCII command lines terminated by CR, LF, or CRLF.
- Normal responses: ASCII lines terminated by CRLF.
- Maximum request length: 63 characters, excluding the line terminator.
- Hexadecimal request values accept upper- or lower-case digits. Responses use
  upper-case hexadecimal.

The receive path belongs to the RV32 management firmware. The transmit pin is
shared by management responses and the passive CoCo diagnostic trace. A host
must therefore ignore unrelated lines while waiting for the expected response.
Match complete prefixes such as `PONG`, `OK KEY`, or `STATUS PC=` instead of
assuming that the next received line is the reply.

`CAPTURE` is the exception: the manager claims the transmit pin for the entire
binary transfer so diagnostic text cannot be inserted into the frame payload.

## Command summary

| Request | Successful response | Purpose |
| --- | --- | --- |
| `PING` | `PONG` | Check that the management processor is responsive. |
| `STATUS` | `STATUS PC=.... I0=.. I1=.. VM=.. VR=..` | Read a compact CPU and GIME status snapshot. |
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
| 2 | F7 | `FK 05` | `FK 04` | Accepted; no current serial consumer. |
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
PC=pppp K=k R=rr C=cc S=ss T=tt V=<40 hex> G=<5 hex> M=<32 hex> D=<8 hex>
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
