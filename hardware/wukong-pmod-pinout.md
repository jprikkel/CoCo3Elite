# Wukong V3 PMOD Pinout

## Scope

These tables transcribe Figure 2-8, "Extension IO," from the QMTECH Wukong V3
hardware manual in `docs/`. FPGA names are Artix-7 package-ball identifiers.
All four connectors use the standard 2x6 PMOD power arrangement:

- Pins 1-4 and 7-10 are FPGA signals.
- Pins 5 and 11 are ground.
- Pins 6 and 12 are 3.3 V.
- No PMOD connector pin supplies 5 V.

The diagram is a schematic pin view. Confirm the pin-1 marking on the physical
board before attaching a cable or module.

## J10 - Bank 35

| PMOD pin | FPGA pin | PMOD pin | FPGA pin |
| ---: | --- | ---: | --- |
| 1 | D5 | 7 | E5 |
| 2 | G5 | 8 | E6 |
| 3 | G7 | 9 | D6 |
| 4 | G8 | 10 | G6 |
| 5 | GND | 11 | GND |
| 6 | 3.3 V | 12 | 3.3 V |

## J11 - Bank 35

| PMOD pin | FPGA pin | PMOD pin | FPGA pin |
| ---: | --- | ---: | --- |
| 1 | H4 | 7 | J4 |
| 2 | F4 | 8 | G4 |
| 3 | A4 | 9 | B4 |
| 4 | A5 | 10 | B5 |
| 5 | GND | 11 | GND |
| 6 | 3.3 V | 12 | 3.3 V |

## J13 - Bank 14

| PMOD pin | FPGA pin | PMOD pin | FPGA pin |
| ---: | --- | ---: | --- |
| 1 | N22 | 7 | P20 |
| 2 | N21 | 8 | N23 |
| 3 | R20 | 9 | P21 |
| 4 | T22 | 10 | R21 |
| 5 | GND | 11 | GND |
| 6 | 3.3 V | 12 | 3.3 V |

## J14 - Bank 14

| PMOD pin | FPGA pin | PMOD pin | FPGA pin |
| ---: | --- | ---: | --- |
| 1 | P23 | 7 | N24 |
| 2 | R23 | 8 | P24 |
| 3 | T24 | 9 | R22 |
| 4 | T25 | 10 | T23 |
| 5 | GND | 11 | GND |
| 6 | 3.3 V | 12 | 3.3 V |

## Current assignments

The PS/2 keyboard uses the Digilent layout on J14: pin 1 (`P23`) for data and
pin 3 (`T24`) for clock. See [PS/2 keyboard wiring](keyboard-ps2.md) for voltage translation
and wiring requirements.

J13 is assigned to the external Digilent Pmod MicroSD: pin 1 chip select,
pin 2 MOSI, pin 3 MISO, and pin 4 SPI clock. The current MicroSD path supports
initialization and sector-zero reads only; FAT32 DSK mounting is not implemented.

Reserve connector assignments for audio, joysticks, and I2C only when those
interfaces are implemented. Record each allocation here to prevent pin
conflicts between hardware milestones.

J10 is proposed for a MAX3421E USB host adapter (SPI, INT, RES, VBUS enable,
and overcurrent). This allocation is not enabled in the current top level;
see [USB host wiring and FPGA prototype](usb-host-interface.md) before using it.
