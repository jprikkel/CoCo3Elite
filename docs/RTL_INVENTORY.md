# CoCo3Elite RTL inventory and Wukong port boundary

## Scope and method

This inventory covers the inherited CoCo3FPGA sources and the current
AMD/Xilinx Artix-7 Wukong port. It does not change functional RTL. Bare legacy
filenames in the tables refer to the locations listed below; they are not
assumed to be files at the repository root.

Current locations are:

- `rtl/third-party/coco3fpga/` — retained CoCo3FPGA behavioral RTL, including
  `coco3fpga_dw.v`, `coco3vid.v`, `cocokey.v`, `i2c.v`, `paddles.v`, and
  `sound.v`.
- `rtl/third-party/coco3fpga/legacy-quartus/` — retained Quartus wrappers,
  generated memories, FIFO/IP files, and project metadata.
- `rtl/third-party/CPU09/` — the active CPU09 source.
- `rtl/third-party/PS2_Key/`, `rtl/third-party/SPI/`, and
  `rtl/third-party/UART_6551/` — retained peripheral sources.

The active Wukong build uses the project-owned machine and peripheral modules
listed in the current build boundary at the end of this document.

Classification means:

- **KEEP**: portable behavioral RTL; use unchanged initially.
- **MODIFY**: portable behavior exists, but a later integration change is
  expected and must be checked against the original timing.
- **REPLACE**: generated/vendor-specific implementation needs a compatible
  Vivado implementation with the same interface and observable latency.
- **DEFER**: not needed for the first HDMI or BASIC-screen milestones.
- **DE1-ONLY**: board/project glue retained only as the reference design.

## Principal and historical machine RTL

Entries marked **DEFER**, **REPLACE**, or **DE1-ONLY** describe retained
historical sources. They are not part of the active Wukong build unless the
build table and Vivado source list explicitly select them.

