param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin',
    [string]$CartridgePath = 'roms\ziadiag.ccc'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\diagnostic_cartridge'
$stagedRomDir = Join-Path $runDir 'build\roms'

& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\coco3.mem')
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\disk11.mem')
& (Join-Path $PSScriptRoot 'prepare_diagnostic_cartridge.ps1') `
    -InputPath (Join-Path $repoRoot $CartridgePath) `
    -OutputPath (Join-Path $repoRoot 'build\roms\diagnostic_cart.mem')

New-Item -ItemType Directory -Force -Path $stagedRomDir | Out-Null
foreach ($name in @('coco3.mem', 'disk11.mem', 'diagnostic_cart.mem')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "build\roms\$name") `
        -Destination (Join-Path $stagedRomDir $name) -Force
}

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

Push-Location $runDir
try {
    Invoke-VivadoTool xvhdl @('--2008', (Join-Path $repoRoot 'rtl\cpu09l_128.vhd'))
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_system_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_disk_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_diagnostic_cartridge.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_disk_image.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_keyboard_matrix.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_gime_timer.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_boot_machine.v'),
        (Join-Path $repoRoot 'tb\diagnostic_cartridge_trace_tb.v')
    )
    Invoke-VivadoTool xelab @('diagnostic_cartridge_trace_tb', '-s', 'diagnostic_cartridge_trace_tb_sim')
    Invoke-VivadoTool xsim @('diagnostic_cartridge_trace_tb_sim', '-runall')
} finally {
    Pop-Location
}

Write-Host "Trace: $(Join-Path $runDir 'diagnostic_cartridge_trace.log')"
