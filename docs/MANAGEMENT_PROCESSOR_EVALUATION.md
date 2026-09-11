# Management processor evaluation

Research date: 2026-09-08. Companion to the
[SD-card and USB plan](SDCARD_SUPPORT_PLAN.md). The comparison is source-based;
no CPU had been benchmarked in the running CoCo system at the time. A subsequent
isolated MicroBlaze V resource prototype was evaluated, then removed after the
project selected and integrated the open ultraembedded RV32IM core. The
historical figures below are not comparative CPU benchmarks.

## Decision for this project

Keep the management CPU inside the FPGA. Shortlist **NEORV32 and AMD MicroBlaze V**
for the first prototype. NEORV32 is the provisional preference for an open,
portable HDL/firmware build; MicroBlaze V is the strongest alternative for AMD
tool integration. Include VexRiscv if measured CPU throughput or area makes the
first two unsatisfactory. PicoRV32 is a compact baseline, not the default choice
for a new service with concurrent filesystem and USB work.

ARM Cortex-M1/M3 is technically possible in FPGA fabric. It does not provide an
automatic performance or USB advantage over these RISC-V choices. ARM MCU USB
examples usually depend on a particular chip's integrated USB controller;
instantiating a Cortex-M processor in an Artix-7 does not instantiate that
controller. The same MAX3421E driver and board adaptation work remain.

Choose on complete-system measurements: CPU plus bus, memory, interrupts,
buffers, debug facilities, firmware, and reproducibility. Management throughput
does not change the emulated 6809's normal/fast clocks.

## Candidate comparison

Ratings below are engineering judgments for our project, not measured rankings.

| Candidate | Performance and resource tradeoff | Implementation and software | Position |
| --- | --- | --- | --- |
| ARM Cortex-M1/M3 | Familiar MCU architectures; actual area, memory use, and speed depend on the available FPGA package. No comparable local result. | Strong ARM compiler/CMSIS/RTOS ecosystem. Need current IP access, redistribution terms, Vivado compatibility, and a custom peripheral/BSP integration. | Consider if usable IP and team familiarity demonstrably reduce work. |
| NEORV32 (RISC-V) | Configurable MCU-class core/SoC; trim unused units and size IMEM/DMEM. Benchmark interrupt and filesystem workloads. | Portable VHDL, bundled peripherals/software/tests, GCC and RTOS options. Natural fit for an independently reproducible repository. | Provisional first choice. |
| MicroBlaze V (RISC-V) | Configurable pipeline and optional ISA units/caches. Strong performance candidate; costs depend on selected AXI/peripheral/debug system. | Native Vivado/Vitis flow and AMD support. Adds generated-IP and software-platform tooling to our scripted build. | Co-finalist; likely easiest vendor-supported integration here. |
| VexRiscv (RISC-V) | Pipelined configurations provide a strong performance/area candidate. Small configurations sacrifice features; caches and bypassing change the comparison. | MIT-licensed, generated from SpinalHDL; GCC/FreeRTOS/Zephyr paths. Need pinning of generator/configuration and SoC integration. | Performance-focused alternative. |
| PicoRV32 (RISC-V) | Compact multicycle core; high achievable clock is not equivalent to high instructions per second. | Small Verilog CPU and simple bus. More integration required; upstream reports no active development. | Baseline for compactness, not assumed smallest complete system. |
| Classic MicroBlaze | Mature configurable soft CPU; actual area and speed require the same measurements. | Established AMD tools/BSPs but a different ISA from MicroBlaze V. No special MAX3421E advantage. | Retain as an alternative if a required driver/tool path is better supported. |
| Nios II / ZPU / another 6809 | No established performance/resource win for this design. | Nios II follows the Intel/Altera ecosystem; ZPU/6809 bring additional toolchain/porting constraints for current middleware. | Architectural references, not first implementation candidates. |

Primary candidate references: [ARM FPGA announcement][arm-fpga],
[current DesignStart page][arm-current], [NEORV32][neorv32],
[MicroBlaze V][mbv], [classic MicroBlaze][mb], [VexRiscv][vex],
and [PicoRV32][pico].

