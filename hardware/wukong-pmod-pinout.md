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
pin 3 (`T24`) for clock. See [PS/2 keyboard wiring](pmod-keyboard-ps2-interface.md) for voltage translation
and wiring requirements.

J13 is assigned to the external Digilent Pmod MicroSD: pin 1 chip select,
pin 2 MOSI, pin 3 MISO, and pin 4 SPI clock. The current MicroSD path supports
initialization and sector-zero reads only; FAT32 DSK mounting is not implemented.

J10 is assigned to one direct Atari/C64-style digital joystick:

| J10 pin | FPGA pin | Function |
| ---: | --- | --- |
| 1 | D5 | Up, active low |
| 2 | G5 | Down, active low |
| 3 | G7 | Left, active low |
| 4 | G8 | Right, active low |
| 7 | E5 | Button 1, active low |
| 8 | E6 | Button 2, active low |
| 9 | D6 | Reserved |
| 10 | G6 | Reserved |

J10 defaults to the right CoCo joystick port. F7 moves the complete physical
joystick, including both genuine CoCo 3 button inputs, between the right and
left CoCo ports. Button 2 does not consume the other port's Button 1 input.

See the [digital joystick interface](pmod-atari-joystick-digital-interface.md)
for the DE-9 pinout and electrical restrictions. The earlier MAX3421E USB
proposal must move to another connector or use a future shared adapter; it is
not compatible with the active J10 assignment.
