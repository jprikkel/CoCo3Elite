# CoCo 3 system ROM

Place a legally obtained CoCo 3 system ROM here as `coco3.rom`. The importer
accepts either a raw 32 KiB image or the historical 32,258-byte CoCo3FPGA flash
format (a two-byte `$8000` load header followed by `$8000-$FDFF`). For the
historical format it reconstructs the vector page used by the original FPGA
design. ROM and binary files in this directory are ignored by Git and must not
be committed.

Prepare the image for Vivado from the repository root:

```powershell
& scripts/prepare_coco3_rom.ps1
```

The script validates the format and reset vector, prints the source SHA-256
digest, and writes `build/roms/coco3.mem`. To require a known source digest,
pass it explicitly:

```powershell
& scripts/prepare_coco3_rom.ps1 -ExpectedSha256 '<64 hex digits>'
```

For the separate CoCo 2 Extended BASIC checkpoint, place `extbas11.rom` and
`bas13.rom` here and run `scripts/prepare_coco2_rom.ps1`. Each input must be
exactly 8 KiB. The generated `build/roms/coco2.mem` is also ignored by Git.
