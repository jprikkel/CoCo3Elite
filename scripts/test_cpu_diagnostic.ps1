param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\cpu_diagnostic'

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\core') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3_diagnostic.mem') `
    -Destination (Join-Path $runDir 'rtl\core\coco3_diagnostic.mem') -Force

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

Push-Location $runDir
try {
    Invoke-VivadoTool xvhdl @('--2008', (Join-Path $repoRoot 'rtl\cpu09l_128.vhd'))
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_diagnostic_rom.v'),
        (Join-Path $repoRoot 'tb\cpu_diagnostic_tb.v')
    )
    Invoke-VivadoTool xelab @('cpu_diagnostic_tb', '-s', 'cpu_diagnostic_tb_sim')
    Invoke-VivadoTool xsim @('cpu_diagnostic_tb_sim', '-runall')
} finally {
    Pop-Location
}
