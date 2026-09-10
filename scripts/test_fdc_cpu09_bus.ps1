param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\fdc_cpu09_bus'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Push-Location $runDir
try {
    Remove-Item -LiteralPath 'xsim.dir' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath '.Xil' -Recurse -Force -ErrorAction SilentlyContinue
    $sources = @(
        (Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v'),
        (Join-Path $repoRoot 'rtl\core\cpu09.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'tb\fdc_cpu09_bus_tb.v')
    )
    & (Join-Path $VivadoBin 'xvlog.bat') @sources
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') 'fdc_cpu09_bus_tb' '-s' 'fdc_cpu09_bus_tb_sim'
    if ($LASTEXITCODE) { throw 'xelab failed' }
    & (Join-Path $VivadoBin 'xsim.bat') 'fdc_cpu09_bus_tb_sim' '-runall'
    if ($LASTEXITCODE) { throw 'xsim failed' }
    if (-not (Select-String -LiteralPath 'xsim.log' -SimpleMatch 'PASS: cpu09 FDC reads all 256 owned-sector bytes without corruption')) {
        throw 'CPU09 FDC full-sector regression did not report PASS'
    }
} finally {
    Pop-Location
}
