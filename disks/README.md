# CoCo3Elite disk images

DSK files are optional local inputs, ignored by Git and untracked. No disk is
embedded unless `scripts/build_wukong.ps1` receives `-EmbeddedTestDisks`.

| Drive | Local input | Prepared output |
| --- | --- | --- |
| 0 | `disks/fpgatest.dsk` | `build/disks/fpgatest.mem` |
| 1 | `disks/games.dsk` | `build/disks/games.mem` |

The importer accepts headerless 161,280-byte images: 35 tracks, 18 sectors per
track, 256 bytes per sector. Embedded disks are read-only block-ROM contents;
changing them requires preparing and rebuilding the bitstream. Write commands
do not save changes. Both inputs are required when embedding is enabled.

Use `-Drive0Disk <path>` and `-Drive1Disk <path>` to select different local
images. Relative paths are resolved from the repository root; absolute paths
are also accepted. These options still require `-EmbeddedTestDisks`.

Run these commands from the repository root after preparing the ROMs:

```powershell
& .\scripts\create_test_disk.ps1
# Supply your own disks/games.dsk before enabling both embedded drives.
& .\scripts\build_wukong.ps1 -Mode COCO3_ELITE -EmbeddedTestDisks
```

`create_test_disk.ps1` replaces the local `fpgatest.dsk`, packages the
[BASIC diagnostics](../tb/basic/README.md), requires local `roms/MEMT2023.BIN`
and `roms/SYSINFO.BIN`, and assembles/packages `VIDHELP.BIN`. It does not create
`games.dsk`. The build launcher converts and stages both disk memory files.

Without `-EmbeddedTestDisks`, the FDC has no mounted image backend. MicroSD
currently supports initialization and sector-zero reads only—not FAT32 DSK
mounting. Copying DSK files to a card does not make them available to Disk BASIC.
See the [storage status and roadmap](../hardware/sd-disk-interface.md).
