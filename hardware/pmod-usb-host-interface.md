# USB host: FPGA prototype and adapter wiring

Status: FPGA-side preparation on `sdcard-support`, 2026-09-08. No USB module
has been selected or connected. This is not enabled in the working CoCo image.

## What is implemented

- A CPU-independent mode-0 SPI peripheral in `rtl/management/usb_host_spi.v`:
  retained chip select across bytes, programmable clock, full-duplex transfers,
  a microsecond timer, synchronized interrupt/fault inputs, and safe reset/abort.
- A freestanding RISC-V C transport and MAX3421E register/oscillator probe in
  `firmware/management/`. Probe leaves VBUS off; it is not a USB host stack.
- A pin-constraint **template**, not loaded by any build:
  [`usb_host_j10.xdc.example`](../constraints/usb_host_j10.xdc.example).

The transport regression simulates SPI traffic and fault cases. The C driver
is compile-checked, **not yet executed on the soft CPU**. The USB interrupt is exposed for future
integration, not connected to the processor interrupt controller yet. Initial
firmware can poll the raw status. No FatFs/TinyUSB dependency is vendored yet.

The existing SD J13, PS/2 J14, UART diagnostics, CoCo memory map, clocks, FDC,
and third-party CPU sources are unchanged. No SD writes or USB enumeration
have been performed. Do not program this prototype over the working image.

## Adapter requirements

Use a MAX3421E **host** module with a USB-A host connector, its required clock
source and support components, and access to SS, SCLK, MOSI, MISO, INT and RES.
Select or adapt the module for **3.3 V logic on every FPGA-connected signal**.
The chip's VL supply sets its SPI/interface levels; a module's labels or input
supply voltage alone do not establish the levels of its outputs. Check its
schematic, regulators, level translators, reset circuit and power jumpers.

The controller provides low/full-speed USB (1.5/12 Mbit/s), not high-speed USB.
Its SPI interface supports up to 26 MHz, but this prototype deliberately starts
at 1 MHz and caps SCK at 6.25 MHz at a 50 MHz FPGA clock. That is a transport
limit, not measured filesystem throughput. See the
[MAX3421E datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/MAX3421E.pdf).

USB D+/D- connect between the module and USB connector, **not to PMOD GPIO**.
The Wukong's existing CH340 USB-UART connection is not a USB host port.
An arbitrary USB connector breakout or a USB-UART PMOD cannot replace the
MAX3421E host controller. A ULPI PHY would require a different FPGA host engine
and substantially different wiring/software.

## Proposed J10 wiring

These are proposed allocations using the board's
[verified PMOD pin table](wukong-pmod-pinout.md), not a claim that a commercial
USB module can plug directly into J10. Use a short adapter cable or carrier.
Verify pin 1 on the physical board and module before connecting power.

| J10 pin | FPGA ball | FPGA signal | Direction relative to FPGA | Module/carrier connection |
| ---: | --- | --- | --- | --- |
| 1 | D5 | `usb_cs_n` | Out | MAX3421E SS, active low |
| 2 | G5 | `usb_mosi` | Out | MOSI |
| 3 | G7 | `usb_miso` | In | MISO, 3.3 V levels |
| 4 | G8 | `usb_sck` | Out | SCLK, idle low |
| 7 | E5 | `usb_int_n` | In | INT, configure active-low level |
| 8 | E6 | `usb_reset_n` | Out | RES, active low; check module reset circuitry |
| 9 | D6 | `usb_vbus_en` | Out | Active-high enable of external 5 V power switch |
| 10 | G6 | `usb_overcurrent_n` | In | Active-low fault from power switch, 3.3 V levels |
| 5, 11 | GND | Ground | Power | Common FPGA/module/5 V supply ground |
| 6, 12 | 3.3 V | Logic supply | Power | Only if module supply specification and board current budget allow |

J11 is an alternative if J10 is needed for another peripheral; substitute the
balls from the pin table, do not load both allocations. J13 remains SD and J14
remains PS/2. No active top-level port or constraint was changed for this plan.

## USB power: separate from PMOD signals

**No PMOD pin supplies 5 V, and no FPGA pin is 5 V tolerant.** Provide regulated
5 V to the USB connector's VBUS through a current-limited, reverse-current-aware
power arrangement appropriate for the chosen module and supply. Do not wire
5 V to J10 pins 6/12 or any signal. `usb_vbus_en` controls a switch; it does not
power the peripheral itself. Avoid tying independent supplies together or
backfeeding the Wukong/PC through a USB hub or module power jumper.

Select a switch with 3.3 V-compatible enable and fault signals. A common
open-drain fault output needs an external pull-up to 3.3 V at the carrier;
the FPGA template pulls this input down so a disconnected fault lead prevents
power enable. If a module has no switch/fault connection, plan a carrier or
external protected switch before enabling VBUS. Do not blindly tie the fault
input high. The switch must enforce the current limit in hardware: the FPGA's
synchronized cutoff is secondary protection, with several clock cycles of delay.

Provide external pull resistors for safe **pre-configuration** states: VBUS
enable low, RES low, SS high, SCLK low, and INT high as appropriate for the
module. FPGA reset logic only protects a configured FPGA. Prevent FPGA outputs
from driving an unpowered module unless the module explicitly supports it.
Confirm total 5 V current budget, connector/cable ratings, and USB power policy
before plugging in a drive. A correctly powered, non-backfeeding hub is useful
for later keyboard+mouse+storage tests, but hub support remains unvalidated.

