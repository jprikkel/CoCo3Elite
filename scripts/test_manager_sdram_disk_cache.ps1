$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\manager_sdram_disk_cache'
$vivadoBin = 'C:\AMD\2025.2\Vivado\bin'

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\wukong\manager_sdram_disk_cache.v') `
        (Join-Path $repoRoot 'tb\manager_sdram_disk_cache_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed with exit code $LASTEXITCODE" }
    & (Join-Path $vivadoBin 'xelab.bat') manager_sdram_disk_cache_tb `
        -s manager_sdram_disk_cache_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw "xelab failed with exit code $LASTEXITCODE" }
    & (Join-Path $vivadoBin 'xsim.bat') manager_sdram_disk_cache_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
