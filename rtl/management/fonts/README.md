# Management UI font

`manager_fonts.mem` contains three selectable 8x16 ASCII banks. Tamzen is the
reset default; the checked-in `Spleen8x16.mem` file is the original first bank. Run
`scripts/generate_manager_fonts.ps1` after changing a source font.

- Upstream: <https://github.com/fcambus/spleen>
- Source file: `spleen-8x16.bdf`
- License: BSD-2-Clause; see `Spleen-LICENSE.txt` in this directory.

The other banks are generated from:

- **Tamzen 8x16** by Scott Fial and Suraj N. Kurapati; permissive font
  license in `Tamzen-LICENSE.txt`.
- **Terminus 8x16** by Dimitar Toshkov Zhekov; SIL Open Font License 1.1 in
  `Terminus-OFL.txt`.

Missing ASCII glyphs fall back to Spleen during generation.

Only the management overlay uses these fonts. The emulated CoCo character ROM
and its software-visible appearance remain unchanged.
