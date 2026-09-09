param([string]$ToolchainBin = 'C:\AMD\2025.2\gnu\riscv\nt\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\management\firmware'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
& (Join-Path $ToolchainBin 'riscv64-unknown-elf-gcc.exe') `
    -march=rv32i_zicsr -mabi=ilp32 -std=c11 -Os -ffreestanding -fno-builtin `
    -Wall -Wextra -Werror -c (Join-Path $repoRoot 'firmware\management\usb_host_spi.c') `
    -o (Join-Path $runDir 'usb_host_spi.o')
if ($LASTEXITCODE -ne 0) { throw "RISC-V firmware compile failed: $LASTEXITCODE" }
& (Join-Path $ToolchainBin 'riscv64-unknown-elf-size.exe') (Join-Path $runDir 'usb_host_spi.o')
if ($LASTEXITCODE -ne 0) { throw "Firmware size report failed: $LASTEXITCODE" }
Write-Host 'PASS: management firmware compile check (not a linked boot image)'