ARM's 2018 announcement offered Cortex-M1/M3 for Xilinx FPGAs, including Artix.
The present DesignStart page describes a refreshed access program. Do not
interpret the historical offer as proof that a compatible, redistributable IP
package can be downloaded and built with our current tools today. Verify that
before spending integration effort; this evaluation has not obtained ARM IP.

Local evidence: Vivado 2025.2 contains both `microblaze_riscv_v1_0` and
`microblaze_mcs_riscv_v1_0`, as well as classic MicroBlaze IP. This proves the
hardware packages are installed, not that Vitis/BSP setup or our application
already works. ARM and standalone RISC-V compilers were not found on the current
shell PATH; toolchain installation/discovery is part of prototype setup.

## What the published performance numbers mean

PicoRV32 quotes roughly 750-2,000 LUTs for its CPU on Xilinx 7-series. VexRiscv
publishes an Artix-7 small configuration at 556 LUTs and a small/productive
configuration at 816 LUTs, with different instruction throughput. Those are
upstream configurations under their stated synthesis conditions, not complete
controllers or expected Wukong utilization. They demonstrate why "Pico is
smallest" or "ARM is fastest" cannot be inferred from architecture names.
See the [PicoRV32 description][pico] and [VexRiscv results][vex].

For this application, filesystem metadata access, storage busy time, firmware
instruction memory, SPI transfers, and USB scheduling can dominate. Hardware
transfer engines and buffering may improve service more than changing the CPU.
The MAX3421E remains a 12 Mb/s full-speed USB host regardless of CPU frequency;
its SPI connection also limits useful throughput. A high-speed USB design is a
different host-controller/PHY project, not a faster CPU setting.

The existing embedded-disk build is at 92.22% BRAM but only 9.42% LUT utilization.
Replacing the two disk ROMs with streaming buffers is therefore the first
resource step. Compare firmware code/stack and buffer memory as carefully as
CPU LUT count. A CPU with compressed instructions may save instruction memory;
measure the compiled application to establish the benefit.

## USB and general software support

Use FatFs and TinyUSB as portable middleware, with a small board support layer
for timer ticks, SPI transactions, interrupts, and buffer access. Begin with
bare-metal scheduling; add a supported RTOS only when it solves a measured
scheduling issue. ARM and RISC-V both have mature C compilers; changing the ISA
does not provide compatibility with an unrelated MCU vendor's USB peripheral.

TinyUSB's [host support matrix][tinyusb] explicitly lists MAX3421E over SPI and
MSC/HID/hub host classes. A new FPGA board still needs its integration hooks and
testing. Keep interrupt handling short, move work to task context, and bound SD
polling so USB tasks continue to run during writes. A faster core cannot rescue
a blocking driver that never services the USB stack.

AMD's processor pages list USB among possible peripherals, but any selected IP
must explicitly support **host** mode and the required classes. USB device-only
IP, USB-to-UART, and a host controller are different things. The availability of
a MicroBlaze peripheral in Vivado is not a guarantee of a compatible TinyUSB
host driver. MAX3421E is the concrete initial host path in this plan.

Recommendation by criterion:

- Best fit for open, portable implementation: NEORV32, subject to resource and
  scheduling tests.
- Easiest integration with the installed AMD hardware tools: MicroBlaze V,
  subject to a reproducible Vitis/GCC and BSP build.
- Strong candidate for highest throughput per FPGA resource: VexRiscv; confirm
  against configured MicroBlaze V and NEORV32 on the same workload.
- Best USB support: the combination of a supported host controller, tested
  host stack, and board drivers; there is no inherent ARM-versus-RISC-V winner.
- Minimum resource use: determined by the whole linked/synthesized system;
  compare small VexRiscv/PicoRV32 as baselines rather than declaring a winner.

## What the C64 Ultimate uses

The product generation matters:

- **Original Ultimate 64:** Gideon's official build instructions specify the
  Nios II compiler for U64. Its management CPU is a soft processor separate
  from the emulated C64 CPU. [Official repository][ultimate]
