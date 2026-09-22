$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\coco3_hybrid_512k_ram'
$vivadoBin = 'C:\AMD\2025.2\Vivado\bin'

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v') `
        (Join-Path $repoRoot 'rtl\wukong\coco3_hybrid_512k_ram.v') `
        (Join-Path $repoRoot 'tb\coco3_hybrid_512k_ram_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed with exit code $LASTEXITCODE" }
    & (Join-Path $vivadoBin 'xelab.bat') coco3_hybrid_512k_ram_tb `
        -s coco3_hybrid_512k_ram_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw "xelab failed with exit code $LASTEXITCODE" }
    $output = & (Join-Path $vivadoBin 'xsim.bat') coco3_hybrid_512k_ram_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch
        'PASS: shared SDRAM disk cache reaches the 360 KiB boundary') {
        throw 'Hybrid RAM simulation failed or did not reach its final PASS marker'
    }
} finally {
    Pop-Location
}
