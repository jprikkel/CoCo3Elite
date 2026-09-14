# Cartridge hardware and peripheral support

Status: design proposal. The current SD-loaded cartridge implements ROM and
CART/FIRQ behavior only. Disk-controller registers are implemented separately
by the existing internal FDC path.

## Scope

Some cartridge files represent more than ROM. The original cartridge may have
contained registers, RAM, a sound generator, a disk controller, communications
hardware, bank-selection logic, or circuitry that drives CART, NMI, and HALT.
Making the ROM bytes visible is not enough to emulate those products.

This document covers FPGA models of that hardware. A physical cartridge-slot
adapter is a separate electrical project, although both should eventually use
the same logical cartridge-bus interface.

## Relevant CoCo cartridge signals

The logical interface must represent:

| Signal | Function |
| --- | --- |
| CTS | Selects the cartridge ROM space |
| SCS | Selects cartridge I/O at `$FF40-$FF5F` |
| CART | Cartridge interrupt input through PIA/GIME behavior |
| NMI | Direct non-maskable CPU interrupt |
| HALT | Stops the 6809 so external hardware can own the bus |
| SLENB | Suppresses internal device selection for expansion hardware |
| E and Q | CPU bus phase and peripheral timing reference |
| SND | Analog cartridge audio contribution on physical hardware |

The [Tandy CoCo 3 Service Manual][service-manual] is the primary reference for
these connector signals. The FPGA implementation should expose equivalent
qualified digital signals internally rather than copying board voltage levels.

## Proposed cartridge-peripheral bus

Add a project-owned bus between `coco3_boot_machine` and selectable cartridge
devices:

```text
MC6809 bus qualification
        |
        +--> standard ROM mapper
        +--> banked ROM mapper
        +--> GMC sound device
        +--> future Orchestra-90/device profile
        +--> future physical-slot bridge
```

Only the selected profile may drive read data or control lines. The top-level
arbiter combines device outputs and reports contention as a simulation error.

Each device receives qualified read/write strobes so a multi-clock CPU cycle
cannot perform the same register side effect more than once. Device reset must
distinguish FPGA configuration, CoCo cold reset, and Ctrl+Alt+Delete where the
real hardware does so.

## Game Master Cartridge sound

GMC support is the highest-priority cartridge peripheral currently identified.
It requires:

1. Decode of the GMC write-only sound register at `$FF41` through SCS.
2. A compatible SN76489-family programmable sound generator.
3. A documented PSG clock and divider matching the cartridge hardware.
4. Signed PCM output mixed with the existing CoCo DAC before HDMI audio packet
   generation.
5. Saturation or sufficient headroom so simultaneous CoCo and cartridge audio
   cannot wrap.
6. Reset and cartridge-presence behavior matching a power-cycled cartridge.

Candidate open implementations for evaluation are:

- [rejunity/tt05-psg-sn76489][tt05-psg], a Verilog implementation with an
  Apache-2.0 license and cocotb tests.
- [dnotq/sn76489_audio][sn76489-audio], a BSD-3-Clause VHDL implementation with
  FPGA use and optional original-style write timing.

Select a core only after comparing noise-LFSR behavior, attenuation table,
clocking, write timing, reset state, output width, test coverage, and license
integration. Keep imported source under `rtl/third-party/`; put CoCo/GMC decode,
clock adaptation, and audio mixing in project-owned RTL.

## Other cartridge classes

### Sound and speech cartridges

These require a profile for their register decode and an audio path. ROM-only
fallback should be marked incomplete rather than reported as working.

### Disk-controller cartridges

The current project already maps Disk BASIC ROM and WD1773-like registers for
the internal virtual drives. A future cartridge framework must not create a
second driver on `$FF40-$FF5F`. Select either the internal FDC profile or a
different cartridge peripheral, or define explicit Multi-Pak behavior.

### RAM and communications cartridges

These require device-owned writable storage and exact read/write side effects.
Serial, network, printer, or DriveWire-style devices also need buffering and
clock-domain isolation from the RV32 manager.

### Multi-Pak Interface

MPI support is not equivalent to a larger ROM. It multiplexes CTS/SCS and
control lines among slots and introduces slot-selection state. Implement it
only after the single-device cartridge bus is stable.

## Firmware metadata and UI

The F12 browser should distinguish:

- `[CCC]` for known linear ROM images.
- `[MAP]` for a banked ROM with a supported mapper sidecar.
- `[HW ]` for a cartridge profile requiring emulated hardware.

Metadata should name a fixed profile such as `gmc-sn76489`; removable media
must not provide arbitrary RTL register equations. Firmware verifies image
size, mapper/peripheral compatibility, and required FPGA capability before
requesting a cold launch.

If a file requires unsupported hardware, show `CARTRIDGE HARDWARE NOT
SUPPORTED` and leave the current CoCo state unchanged.

## Physical cartridge connection

A real cartridge port cannot be connected directly to a 3.3 V PMOD header.
Before any adapter is designed, determine:

- Required 5 V and 3.3 V level translation in both directions.
- Bus direction and output-enable timing.
- CART, NMI, HALT, RESET, CTS, SCS, SLENB, E, and Q electrical behavior.
- Current available from the external supply.
- Connector pin count; a normal PMOD does not provide enough signals for a
  complete parallel cartridge bus without serialization or an interposer CPLD.
- Protection against insertion while powered.

The recommended first hardware work remains the previously planned physical
floppy interface, because it has a narrower Shugart-style signal set. A real
cartridge adapter should be a purpose-built level-shifting board, not loose
PMOD wiring.

## Test strategy

1. Add a generic cartridge-bus testbench with read-data contention assertions.
2. Verify one SCS write produces exactly one peripheral write pulse.
3. Test CART, NMI, and HALT independently and during reset.
4. For GMC, verify tone periods, noise sequence, attenuation, silence, reset,
   and mixed-audio saturation.
5. Run normal and fast CoCo clocks and confirm the peripheral clock does not
   accidentally follow the F6 turbo override unless hardware requires it.
6. Test replacement of a hardware profile with a normal ROM and vice versa.
7. Confirm SD removal does not leave a partially configured device active.
8. Hardware-test with source-available software or user-supplied images; do not
   commit copyrighted cartridge ROMs.

## Acceptance criteria

- Existing linear cartridges, DSK access, keyboard, joystick, reset, and HDMI
  audio remain unchanged.
- Unsupported hardware is rejected explicitly.
- The selected device alone owns its SCS and ROM responses.
- Cartridge interrupts and HALT cannot persist after removal or soft reset.
- Audio remains correctly clocked and free of overflow or DC offsets.
- Resource and timing reports are recorded for each integrated hardware core.

## Relevant implementation files

- [`rtl/core/coco3_boot_machine.v`](../rtl/core/coco3_boot_machine.v)
- [`rtl/core/coco3_sd_cartridge.v`](../rtl/core/coco3_sd_cartridge.v)
- [`rtl/core/coco3_fdc.v`](../rtl/core/coco3_fdc.v)
- [`rtl/wukong/coco3_boot_system.v`](../rtl/wukong/coco3_boot_system.v)
- [`rtl/wukong/wukong_top.v`](../rtl/wukong/wukong_top.v)
- [`firmware/management/rv32_sd_mount.c`](../firmware/management/rv32_sd_mount.c)

[service-manual]: https://colorcomputerarchive.com/coco/Documents/Manuals/Hardware/Color%20Computer%203%20Service%20Manual%20%28Tandy%29.pdf
[tt05-psg]: https://github.com/rejunity/tt05-psg-sn76489
[sn76489-audio]: https://github.com/dnotq/sn76489_audio