| File / module | Purpose | Language | Vendor dependency | Clock assumptions | Memory assumptions | Class | Proposed Wukong action / notes |
|---|---|---|---|---|---|---|---|
| `coco3fpga_dw.v` / `coco3fpga_dw` | DE1 top-level, CoCo/GIME register logic, MMU/decode, SRAM arbitration, reset, clocks, peripheral integration | Verilog | Directly instantiates `PH2_CLK`, `FFF0`; DE1 pin/peripheral model | 50 MHz master; falling-edge divider; a state machine creates 0.89/1.79/8.33/25 MHz CPU timing and interleaves CPU/video SRAM cycles; `PH_2_RAW` is promoted by Altera clock control | Asynchronous 16-bit external SRAM, byte lanes selected by A0; up to 2 MiB addressing though DE1 wiring/commentary varies; external flash plus small internal memories | **DE1-ONLY** as a top; **MODIFY** only later when extracting portable machine logic | Do not use as the first Wukong top and do not rewrite it. Add a separate Wukong top. Later isolate machine/decode/arbitration carefully, replacing SRAM timing explicitly. Switch/button defaults must become constants or Wukong configuration parameters, not prerequisites. |
| `cpu09l_128.vhd` / `cpu09` | John Kent 6809-compatible CPU | VHDL | None found | One `clk`; active-high reset; bus and interrupt timing tied to `PH_2` in the reference top | External 8-bit synchronous bus contract, no internal memory | **KEEP** | Compile unchanged in Vivado mixed-language flow. Verify reset-vector and read/write phase timing at integration. Entity is lowercase `cpu09` (VHDL is case-insensitive; Verilog instantiates `CPU09`). |
| `coco3vid.v` / `COCO3VIDEO` | CoCo 1/3 raster generation, text/graphics interpretation, RGB and sync generation | Verilog | Instantiates Altera `COCO3GEN` character ROM | `PIX_CLK` is `CLK50MHZ` in the reference; counters and outputs update directly in that domain | Consumes a 16-bit video buffer supplied by top-level external-SRAM arbitration; produces 20-bit video address; assumes the reference fetch cadence | **MODIFY** | Preserve raster/GIME behavior. Replace only character ROM first. Later expose RGB/HSYNC/VSYNC/blanking through an adapter; do not force HDMI timing into this module. BRAM latency and video prefetch require explicit analysis. |
| `cocokey.v` / `COCOKEY` | Maps PS/2 scan events into the 56-key CoCo matrix and reset/shift signals | Verilog | None | Input sampling from nominal 50 MHz; slow reset clock supplied as `V_SYNC`; internally instantiates PS/2 decoder | Register state only | **DEFER** | Reuse after BASIC video. Later give asynchronous PS/2 inputs proper constraints/synchronization review; keyboard must not gate startup. |
| `ps2_keyboard.v` / `ps2_keyboard` | PS/2 serial decoder | Verilog | None | Samples asynchronous PS/2 clock/data with system clock | No RAM | **DEFER** | Reuse with `COCOKEY` in keyboard phase; PMOD pin mapping belongs only in Wukong constraints. |
| `SDCard.v` / `SDCard` | CPU-visible SPI SD interface/state machine | Verilog | None | `clk_i` is asynchronous and documented as 2x SPI clock; reference supplies 25 MHz; `cpuclk_n_i` is `PH_2`; contains an explicit cross-domain halt synchronizer | Small registers only | **DEFER** | Keep unchanged until storage phase; review CDC and generated SPI rate then. Never include in early HDMI acceptance path. |
| `i2c.v` / `I2C` | Register-programmed I2C master used by disk/slave subsystem | Verilog | None | Falling edge of supplied clock, async active-low reset | Registers only | **DEFER** | Retain for later peripheral/storage work. |
| `sound.v` (include fragment) | CoCo audio mixing/DAC datapath | Verilog include | None | Uses surrounding top-level signals/clocks | Register/arithmetic state | **DEFER** | Integrate only after BASIC/keyboard/storage baseline; later wrap a clean audio interface. |
| `paddles.v` (include fragment) | Joystick/paddle timing | Verilog include | None | Uses `MCLOCK[10]` and async reset | Registers only | **DEFER** | Not part of no-wiring milestones. |
| `uart_6551.v` / `glb6551`; `6551rx.v` / `uart51_rx`; `6551tx.v` / `uart51_tx` | 6551-compatible serial subsystem | Verilog | None | CPU `PH_2` plus receive/transmit/baud clocks; some explicit domain synchronization | FIFO/register state only | **DEFER** | Retain for later serial/DriveWire work; CDC/timing review before use. |
| `uart_6850.v` / `glb6850`; `6850RX.v` / `UART_RX`; `6850TX.v` / `UART_TX` | 6850-compatible serial subsystem | Verilog | None | CPU `PH_2` plus independent UART clocks; explicit synchronization comments | FIFO/register state only | **DEFER** | Retain for later serial/DriveWire work. |

## Generated memories, FIFO, and clock resources

