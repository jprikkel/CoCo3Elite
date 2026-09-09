param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'build\test-manager-sd-mmio'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path $repo 'rtl\wukong\uart_tx.v') `
        (Join-Path $repo 'rtl\management\manager_sd_mmio.v') (Join-Path $repo 'tb\manager_sd_mmio_tb.v')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') manager_sd_mmio_tb -s manager_sd_mmio_tb_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'xelab failed' }
    $output = & (Join-Path $VivadoBin 'xsim.bat') manager_sd_mmio_tb_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch 'PASS: manager SD MMIO' -or ($output -join "`n") -match 'Fatal:') { throw 'xsim failed' }
} finally { Pop-Location }
