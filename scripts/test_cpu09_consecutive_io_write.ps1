param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\cpu09_consecutive_io_write'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v') `
        (Join-Path $repoRoot 'rtl\core\cpu09.v') `
        (Join-Path $repoRoot 'tb\cpu09_consecutive_io_write_tb.v')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') 'cpu09_consecutive_io_write_tb' `
        '-s' 'cpu09_consecutive_io_write_tb_sim'
    if ($LASTEXITCODE) { throw 'xelab failed' }
    & (Join-Path $VivadoBin 'xsim.bat') 'cpu09_consecutive_io_write_tb_sim' '-runall'
    if ($LASTEXITCODE) { throw 'xsim failed' }
    if (-not (Select-String -LiteralPath 'xsim.log' -SimpleMatch `
        'PASS: consecutive cpu09 GIME writes preserve address/data pairing')) {
        throw 'consecutive I/O write regression did not report PASS'
    }
} finally {
    Pop-Location
}
