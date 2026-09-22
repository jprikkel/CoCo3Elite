$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\manager_disk_geometry'
$vivadoBin = 'C:\AMD\2025.2\Vivado\bin'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') -d WUKONG_HYBRID_512K `
        (Join-Path $repoRoot 'rtl\wukong\uart_tx.v') `
        (Join-Path $repoRoot 'rtl\wukong\uart_rx.v') `
        (Join-Path $repoRoot 'rtl\management\manager_sd_mmio.v') `
        (Join-Path $repoRoot 'tb\manager_disk_geometry_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $vivadoBin 'xelab.bat') manager_disk_geometry_tb `
        -s manager_disk_geometry_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    $output = & (Join-Path $vivadoBin 'xsim.bat') manager_disk_geometry_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch
        'PASS: 35-track single-sided and 40-track double-sided image geometry') {
        throw 'Disk geometry simulation failed or did not finish'
    }
} finally {
    Pop-Location
}
