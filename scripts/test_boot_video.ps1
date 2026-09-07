param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\boot_video'

& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\coco3.mem')
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\disk11.mem')
& (Join-Path $PSScriptRoot 'prepare_diagnostic_cartridge.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\ziadiag.ccc') `
    -OutputPath (Join-Path $repoRoot 'build\roms\diagnostic_cart.mem')

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\core') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\coco3.mem') -Destination (Join-Path $runDir 'build\roms\coco3.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\disk11.mem') -Destination (Join-Path $runDir 'build\roms\disk11.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\diagnostic_cart.mem') -Destination (Join-Path $runDir 'build\roms\diagnostic_cart.mem') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3gen.mem') -Destination (Join-Path $runDir 'rtl\core\coco3gen.mem') -Force

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $path)) { throw "$Tool was not found at: $path" }
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

$sources = @(
    'rtl\third-party\PS2_Key\ps2_keyboard.v', 'rtl\third-party\coco3fpga\cocokey.v',
    'rtl\core\coco3_keyboard_matrix.v', 'rtl\core\coco3_char_rom.v',
    'rtl\core\coco3_128k_ram.v',
    'rtl\core\coco3_system_rom.v', 'rtl\core\coco3_disk_rom.v',
    'rtl\core\coco3_diagnostic_cartridge.v', 'rtl\core\coco3_disk_image.v',
    'rtl\core\sd_spi_init.v', 'rtl\core\sd_spi_read_sector0.v',
    'rtl\core\coco3_fdc.v', 'rtl\core\coco3_gime_timer.v',
    'rtl\core\coco3_boot_machine.v',
    'rtl\third-party\coco3fpga\coco3vid.v', 'rtl\wukong\uart_tx.v',
    'rtl\wukong\coco3_uart_debug.v', 'rtl\wukong\ntsc_artifact_filter.v',
    'rtl\wukong\crt_filter.v', 'rtl\wukong\coco3_boot_system.v',
    'tb\boot_video_tb.v'
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $runDir
try {
    Invoke-VivadoTool xvlog @((Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v'), (Join-Path $repoRoot 'rtl\core\cpu09.v'))
    Invoke-VivadoTool xvlog (@('-d', 'NEW_SRAM') + $sources)
    Invoke-VivadoTool xelab @('boot_video_tb', '-s', 'boot_video_tb_sim')
    Invoke-VivadoTool xsim @('boot_video_tb_sim', '-runall')
} finally {
    Pop-Location
}
