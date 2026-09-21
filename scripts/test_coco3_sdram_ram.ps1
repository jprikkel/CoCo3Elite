param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\coco3_sdram_ram'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Push-Location $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\wukong\coco3_sdram_ram.v') `
        (Join-Path $repoRoot 'tb\coco3_sdram_ram_tb.v')
    if ($LASTEXITCODE) { throw 'SDRAM controller compile failed' }

    & (Join-Path $VivadoBin 'xelab.bat') coco3_sdram_ram_tb `
        -s coco3_sdram_ram_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'SDRAM controller elaboration failed' }

    & (Join-Path $VivadoBin 'xsim.bat') coco3_sdram_ram_sim -runall
    if ($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch `
            'PASS: SDRAM preserves queued writes and aligns refresh without video deadline misses')) {
        throw 'SDRAM controller regression failed'
    }
} finally {
    Pop-Location
}
