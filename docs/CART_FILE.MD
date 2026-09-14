# Linear cartridge image support

Status: 2, 4, and 8 KiB raw `.CCC` cartridge images are implemented and
hardware-verified. Linear 16 and 32 KiB cartridge images are proposed.

## Current implementation

The F12 browser accepts a raw 2, 4, or 8 KiB `.CCC` file from FAT32. Firmware
mirrors a 2 or 4 KiB image across an 8 KiB cartridge window, writes it through
manager MMIO, and compares a rolling address-and-data signature before launch.

The cartridge is visible at `$C000-$DFFF`. Selection performs a CoCo-only cold
start, clears the BASIC warm-start flag at `$0071`, waits for the BASIC idle
loop, maps the verified cartridge, and generates the normal CART/FIRQ event.
The RV32 and mounted disk cache remain running. Ctrl+Alt+Delete disables the
cartridge and returns to Disk BASIC.

This behavior is the reference that larger linear images must preserve.

## Problems already investigated

The following failed approaches must not be reintroduced:

- Mapping the 8 KiB image into `$E000-$FDFF` replaced Super Extended BASIC
  routines and caused diagnostics to execute unrelated mirrored cartridge
  bytes.
- Jumping directly to `$C000` skipped normal ROM, GIME, PIA, and interrupt
  initialization and produced corrupt video or random execution.
- Launching a new cartridge into a running program generated CART/FIRQ in
  arbitrary machine state. A physical CoCo cartridge is installed with power
  removed, so the management UI now models a cold insertion.
- Enabling the cartridge while the reset pipeline still reported the old BASIC
  program counter occasionally accepted stale `$A7D3-$A7D7`. The sequencer now
  requires the PC to leave that range before accepting its later return.
- Advancing the manager cartridge address in the same registered MMIO write
  shifted every byte by one clock. Firmware now writes every address explicitly
  and verifies the completed image signature.
- Treating cartridge RAM as an asynchronous ROM hid the one-cycle behavior of
  the FPGA block RAM. The current synchronous CPU read path is intentional.
- Holding a cartridge active across Ctrl+Alt+Delete allowed the reset ROM to
  start with stale cartridge and video state. Soft reset now disarms the active
  cartridge session.

These findings are covered by the boot, reset, and cartridge-trace regressions.

## CoCo cartridge address spaces

The physical cartridge connector provides more than a ROM byte stream:

- CTS selects the cartridge ROM region.
- SCS selects cartridge I/O in `$FF40-$FF5F`.
- CART reaches the PIA/GIME interrupt path.
- NMI and HALT permit cartridge hardware to interrupt or stop the processor.
- The CoCo 3 GIME selects internal and external ROM layouts through `INIT0`.

The current implementation deliberately models only the normal 8 KiB
`$C000-$DFFF` ROM-Pak window. A linear CoCo 3 image must use the corresponding
GIME external-ROM layout; it must not be implemented as an unconditional mirror
over the system ROM.

See the [Tandy CoCo 3 Service Manual][service-manual] for the cartridge signals
and memory-map controls.

## Proposed linear profiles

| Profile | File size | Intended behavior |
| --- | ---: | --- |
| `legacy_2k` | 2 KiB | Mirror through the existing 8 KiB CTS window |
| `legacy_4k` | 4 KiB | Mirror through the existing 8 KiB CTS window |
| `legacy_8k` | 8 KiB | Existing `$C000-$DFFF` mapping |
| `linear_16k` | 16 KiB | Use the documented 16 KiB external-ROM layout |
| `coco3_linear_32k` | 32 KiB | Use the CoCo 3 32 KiB external-ROM layout while preserving I/O and vectors |

File size can select the first three profiles. It is not sufficient to
distinguish every 16 or 32 KiB image from a banked cartridge. Ambiguous files
need metadata as described in [Banked cartridge support](CART_BANKED.MD).

## RTL and firmware changes

1. Expand `coco3_sd_cartridge` from 8 KiB to 32 KiB and pass all 15 address bits
   already exposed by the manager interface.
2. Add a cartridge-profile register to manager MMIO.
3. Decode the CPU address according to the selected profile and current GIME
   ROM-map mode.
4. Keep standard CoCo I/O and vector behavior outside the external-ROM window.
5. Extend the firmware scanner and loader to accept 16 and 32 KiB images.
6. Include the selected profile in the transfer signature so an image cannot be
   launched under stale mapping metadata.
7. Preserve the current cold-start and CART/FIRQ sequencer without a second
   launch path.

The current MMIO and boot-system wiring already carry a 15-bit manager
cartridge address. The storage module currently discards the upper two bits,
so this is an extension of an existing interface rather than a new bus.

## Resource impact

The current 8 KiB true dual-port cartridge memory synthesizes as block RAM. A
32 KiB implementation is expected to use approximately four times that
cartridge storage. Measure the routed result rather than relying on inference
alone, because the design also contains a full drive-0 disk cache and 64 KiB
RV32 TCM.

Do not allocate block RAM for large speculative mapper support. Complete linear
32 KiB support first and reserve external DDR or a controlled bank cache for
larger images.

## Image ordering and metadata

Raw cartridge dumps are not self-describing. Even two images of the same size
may use different physical ordering or mapper hardware. A known 32 KiB dump
ordering issue has affected Arkanoid in emulators, and the MAME software list
uses explicit slot metadata for some banked cartridges. See the
[MAME CoCo cartridge catalog][mame-cart-list].

Default behavior should therefore be conservative:

- Recognized 2, 4, and 8 KiB images use the existing mapping.
- A 16 or 32 KiB image uses a linear profile only when the format or metadata
  identifies it as linear.
- An ambiguous image is shown as unsupported instead of silently choosing a
  mapper.
- CRC-based identification may improve convenience but must not replace an
  explicit profile for unknown or modified images.

## Tests

- Verify the first, middle, and last byte of every supported image size.
- Test all relevant `INIT0` ROM-map values and all-RAM transitions.
- Prove that `$E000-$FDFF`, `$FE00-$FEFF`, I/O, and vectors retain their required
  sources for each profile.
- Run the existing 2/4/8 KiB cartridge suite unchanged.
- Add generated 16 and 32 KiB images with unique patterns in every 8 KiB block.
- Test cold selection, repeated selection, different-image selection, reset,
  and F12 return.
- Hardware-test source-available CoCo 3 software; do not commit commercial ROM
  images.

## Relevant implementation files

- [`firmware/management/rv32_sd_mount.c`](../firmware/management/rv32_sd_mount.c)
- [`rtl/management/manager_sd_mmio.v`](../rtl/management/manager_sd_mmio.v)
- [`rtl/core/coco3_sd_cartridge.v`](../rtl/core/coco3_sd_cartridge.v)
- [`rtl/core/coco3_boot_machine.v`](../rtl/core/coco3_boot_machine.v)
- [`rtl/wukong/coco3_boot_system.v`](../rtl/wukong/coco3_boot_system.v)

[service-manual]: https://colorcomputerarchive.com/coco/Documents/Manuals/Hardware/Color%20Computer%203%20Service%20Manual%20%28Tandy%29.pdf
[mame-cart-list]: https://github.com/mamedev/mame/blob/master/hash/coco_cart.xml