| File / module | Purpose | Language/data | Vendor dependency | Clock and latency assumptions | Memory assumptions | Class | Proposed Wukong action / notes |
|---|---|---|---|---|---|---|---|
| `COCO3GEN.v` / `COCO3GEN`; `coco3gen.mif` | 2 KiB x 8 CoCo character-generator ROM | Altera-generated Verilog + MIF | `altsyncram`, Cyclone II, `altera_mf` | Clocked address with **unregistered output** configuration; effective behavior must be established in simulation | Initialized from `coco3gen.mif` | **REPLACE** | Add an inferred ROM wrapper with identical ports; convert/consume MIF reproducibly (prefer a checked-in Vivado-readable `.mem`). Preserve address-to-pixel pipeline latency. |
| `FFF0.v` / `FFF0`; `FFF0.mif` | Writable 2 KiB x 8 vector/fast-ROM page | Altera-generated Verilog + MIF | `altsyncram`, Cyclone II | Single `PH_2` clock, unregistered output configuration, same-port read/write behavior is not explicitly documented | Initialized single-port RAM, CPU writes enabled by `ROM_RW & FFF0_EN` | **REPLACE** | Inferred initialized RAM with identical interface. Establish read-during-write and output latency before replacement; this block contains reset vectors and is CPU-critical. |
| `disk02.v` / `disk02`; `DISK_02.mif` | 2 KiB x 8 initialized writable memory for the legacy disk subsystem | Altera-generated Verilog + MIF | `altsyncram`, Cyclone II | Single `PH2_02` clock, unregistered output setting | Initialized single-port RAM | **REPLACE**, then **DEFER** | Implement only for a future storage phase; preserve initialization and read-during-write behavior. Case mismatch (`disk_02.mif` in wrapper versus checked-in `DISK_02.mif`) matters on case-sensitive hosts. |
| `buffer_dp.v` / `buffer_dp` | 512 x 8 dual-clock, dual-port disk transfer buffer (instantiated twice) | Altera-generated Verilog | `altsyncram`, Cyclone II | Independent write/read clocks; B address registered, B output configured unregistered | True dual-clock RAM; wrapper names an absent `buffer_dp` init file although power-up is configured initialized | **REPLACE**, then **DEFER** | Use inferred simple dual-port dual-clock RAM only after confirming Vivado inference and exact one-cycle address/output behavior. No initialization file is present. |
| `FIFO_READ.v` / `FIFO_READ` | 512 x 8 dual-clock FIFO | Altera-generated Verilog | `dcfifo`, `altera_mf`, Cyclone II | Independent clocks, async clear, non-show-ahead output; 4-stage read/write synchronizer settings | BRAM-backed async FIFO | **REPLACE**, then **DEFER** | Prefer XPM FIFO or a proven portable async FIFO. Match non-FWFT behavior, flags, reset semantics, depth, and CDC constraints. |
| `FIFO_WRITE.v` / `FIFO_WRITE` | 512 x 8 dual-clock FIFO | Altera-generated Verilog | `dcfifo`, `altera_mf`, Cyclone II | Independent clocks, async clear, non-show-ahead output; 5-stage synchronization settings | BRAM-backed async FIFO | **REPLACE**, then **DEFER** | Same as read FIFO; retain the original conservative synchronization depth unless equivalence is demonstrated. |
| `PH2_CLK.v` / `PH2_CLK` | Promotes generated `PH_2_RAW` onto a global clock network | Altera-generated Verilog | Direct `cycloneii_clkctrl` primitive | Input is a logic-generated, variable-rate CPU clock | None | **REPLACE** | Do not translate literally to a fabric-clock buffer without review. Preferred later architecture is a stable global system clock plus CPU clock enable; if a real divided clock remains necessary use supported Xilinx clocking and generated-clock constraints. Preserve bus phase relationships. |
| `*_bb.v` for the six generated blocks | Quartus black-box declarations | Altera-generated Verilog | Quartus flow only | Mirrors associated wrapper | None | **DE1-ONLY** | Do not add to Vivado sources. Files: `COCO3GEN_bb.v`, `disk02_bb.v`, `FFF0_bb.v`, `buffer_dp_bb.v`, `FIFO_READ_bb.v`, `FIFO_WRITE_bb.v`, `PH2_CLK_bb.v`. |
| `COCO3GEN_inst.v`, `PH2_CLK_inst.v` | Wizard instantiation templates, not design modules | Verilog snippets | Quartus wizard artifacts | N/A | N/A | **DE1-ONLY** | Retain as historical reference; do not compile. |
| `*.qip` | Quartus IP include metadata | Tcl-like Quartus assignments | Quartus only | N/A | Names generated wrapper/black-box files | **DE1-ONLY** | Do not use in Vivado. Files present: `coco3gen.qip`, `disk02.qip`, `buffer_dp.qip`, `FIFO_READ.qip`, `FIFO_WRITE.qip`, `PH2_CLK.qip`. |

## Project and board files

