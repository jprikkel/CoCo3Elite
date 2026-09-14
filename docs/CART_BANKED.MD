# Banked cartridge support

Status: design proposal. No banked cartridge mapper is implemented.

## Why banked cartridges are different

The processor can see only a limited external-ROM window at one time. A larger
cartridge contains additional ROM and changes which bank appears in that
window when software reads or writes a mapper-specific address.

Raw `.CCC` files contain bytes, not a circuit description. Their size does not
identify:

- Bank width or number of banks.
- Power-on bank.
- Whether a bank change is selected by address, written data, or a read side
  effect.
- Whether the visible window is 8 or 16 KiB.
- Whether SCS `$FF40-$FF5F` registers are also present.
- Whether the cartridge includes RAM, sound, NMI, or HALT behavior.

For example, MAME's CoCo cartridge catalog explicitly marks Mind-Roll as a
`banked_16k` device and notes mapper behavior for Mind-Roll, RoboCop, and
Predator. That metadata cannot be recovered reliably from a raw dump alone.
See the [MAME CoCo cartridge catalog][mame-cart-list].

## Required separation

Implement three layers rather than adding title-specific tests to the main
memory decoder:

```text
SD image and sidecar metadata
             |
             v
RV32 cartridge loader and profile selection
             |
             v
generic cartridge bus + selected mapper
             |
             v
ROM storage / optional peripheral functions
```

The CoCo machine should ask the selected mapper for a byte and present mapper
writes with their original address and data. The mapper owns bank registers;
the machine owns the standard CPU, GIME, PIA, and RAM decode.

## Mapper interface

A project-owned mapper interface should include:

| Signal | Purpose |
| --- | --- |
| CPU address, data, and R/W | Observe accesses used by the mapper |
| CTS select | Read from the external-ROM window |
| SCS select | Read or write `$FF40-$FF5F` cartridge I/O |
| E/Q phase or qualified bus strobe | Commit side effects once per valid cycle |
| Reset | Restore the mapper's power-on bank |
| ROM address | Address into cartridge storage after bank translation |
| Read data and drive enable | Return ROM, RAM, or peripheral data without contention |
| CART, NMI, and HALT outputs | Optional cartridge control lines |
| Audio output | Optional signed cartridge audio sample |

Do not put mapper behavior into the third-party MC6809 core.

## Metadata format

Use an optional sidecar with the same base name:

```text
MINDROLL.CCC
MINDROLL.CART
```

The first sidecar format should be deliberately small enough for the existing
firmware parser. A line-oriented example is:

```text
type=banked-rom
mapper=banked-16k-v1
rom_size=32768
bank_size=16384
power_on_bank=0
```

Only named, implemented mapper profiles are accepted. Do not initially expose
arbitrary address masks or expressions from removable media directly to RTL.
That would be difficult to validate and could conflict with FDC or future
hardware-cartridge registers.

An offline utility may translate MAME software-list metadata into these compact
sidecars. The RV32 firmware should not parse a large XML database.

## Storage choices

### Entire image in block RAM

This has deterministic zero-wait access and is easiest to verify, but the
current build already spends substantial block RAM on CoCo RAM, RV32 TCM, and
the full drive-0 DSK cache. It is reasonable for the first 32 KiB mapper test,
but it does not scale to large multicarts.

### External DDR storage

This is the preferred long-term solution for large cartridges and future
capabilities. It needs a Wukong DDR controller, clock-domain crossing, cache or
prefetch policy, and arbitration with other prospective users. The CPU-visible
bank must be available with deterministic timing.

### SD-backed bank cache

A small FPGA bank cache could stop the 6809 with HALT when a missing bank is
selected, ask RV32 to read that bank from FAT32, verify it, and then resume.
This saves block RAM but is substantially more complex:

- Software may execute from the bank immediately after the selecting write.
- The mapper must capture that write exactly once before halting.
- Card removal and read failure need a recoverable state.
- Long SD latency freezes the CoCo and audio/video-visible program behavior.
- Dirty cartridge RAM, if supported later, requires a separate policy.

Never perform an SD read directly in response to an ordinary CPU ROM fetch.

## Implementation phases

1. Finish linear 16/32 KiB support described in
   [Linear cartridge image support](CART_FILE.MD).
2. Introduce the generic mapper interface with a pass-through linear mapper.
3. Add one source-available `banked_16k` mapper and synthetic patterned ROM
   tests.
4. Add sidecar parsing and explicit mapper selection in the F12 browser.
5. Measure block-RAM use and decide whether the second mapper can remain fully
   resident or requires DDR/cache work.
6. Add mapper profiles individually, with documentation and regression tests
   for each profile.

## Reset and launch behavior

- Loading a new image disables the previous mapper before any ROM writes.
- The mapper and bank register receive a power-on reset during the CoCo-only
  cold-start sequence.
- RV32 and mounted disks survive that reset.
- The image and metadata are verified before the mapper becomes visible.
- CART/FIRQ is generated only after BASIC completes initialization.
- Ctrl+Alt+Delete disables the mapper and returns to Disk BASIC.
- Reopening F12 without reset must not generate mapper side effects from menu
  traffic.

## Tests and acceptance

- Unit-test every mapper's bank-address calculation.
- Use a generated ROM with unique data and executable loops in every bank.
- Verify selecting a bank by address and by data where the profile requires it.
- Test normal and fast CPU clocks.
- Test all-RAM and GIME ROM-map changes while executing from the cartridge.
- Test repeated reset, cartridge replacement, SD removal, and invalid sidecars.
- Confirm Disk BASIC FDC registers are not intercepted by a ROM-only mapper.
- Synthesize and report block-RAM and timing changes for every added profile.

Commercial cartridge images remain user-supplied and must not be committed.

## Open questions

- Which mapper profile provides the highest compatibility value after linear
  CoCo 3 cartridges?
- Which existing dumps have reversed or nonphysical bank ordering?
- Is a compact manifest sufficient, or should a host utility maintain a CRC
  database and generate manifests automatically?
- At what image size should the implementation require external DDR instead of
  block RAM?

[mame-cart-list]: https://github.com/mamedev/mame/blob/master/hash/coco_cart.xml
