# Physical floppy PMOD interposer proposal

This is the first hardware-design step for the Shugart floppy backlog. It is a
proposal for a custom cable/interposer between Wukong PMOD connectors and the
[Adafruit Floppy FeatherWing, Product 5679](https://www.adafruit.com/product/5679).
It is not an approved wiring diagram and must be checked against the actual
Wing schematic and the selected floppy drive before fabrication.

## Electrical boundary

The Wukong FPGA pins are 3.3 V LVCMOS and PMOD power is 3.3 V. The FeatherWing
provides the drive-side 5 V level translation; do not bypass it. The floppy
mechanism needs its own regulated supply, normally 5 V with approximately 2 A
available for motor startup. Some 5.25-inch drives additionally require 12 V.
Tie signal ground between the Wukong, adapter, and drive, but do not use PMOD
power for the drive motor.

The Wing's write-disable control remains asserted during initial bring-up. A
second hardware write-inhibit control on the interposer is recommended so an
FPGA reset or pin-configuration error cannot energize `WRITE GATE`.

## Proposed Wukong signal allocation

J13 remains the MicroSD connector and J14 remains PS/2. J10 and J11 are used
only by the physical-floppy prototype. The labels below are logical signals;
the final FPGA constraints must use these package pins and explicitly set
I/O standards, pull states, and safe reset values.

| Connector pin | FPGA pin | Direction | Floppy signal | Initial use |
| --- | --- | --- | --- | --- |
| J10-1 | D5 | FPGA to drive | `DS0_N` | Select the single physical drive |
| J10-2 | G5 | FPGA to drive | `MOTOR_N` | Motor control |
| J10-3 | G7 | FPGA to drive | `DIR_N` | Head-step direction |
| J10-4 | G8 | FPGA to drive | `STEP_N` | Head-step pulse |
| J10-7 | E5 | FPGA to drive | `SIDE1_N` | Head select |
| J10-8 | E6 | FPGA to drive | `WRITE_GATE_N` | Held inactive until write milestone |
| J10-9 | D6 | FPGA to drive | `WRITE_DATA_N` | Reserved for guarded writes |
| J10-10 | G6 | FPGA to adapter | `PHYS_RESET_N` | Adapter reset or write-inhibit control |
| J11-1 | H4 | Drive to FPGA | `INDEX_N` | Rotation/index timing |
| J11-2 | F4 | Drive to FPGA | `TRACK0_N` | Head reference |
| J11-3 | A4 | Drive to FPGA | `READ_DATA_N` | Raw flux-transition input |
| J11-4 | A5 | Drive to FPGA | `WRITE_PROTECT_N` | Media write protection |
| J11-7 | J4 | Drive to FPGA | `READY_N` | Optional; qualify per drive |
| J11-8 | G4 | Drive to FPGA | `DISK_CHANGE_N` | Optional; qualify per drive |
| J11-9 | B4 | FPGA to drive | `DS1_N` | Reserved for a future second drive |
| J11-10 | B5 | bidirectional | `AUX/FAULT` | Reserved; do not connect initially |

The exact active polarity and whether a signal is open-collector or
push-pull must be confirmed from the FeatherWing and drive documentation. The
interposer must not place two push-pull outputs against each other. Start with
one drive select only; leave `DS1_N` and `AUX/FAULT` unconnected or protected.

## FPGA implementation boundary

The physical backend should share the existing FDC request/response contract:

```text
FDC request (drive, track, side, sector)
    -> physical controller: seek, select, wait index, capture raw data
    -> sector buffer and CRC/result
    -> FDC response or not-ready/CRC/timeout error
```

The raw `READ_DATA_N` input must be sampled with a dedicated capture clock or
a sufficiently oversampled clock. It must not be treated as a normal
synchronous byte input. The first implementation is read-only and should
expose index, transition count, decoded address/data marks, CRC, and timeout
status through the management serial diagnostics. FM/MFM decoding and sector
format details belong in the physical backend, not in the FAT32 firmware.

## Bring-up checklist

1. Confirm the Wing schematic, Feather header orientation, IDC pin numbering,
   drive connector keying, and the selected drive's power requirements.
2. Build and continuity-test the interposer with no floppy attached. Verify
   every FPGA output is inactive during configuration and reset.
3. Add an FPGA pin-constraint-only test that toggles no drive control and
   reports input states over UART.
4. Attach a powered 3.5-inch drive and qualify `INDEX`, `TRACK0`, `READY`, and
   `WRITE_PROTECT` without media writes.
5. Add head stepping and raw read capture, then compare decoded CoCo sectors
   against known-good ToolShed/emulator fixtures.
6. Enable writes only after the read path, reset recovery, and hardware
   write-inhibit behavior pass review.