| File | Purpose | Vendor dependency | Class | Wukong action / notes |
|---|---|---|---|---|
| `coco3fpga_dw.qsf` | Quartus Cyclone-II device, file, timing, and DE1 pin assignments | Quartus; targets `EP2C20F484C7` | **DE1-ONLY** | Use only to recover source order, ports, and intent. It includes DE1 VGA, SRAM, flash, audio, PS/2, switches/buttons, LEDs, and other pins that must not leak into the Wukong top. |
| `CoCo3FPGA.qpf` | Quartus project/revision metadata | Quartus | **DE1-ONLY** | Retain as reference. |
| `LICENSE` | Project license | None | **KEEP** | Preserve. New files should remain compatible with it. |

## Missing and inconsistent legacy inputs

The legacy QSF refers to files not present anywhere in this checkout: `disk_c0.mif`,
`disk_c0.qip`, `disk_c8.qip`, `disk_d0.qip`, `disk_d8.qip`,
`buffer_dp.mif`, `disk02_1.qip`, `Video_DAC.qip`, and `uartclk.qip`.
`disk_02.mif` is also named with different case from the checked-in
`DISK_02.mif`. These are legacy-build reproducibility issues, not permission to
invent ROM contents. None is required for the standalone HDMI test; ROM/image
provenance must be resolved before claiming a complete machine build.

## Obvious Altera/Quartus dependencies to replace

1. `altsyncram` in `COCO3GEN.v`, `FFF0.v`, `disk02.v`, and `buffer_dp.v`.
2. `dcfifo` in `FIFO_READ.v` and `FIFO_WRITE.v`.
3. `cycloneii_clkctrl` in `PH2_CLK.v`.
4. All `.qip`, `_bb.v`, wizard instantiation snippets, `.qsf`, and `.qpf`
   artifacts in a Vivado source set.
5. Altera MIF initialization handling. Contents must be converted without
   changing byte order/address meaning and checked by a small ROM test.
6. DE1 external asynchronous SRAM/flash, VGA DAC, audio codec, PS/2, switch,
   button, LED, serial, and SD pin glue embedded in `coco3fpga_dw`.

No Altera primitive was found inside the CPU09, GIME/video behavior,
keyboard decoder/matrix, SD controller, I2C, UART, sound, or paddle source
itself.

## Clock and reset facts that constrain later work

- The reference master is 50 MHz. `MCLOCK` is a falling-edge binary divider.
- CPU `PH_2` is not a simple fixed divide in all modes. A 50 MHz state machine
  interleaves external SRAM CPU and video accesses and creates approximately
  0.89286, 1.7857, 8.33, or 25 MHz CPU operation depending on switches/build
  mode. Changing this also changes memory/video arbitration.
- CoCo video receives the 50 MHz master as `PIX_CLK`; this is machine raster
  logic, not an HDMI-standard pixel stream.
- SD logic crosses between 25 MHz (`MCLOCK[0]`) and CPU `PH_2`.
- Reset is asserted by DE1 button or keyboard logic, then stretched by a state
  machine clocked from a divided master clock. CPU reset releases later than
  general reset. The source comments' divisor/time arithmetic is inconsistent
  with `MCLOCK[8]`; measure the actual RTL behavior before reproducing it.
- Several logic-generated/divided clocks appear throughout the design. Later
  conversion should prefer one or a small number of MMCM-derived global clocks
  plus clock enables, with explicit CDC constraints where domains remain.

## Current Wukong build boundaries

The active Wukong source set has three entry points:

- `COCO3_ELITE` combines the complete CoCo integration with the hdl-util
  HDMI encoder and continuous 48 kHz audio packets.
- `HDMI_TEST_PATTERN` displays the library test pattern and sends zero-valued
  HDMI audio samples. It does not generate a sound test.
- `BASIC_6809_DVI_TEST` retains the small CPU09 and block-RAM diagnostic with the
  local DVI-compatible serializer.

The removed standalone and synthetic-video checkpoints no longer contribute
RTL or selectable build modes. The remaining `test_pattern.v` is shared by
`HDMI_TEST_PATTERN`, while `tmds_serializer.v` remains necessary for
`BASIC_6809_DVI_TEST`.
