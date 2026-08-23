param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'

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

Invoke-VivadoTool xvhdl @('--2008', 'rtl/cpu09l_128.vhd')
Invoke-VivadoTool xvlog @(
    'rtl/core/coco3_128k_ram.v',
    'rtl/core/coco3_diagnostic_rom.v',
    'tb/cpu_diagnostic_tb.v'
)
Invoke-VivadoTool xelab @('cpu_diagnostic_tb', '-s', 'cpu_diagnostic_tb_sim')
Invoke-VivadoTool xsim @('cpu_diagnostic_tb_sim', '-runall')
