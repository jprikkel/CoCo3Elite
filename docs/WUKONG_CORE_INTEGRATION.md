# Wukong CoCo3 core integration plan

## Goal

Advance from the verified standalone HDMI pattern to a reproducible CoCo 3
boot screen while keeping the known-good 640x480 TMDS transmitter available as
a fallback. The first core milestone intentionally excludes disk, SD, audio,
joysticks, serial ports, and DDR3.

## Wukong peripheral direction

The Wukong port will use locally attached hardware and will not implement
DriveWire. Disk-image storage will use the board's onboard Micro SD slot rather
than a serial connection to a host computer. The onboard CH340N USB-to-UART
bridge is not part of the storage design; it may remain unused or be enabled
later as an optional diagnostic console or RS-232 PAK connection.

After the real-ROM boot milestone, add hardware interfaces in this order:

1. PS/2 keyboard through PMOD J14, using the existing PS/2 receiver and CoCo
   keyboard-matrix translation logic.
2. Direct Micro SD storage through the existing SPI controller, adapted to the
   Wukong slot and verified without DriveWire dependencies.
3. Audio through a PMOD I2S DAC or a small external audio interface.
4. CoCo joystick inputs through an external ADC connected to a PMOD header.
5. An optional DS3231-compatible real-time clock over I2C.
6. External SDRAM or DDR3 only for expanded-memory configurations that exceed
   the practical block-RAM capacity.
7. Optional RS-232 PAK support, kept independent of storage and DriveWire.

Ethernet and Wi-Fi are not initial port milestones. A USB keyboard is also not
an initial target because the board's Mini-USB connector is a CH340N UART
device, not a USB host; native PS/2 is the supported keyboard path.

## Legacy design findings

### Top level and CPU

The legacy system is rooted at `rtl/coco3fpga_dw.v`. It directly instantiates
the 6809-compatible `cpu09l_128` core and includes register/peripheral logic
from `CoCo3IO.v` and `sound.v`. The CPU bus exposed internally is:

- `ADDRESS[15:0]`, `DATA_IN[7:0]`, and `DATA_OUT[7:0]`
- `RW_N`, `VMA`, `PH_2`, reset, IRQ, FIRQ, NMI, and HALT

The module is not a portable board-independent core today. Board pins, SRAM
arbitration, flash decoding, video, audio, storage, and peripherals are all in
one top level.

### Clocks and reset

The original design receives 50, 24, 27, and 3.57 MHz board clocks. Its main
counter divides 50 MHz and supplies a 25 MHz video clock. A state machine also
derives `PH_2_RAW`; the Altera `cycloneii_clkctrl` wrapper `PH2_CLK` promotes it
to a global clock. Reset is stretched using a divided 50 MHz clock.

For Wukong, the 50 MHz oscillator is sufficient for the initial core. The
existing HDMI MMCM already creates 25 MHz and 125 MHz. The portable core should
receive a synchronous clock-enable for CPU cycles rather than create a fabric
clock and then pass it through an Altera clock-control primitive. Reset release
must be synchronized in every active clock domain.

### Memory and ROM

The legacy machine uses an external 16-bit asynchronous SRAM as a shared 2 MiB
CPU/video memory. A 50 MHz state machine interleaves byte-wide CPU accesses and
16-bit video fetches. System and cartridge ROM normally come from external
flash. Addresses `$FFF0-$FFFF` are shadowed in the writable `FFF0` Altera RAM,
initialized by `legacy-quartus/FFF0.mif`.

The Wukong XC7A100T has 4,860 Kbit (about 607 KiB) of block RAM, so it cannot
hold the legacy design's complete 2 MiB machine memory. First diagnostic boot
should nevertheless use a reduced inferred true dual-port block RAM, sized to
leave room for ROM and the rest of the design:

- Port A: byte-wide CPU access
- Port B: 16-bit video access
- Depth: configurable, initially 128 or 256 KiB
- Read latency: explicitly registered and reflected in both clients

Using reduced BRAM avoids a DDR3 controller, calibration, arbitration, and
unrelated clock-domain crossings during the first CPU/video bring-up. A full
512 KiB configuration would consume almost all device BRAM, while the complete
2 MiB configuration requires the board's DDR3. The DDR3 controller and a
deterministic CPU/video cache or arbitration layer are therefore required
before declaring the full memory port complete.

`FFF0.mif` contains vector-shadow data, not a complete CoCo 3 system ROM.
No complete system ROM image is present in this repository. A legal, user-
supplied ROM image and its exact byte layout are therefore prerequisites for a
real boot. ROM data should be loaded into inferred ROM/BRAM from a `.mem` file
that is excluded from Git. Do not commit copyrighted ROM bytes.

### Video

`rtl/coco3vid.v` defines `COCO3VIDEO`. It runs from 25 MHz, produces 9-bit
palette/index data plus HSYNC, VSYNC, horizontal blanking, and vertical
blanking, and consumes 16-bit words from shared RAM. It also instantiates the
Altera `COCO3GEN` character ROM initialized by
`legacy-quartus/coco3gen.mif`.

The legacy top level converts `COLOR[8:0]` and the GIME palette registers into
12-bit RGB. This conversion should move into the portable core boundary so the
Wukong wrapper receives RGB, sync, and blanking signals rather than internal
palette state.

The legacy raster timing should remain authoritative for CoCo video. Do not
feed its pixels into the independent `video_timing.v` raster, because two
unrelated timing generators would drift. Instead, adapt the legacy RGB,
HSYNC/VSYNC, and blanking directly to the proven TMDS encoders. The existing
test pattern remains selectable at build time for hardware diagnosis.

