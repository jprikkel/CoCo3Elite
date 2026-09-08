param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\gime_interrupt'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\core\coco3_gime_interrupt.v') `
        (Join-Path $repoRoot 'tb\gime_interrupt_tb.v')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $VivadoBin 'xelab.bat') gime_interrupt_tb -s gime_interrupt_tb_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    & (Join-Path $VivadoBin 'xsim.bat') gime_interrupt_tb_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
} finally { Pop-Location }
