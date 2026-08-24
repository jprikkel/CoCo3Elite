param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\ps2_keyboard'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

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
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\ps2_keyboard.v'),
        (Join-Path $repoRoot 'rtl\cocokey.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_keyboard_matrix.v'),
        (Join-Path $repoRoot 'tb\ps2_keyboard_matrix_tb.v')
    )
    Invoke-VivadoTool xelab @('ps2_keyboard_matrix_tb', '-s', 'ps2_keyboard_matrix_tb_sim')
    Invoke-VivadoTool xsim @('ps2_keyboard_matrix_tb_sim', '-runall')
} finally {
    Pop-Location
}