## Portability work required

Create these new portable components under `rtl/core/`:

1. `coco3_core.v` -- board-neutral integration boundary exposing RGB, sync,
   blanking, keyboard inputs, and simple optional peripheral interfaces.
2. `coco3_memory.v` -- configurable inferred dual-port diagnostic BRAM with
   defined read latency.
3. `coco3_rom.v` -- inferred ROM initialized from a user-provided `.mem` file.
4. `coco3_char_rom.v` -- portable replacement for `COCO3GEN`, initialized from
   a converted copy of the existing character-generator data.
5. `coco3_clock_enable.v` -- CPU-cycle enables derived synchronously from the
   system clock, replacing `PH2_CLK`.

Keep the original files and all `legacy-quartus/` artifacts intact. Changes to
legacy logic should be small, reviewable extractions or conditionally selected
portable wrappers rather than an irreversible rewrite.

## Incremental implementation sequence

### Stage 1: video-core compile checkpoint

- Replace `COCO3GEN` with a portable inferred ROM.
- Instantiate `COCO3VIDEO` with fixed power-on GIME mode values and a small
  initialized screen buffer.
- Convert its legacy color output to 8-bit-per-channel RGB.
- Send its own sync/blanking and RGB directly through the existing TMDS
  encoder/serializer.
- Add a Tcl build argument that selects `TEST_PATTERN` or `COCO_VIDEO`.

Acceptance: Vivado builds with no Altera primitives, timing and DRC pass, and a
stable synthetic CoCo text-mode screen is visible over HDMI.

Implementation status: the portable character ROM, synthetic video memory,
legacy video adapter, and `COCO_VIDEO` build selector are implemented. Vivado
2025.2 passes synthesis, implementation, timing, DRC, and bitstream generation.
Physical display acceptance passed on 2026-08-23 with correct 80-column text,
palette colors, and stable HDMI output. Stage 1 is complete.

### Stage 2: CPU and internal RAM checkpoint

- Add `cpu09l_128` and the minimum GIME/SAM/PIA register logic.
- Replace the external SRAM state machine with inferred dual-port BRAM.
- Hold optional peripheral selects inactive and return defined idle data.
- Add simulation tests for reset-vector fetch, RAM byte lanes, ROM/RAM decode,
  and simultaneous CPU/video access.

Acceptance: simulation shows the CPU reading the reset vector and executing a
small repository-owned diagnostic ROM that writes recognizable characters or
color data into video RAM; hardware displays that result.

Implementation status: `CPU_DIAGNOSTIC` integrates the `cpu09` core, a 128 KiB
dual-port BRAM built from two byte-wide banks, and a repository-owned reset ROM.
The mixed-language Vivado simulation passes reset-vector fetch, CPU execution,
both RAM byte lanes, and video-port visibility. Vivado 2025.2 also passes full
synthesis, implementation, timing, DRC, and bitstream generation. Physical
display acceptance passed on 2026-08-23 with all three expected CPU-generated
messages. Stage 2 is complete.

### Stage 3: real ROM boot checkpoint

- Add an ignored path such as `roms/coco3.rom` and a conversion/validation
  script that emits `build/roms/coco3.mem`.
- Require an expected size and optionally a user-configured checksum before
  building.
- Load the image into the portable ROM without adding it to source control.
- Enable the keyboard matrix only after the boot screen is stable.

Acceptance: the physical board reaches the CoCo 3 startup screen repeatedly
after power-on and reset, with stable HDMI and working keyboard input.

Implementation status: the repository now provides an ignored
`roms/coco3.rom` input and `scripts/prepare_coco3_rom.ps1`, which validates an
exact 32 KiB image, optionally enforces its SHA-256 digest, checks that the
reset vector points into ROM, and emits `build/roms/coco3.mem`. No copyrighted
ROM data is stored in Git. `coco3_system_rom.v` provides the inferred block-ROM
reader and `test_system_rom.ps1` verifies the reconstructed reset vector and
reset target. Real-boot memory decode and minimum GIME/SAM/PIA integration
remain to be implemented.

The base 128 KiB CoCo 3 does not require DDR3. DDR3 is reserved for a later
expanded-memory configuration.

### Stage 4: peripherals

Add one subsystem per checkpoint in the following order:

1. PS/2 keyboard through PMOD J14.
2. Direct storage using the onboard Micro SD slot and SPI.
3. Audio using an external PMOD-compatible interface.
4. Joysticks using an external ADC.
5. Optional I2C RTC and RS-232 PAK interfaces.
6. Optional external-memory support for configurations larger than BRAM can
   accommodate.

DriveWire is explicitly out of scope. Replace `disk02`, FIFOs, and other
Altera-generated blocks only when required by one of the selected local
subsystems. Preserve the original source files for reference even when their
DriveWire paths are not ported.

Acceptance for each peripheral checkpoint requires a focused simulation,
successful implementation and timing, and a physical-board test before the
next peripheral is enabled.

## Verification requirements

- Preserve the last known-good test-pattern build mode.
- Add an RTL testbench under `tb/` before enabling the CPU in hardware.
- Fail the build with a clear message when the selected ROM file is absent.
- Report unconstrained paths, CDC issues, inferred latches, and multi-driven
  nets as build failures where practical.
- Run synthesis, implementation, timing, DRC, and bitstream generation after
  every hardware milestone.

## Immediate next change

Validate a user-supplied CoCo 3 system ROM, then implement the smallest
`COCO3_BOOT` system boundary that preserves its reset memory map and required
power-on GIME/SAM/PIA behavior. Keep all three verified fallback images
selectable while adding simulation coverage before generating hardware.
