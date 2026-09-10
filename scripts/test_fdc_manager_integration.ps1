param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'build\test-fdc-manager-integration'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repo 'rtl\wukong\uart_tx.v') `
        (Join-Path $repo 'rtl\management\manager_sd_mmio.v') `
        (Join-Path $repo 'rtl\core\coco3_fdc.v') `
        (Join-Path $repo 'tb\fdc_manager_integration_tb.v')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') -L xpm fdc_manager_integration_tb `
        -s fdc_manager_integration_tb_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'xelab failed' }
    $output = & (Join-Path $VivadoBin 'xsim.bat') `
        fdc_manager_integration_tb_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch
        'PASS: manager/FDC publishes distinct back-to-back') {
        throw 'xsim failed'
    }
} finally {
    Pop-Location
}
