param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin',
    [switch]$UseExistingRomMem,
    [string]$RunDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $repoRoot 'build\sim\boot_video' }
$runDir = $RunDir

if (-not $UseExistingRomMem) {
    & (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
        -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
        -OutputPath (Join-Path $repoRoot 'build\roms\coco3.mem')
    & (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
        -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
        -OutputPath (Join-Path $repoRoot 'build\roms\disk11.mem')
}

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\core') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\management') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\coco3.mem') -Destination (Join-Path $runDir 'build\roms\coco3.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\disk11.mem') -Destination (Join-Path $runDir 'build\roms\disk11.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3gen.mem') -Destination (Join-Path $runDir 'rtl\core\coco3gen.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\management\manager_fonts.mem') -Destination (Join-Path $runDir 'rtl\management\manager_fonts.mem') -Force

$firmwareDir = Join-Path $runDir 'firmware'
$toolchain = 'C:\AMD\2025.2\gnu\riscv\nt\bin'
New-Item -ItemType Directory -Force -Path $firmwareDir | Out-Null
$firmwareElf = Join-Path $firmwareDir 'rv32_sd_mount.elf'
$firmwareBin = Join-Path $firmwareDir 'rv32_sd_mount.bin'
& (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $firmwareDir
& (Join-Path $toolchain 'riscv64-unknown-elf-gcc.exe') `
    '-march=rv32im_zicsr' '-mabi=ilp32' '-Os' '-ffreestanding' '-fno-builtin' '-nostdlib' `
    '-Wl,--build-id=none' '-Wl,--gc-sections' '-T' (Join-Path $repoRoot 'firmware\management\rv32_tcm.ld') `
    '-I' $firmwareDir `
    (Join-Path $repoRoot 'firmware\management\rv32_start.S') `
    (Join-Path $repoRoot 'firmware\management\decb_bin_format.c') `
    (Join-Path $repoRoot 'firmware\management\settings_ui.c') `
    (Join-Path $repoRoot 'firmware\management\rv32_sd_mount.c') '-o' $firmwareElf
if ($LASTEXITCODE) { throw "RV32 firmware link failed: $LASTEXITCODE" }
& (Join-Path $toolchain 'riscv64-unknown-elf-objcopy.exe') '-O' 'binary' $firmwareElf $firmwareBin
if ($LASTEXITCODE) { throw "RV32 firmware conversion failed: $LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'generate_rv32_program_header.ps1') `
    -Binary $firmwareBin -Output (Join-Path $runDir 'rv32_sd_mount_program.vh')

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $path)) { throw "$Tool was not found at: $path" }
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

$managerCpuSources = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'rtl\third-party\ultraembedded-riscv\core\riscv') -Filter '*.v'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'rtl\third-party\ultraembedded-riscv\top_tcm_axi\src_v') -Filter '*.v'
) | Sort-Object FullName | ForEach-Object FullName

$sources = @($managerCpuSources) + (@(
    'rtl\third-party\PS2_Key\ps2_keyboard.v', 'rtl\third-party\coco3fpga\cocokey.v',
    'rtl\core\coco3_keyboard_matrix.v', 'rtl\core\coco3_char_rom.v',
    'rtl\core\coco3_128k_ram.v',
    'rtl\core\coco3_system_rom.v', 'rtl\core\coco3_disk_rom.v', 'rtl\core\coco3_sd_cartridge.v',
    'rtl\core\coco3_disk_image.v',
    'rtl\management\manager_sd_mmio.v',
    'rtl\management\ultraembedded_manager_sd_mount.v',
    'rtl\management\manager_font_rom.v',
    'rtl\management\manager_osd.v',
    'rtl\core\coco3_fdc.v', 'rtl\core\coco3_gime_timer.v',
    'rtl\core\coco3_gime_interrupt.v',
    'rtl\core\coco3_boot_machine.v',
    'rtl\third-party\coco3fpga\coco3vid.v', 'rtl\wukong\uart_tx.v',
    'rtl\wukong\coco3_uart_debug.v', 'rtl\wukong\ntsc_artifact_filter.v',
    'rtl\wukong\crt_filter.v', 'rtl\wukong\coco3_boot_system.v',
    'tb\boot_video_tb.v'
) | ForEach-Object { Join-Path $repoRoot $_ })

Push-Location $runDir
try {
    Invoke-VivadoTool xvlog @((Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v'), (Join-Path $repoRoot 'rtl\core\cpu09.v'))
    Invoke-VivadoTool xvlog (@('-d', 'NEW_SRAM', '-i',
        (Join-Path $repoRoot 'rtl\third-party\ultraembedded-riscv\core\riscv'),
        '-i', $runDir) + $sources)
    Invoke-VivadoTool xelab @('-L', 'xpm', 'boot_video_tb', '-s',
        'boot_video_tb_sim', '--timescale', '1ns/1ps')
    Invoke-VivadoTool xsim @('boot_video_tb_sim', '-runall')
} finally {
    Pop-Location
}