- **Ultimate 64 Elite II / Commodore 64 Ultimate:** the official recovery guide
  covers these together and describes a soft RISC CPU. The U64-II application
  Makefile targets `rv32im`/`ilp32` and sets `CLOCK_FREQ=100000000` (100 MHz).
  This establishes RISC-V management firmware, not an ARM management CPU.
  [Recovery guide][ultimate-recovery] and [application build][ultimate-make]
- **Firmware stack:** that Makefile builds C/C++ with FreeRTOS, FatFs, and
  project USB storage/hub/HID drivers. It is not a Linux management system and
  its listed USB implementation is not TinyUSB. [Application build][ultimate-make]

Do not identify the U64-II core as NEORV32 just because the repository contains
a NEORV32 submodule: it also contains RVLite and other CPU implementations.
The exact production CPU instantiation was not established from the inspected
public files. The firmware target and clock constant are verified; a specific
core-brand claim needs the matching production FPGA build.

The U64-II linker script reserves `0xE60000` bytes (14.375 MiB) for the application
memory region. This is a reserved region, not measured firmware consumption,
but it makes clear that its full system is not a tiny BRAM-only application.
[Linker script][ultimate-link]

Its useful precedent is the architecture: hardware implements the old machine
while a soft processor runs the menu, filesystems, devices, and configuration.
That supports our proposed split. Reusing the complete Ultimate firmware would
also import its hardware assumptions, C64 interfaces, memory needs, and license
obligations. Review selected concepts/components rather than assuming that
choosing RISC-V makes the whole firmware portable without adaptation.

## Prototype comparison and selection gate

Compare NEORV32 and MicroBlaze V first. Hold the application, workload, buffer
sizes, compiler optimization intent, and peripheral contracts constant. Start
at a common 50 MHz management target, then measure each design's timing margin.
Use multiplication/compressed instructions where available and report the
configuration; exclude FPU/MMU/debug features unless needed. Compare both BRAM
resident code and any proposed external-memory version separately.

Collect:

1. LUT/FF/BRAM/DSP use for CPU alone and complete subsystem; firmware code/data
   sizes, worst stack use, and remaining CoCo/cartridge/overlay memory.
2. Build reproducibility on this Windows/Vivado setup, debug capability,
   dependency versions, and the steps needed for another contributor to build.
3. Sequential file throughput, fragmented random-sector reads/writes, long-name
   directory listing time, and worst-case FDC completion latency.
4. Maximum time between USB task service calls, keyboard/mouse input latency,
   and successful sustained MSC writes with HID devices through the same hub.
5. Recovery under media removal, timeouts, force-interrupt, CoCo reset, and
   management watchdog reset without video disruption or false write success.

Select the smallest maintainable implementation that passes all functional and
latency gates. Use upstream synthetic benchmarks only as background. Add
VexRiscv if CPU throughput or footprint is the limiting factor; consider ARM
only if current IP availability and a concrete software advantage are proven.
No comparative synthesis or USB hardware testing is claimed by this document.

[arm-fpga]: https://newsroom.arm.com/news/arm-expands-design-possibilities-with-free-cortex-m-processors-for-xilinx-fpgas
[arm-current]: https://www.arm.com/resources/designstart
[neorv32]: https://github.com/stnolting/neorv32
[mbv]: https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/microblaze-v.html
[mb]: https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/microblaze.html
[vex]: https://github.com/SpinalHDL/VexRiscv
[pico]: https://github.com/YosysHQ/picorv32
[tinyusb]: https://docs.tinyusb.org/en/latest/
[ultimate]: https://github.com/GideonZ/1541ultimate
[ultimate-recovery]: https://github.com/GideonZ/1541ultimate/blob/master/recovery/u64ii/README.md
[ultimate-make]: https://github.com/GideonZ/1541ultimate/blob/master/target/u64ii/riscv/ultimate/Makefile
[ultimate-link]: https://github.com/GideonZ/1541ultimate/blob/master/target/u64ii/riscv/ultimate/linker.x
