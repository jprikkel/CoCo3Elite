$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'build\test-manager-sd-fat32-firmware'
$toolchain = 'C:\AMD\2025.2\gnu\riscv\nt\bin'
New-Item -ItemType Directory -Force $work | Out-Null
$gcc = Join-Path $toolchain 'riscv64-unknown-elf-gcc.exe'
$gccArgs = @('-march=rv32im_zicsr', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin', '-nostdlib',
    '-Wl,--build-id=none', '-T', (Join-Path $repo 'firmware\management\rv32_tcm.ld'),
    (Join-Path $repo 'firmware\management\rv32_start.S'), (Join-Path $repo 'firmware\management\rv32_sd_fat32_list.c'),
    '-o', (Join-Path $work 'rv32_sd_fat32_list.elf'))
& $gcc @gccArgs
if ($LASTEXITCODE) { throw "RV32 firmware compile/link failed: $LASTEXITCODE" }
& (Join-Path $toolchain 'riscv64-unknown-elf-size.exe') (Join-Path $work 'rv32_sd_fat32_list.elf')
if ($LASTEXITCODE) { throw "RV32 firmware size report failed: $LASTEXITCODE" }
Write-Host 'PASS: RV32 FAT32 listing firmware builds'