## Transport register contract (ABI 1)

All registers are aligned little-endian 32-bit MMIO words. The local byte
offset is eight bits. Writes require all four byte strobes; partial writes,
misaligned/unmapped accesses and writes to read-only registers set ERROR.
The prototype MCS maps this bank at **`0xC0000000`**; it is not accessible at
any new CoCo 6809 address. Other MCS IO addresses acknowledge with zero.

| Offset | Access | Meaning |
| --- | --- | --- |
| `00` | R | Transport ID `0x55425331` (`UBS1`) |
| `04` | R/W1C | Status: bit 0 BUSY, 1 DONE, 2 ERROR, 3 active INT, 4 latched power fault, 5 active overcurrent |
| `08` | R/W | Control: bit 0 CS asserted, 1 reset released, 2 IRQ output enabled, 3 VBUS requested; bit 31 write abort |
| `0C` | R/W | SCK half-period in FPGA cycles, 4..65535, reset value 25 |
| `10` | R/W | Read last received byte; write low byte to start a transfer |
| `14` | R | Microseconds since management reset; wraps modulo 2^32 |

STATUS bits 1, 2 and 4 are write-one-to-clear. INT and overcurrent are live
levels; software clears the MAX3421E interrupt source via SPI, not by clearing
STATUS. The power fault cannot be cleared while overcurrent is active.
IRQ output is `IRQ_EN && (active_INT || latched_power_fault)`. Power recovery
requires the fault input high, an explicit W1C, then a new power-enable write.
The timer requires an integer-MHz `CLK_HZ` parameter (default 50 MHz).

Assert CS only after releasing RES. CS remains asserted after DONE and across
any number of bytes. A new DATA write clears DONE. Reject DATA/control/divider
writes while BUSY without disrupting the current byte; ERROR records rejection.
The exception is CONTROL bit 31: immediately on acceptance it cancels transfer,
clears BUSY/DONE, drops VBUS, asserts RES, releases SS, and sets SCK/MOSI low.
Abort preserves latched errors for diagnosis. Global synchronous reset also
restores divider/timer/flags. Do not use the CoCo Ctrl-Alt-Del reset for the
eventual storage manager: pending file writes need a separate reset policy.

SCK = `CLK_HZ / (2 * divider)`. Sample mode-0 MISO on rising edges, change MOSI
on falling edges. MISO uses two synchronizer stages; the minimum divider is
intentional. Review actual module clock-to-output and cable delay before raising
SCK. The supplied constraint fragment cuts only input-to-first-stage paths;
inter-stage and other synchronous paths still need normal timing analysis.

The generic bus samples address/data/write strobes on the first rising clock
edge with `bus_valid` high, returns registered data and a one-cycle `bus_ack`,
and requires `bus_valid` low for at least one clock before the next request.
Holding valid high cannot repeat a write. A CPU adapter must preserve this
contract and handle all high address bits; it must not forward unrelated banks.

## Firmware and TinyUSB boundary

The current transport provides init/select/transfer/abort/pending functions.
It assumes one foreground owner, a working MMIO bus and the live hardware timer.
Transfers have a wrap-safe 25 ms byte timeout; bus-level hangs or a stopped
management clock need a later watchdog. Null TX sends zero; null RX discards
received data. `max3421_probe` resets the chip, enables four-wire full-duplex
mode, checks PINCTL readback and a nonzero/non-FF revision, then waits up to
100 ms for oscillator ready. Failure returns to reset with power off.

Next add startup/linker/ELF initialization and UART diagnostics, then run this
probe on hardware with **VBUS off**. Record the actual revision. Only after
that should we pin TinyUSB and adapt its `tuh_max3421_spi_cs_api`,
`tuh_max3421_spi_xfer_api`, `tuh_max3421_int_api` and board timing hooks. Handle
transfer failure and preserve the single-owner/interrupt masking contract.
The reference is TinyUSB's
[MAX3421E host driver](https://github.com/hathach/tinyusb/blob/master/src/portable/analog/max3421/hcd_max3421.c);
the branch URL is research, not a pinned project dependency.

## Reproduce the checks

From the repository root, with Vivado and AMD's RISC-V tools installed:

```powershell
.\scripts\test_usb_host_spi.ps1
.\scripts\check_management_firmware.ps1
```

The simulation checks independent SPI slave TX/RX behavior, command+payload
and a 64-byte burst under one CS, exact clock count, several dividers, single-ack behavior, rejected
busy/invalid accesses, level IRQ, fault latching/recovery, timer progression,
and reset/abort mid-transfer. The script requires a PASS marker and rejects
error/fatal output. These checks need no ROM, disk, module, or downloaded HDL.
The abandoned Xilinx MicroBlaze management prototype and its resource-only
synthesis flow were removed after the project selected the open RV32 manager.

Recorded checks, Vivado 2025.2 / XC7A100T-2, 2026-09-08:

- `usb_host_spi_tb`: PASS.
- RV32I C driver: compile PASS with warnings treated as errors; object text
  1,100 bytes, no static data/BSS. This excludes startup, stack, USB stack and UI.

Hardware acceptance after selecting the module: schematic/voltage review,
safe power-up and reset, SPI trace and probe with VBUS off, controlled VBUS and
fault tests using an appropriate test load (do not short the connector), then
keyboard enumeration, flash-drive read-only access, powered-hub operation and
service-latency measurements. Writable media and CoCo integration are later
gates in the [SD/USB plan](../docs/SDCARD_SUPPORT_PLAN.md).
