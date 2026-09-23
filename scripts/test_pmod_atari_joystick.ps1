param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\pmod_atari_joystick'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" `
        (Join-Path $repoRoot 'rtl\wukong\pmod_atari_joystick.v') `
        (Join-Path $repoRoot 'tb\pmod_atari_joystick_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & "$VivadoBin\xelab.bat" pmod_atari_joystick_tb -s pmod_atari_joystick_sim
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    & "$VivadoBin\xsim.bat" pmod_atari_joystick_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed: $LASTEXITCODE" }
    $pass = Select-String -Path xsim.log -SimpleMatch `
        'PASS: J10 Atari joystick inputs and second button'
    if (-not $pass) {
        throw 'J10 joystick regression did not report PASS'
    }
} finally {
    Pop-Location
}
