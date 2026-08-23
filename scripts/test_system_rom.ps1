param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath 'build/roms/coco3.mem' -PathType Leaf)) {
    & scripts/prepare_coco3_rom.ps1
}

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$Tool was not found at: $path"
    }
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE"
    }
}

Invoke-VivadoTool xvlog @(
    'rtl/core/coco3_system_rom.v',
    'tb/system_rom_tb.v'
)
Invoke-VivadoTool xelab @('system_rom_tb', '-s', 'system_rom_tb_sim')
Invoke-VivadoTool xsim @('system_rom_tb_sim', '-runall')
