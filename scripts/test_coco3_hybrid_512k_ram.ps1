$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\coco3_hybrid_512k_ram'
$vivadoBin = 'C:\AMD\2025.2\Vivado\bin'

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\core') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3gen.mem') `
    -Destination (Join-Path $runDir 'rtl\core\coco3gen.mem') -Force
Push-Location $runDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') -d NEW_SRAM `
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v') `
        (Join-Path $repoRoot 'rtl\core\coco3_char_rom.v') `
        (Join-Path $repoRoot 'rtl\third-party\coco3fpga\coco3vid.v') `
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
