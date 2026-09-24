param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\pmod_floppy_read_only'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" `
        (Join-Path $repoRoot 'rtl\wukong\pmod_floppy_read_only.v') `
        (Join-Path $repoRoot 'tb\pmod_floppy_read_only_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & "$VivadoBin\xelab.bat" pmod_floppy_read_only_tb `
        -s pmod_floppy_read_only_sim
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    & "$VivadoBin\xsim.bat" pmod_floppy_read_only_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed: $LASTEXITCODE" }
    $pass = Select-String -Path xsim.log -SimpleMatch `
        'PASS: J13 read-only floppy telemetry, motor, and home'
    if (-not $pass) {
        throw 'J13 read-only floppy regression did not report PASS'
    }
} finally {
    Pop-Location
}
