param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\gime_border'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\core') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3gen.mem') `
    -Destination (Join-Path $runDir 'rtl\core\coco3gen.mem') -Force

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

Push-Location $runDir
try {
    Invoke-VivadoTool xvlog @(
        '-d', 'NEW_SRAM', '-d', 'HDMI_RASTER_800X525',
        (Join-Path $repoRoot 'rtl\core\coco3_char_rom.v'),
        (Join-Path $repoRoot 'rtl\coco3vid.v'),
        (Join-Path $repoRoot 'tb\gime_border_tb.v'))
    Invoke-VivadoTool xelab @('gime_border_tb', '-s', 'gime_border_sim')
    Invoke-VivadoTool xsim @('gime_border_sim', '-runall')
} finally {
    Pop-Location
}
