$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'build\wukong-manager-sd-fat32'
$firmwareWork = Join-Path $work 'firmware'
$toolchain = 'C:\AMD\2025.2\gnu\riscv\nt\bin'
$gcc = Join-Path $toolchain 'riscv64-unknown-elf-gcc.exe'
$objcopy = Join-Path $toolchain 'riscv64-unknown-elf-objcopy.exe'
$vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat'
New-Item -ItemType Directory -Force $firmwareWork | Out-Null
$gccArgs = @('-march=rv32im_zicsr', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin', '-nostdlib',
    '-Wl,--build-id=none', '-Wl,--gc-sections', '-T', (Join-Path $repo 'firmware\management\rv32_tcm.ld'),
    (Join-Path $repo 'firmware\management\rv32_start.S'), (Join-Path $repo 'firmware\management\rv32_sd_fat32_list.c'),
    '-o', (Join-Path $firmwareWork 'rv32_sd_fat32_list.elf'))
& $gcc @gccArgs
if ($LASTEXITCODE) { throw "RV32 firmware link failed: $LASTEXITCODE" }
& $objcopy -O binary (Join-Path $firmwareWork 'rv32_sd_fat32_list.elf') (Join-Path $firmwareWork 'rv32_sd_fat32_list.bin')
if ($LASTEXITCODE) { throw "RV32 firmware conversion failed: $LASTEXITCODE" }
& (Join-Path $repo 'scripts\generate_rv32_program_header.ps1') `
    -Binary (Join-Path $firmwareWork 'rv32_sd_fat32_list.bin') `
    -Output (Join-Path $work 'rv32_sd_list_program.vh')
& $vivado -mode batch -nojournal -nolog -source (Join-Path $repo 'scripts\build_wukong_manager_sd_fat32.tcl')
if ($LASTEXITCODE) { throw "Manager SD/FAT32 bitstream build failed: $LASTEXITCODE" }
