param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\floppy_mfm_track_decoder'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & "$vivadoBin\xvlog.bat" `
        (Join-Path $repoRoot 'rtl\wukong\floppy_mfm_track_decoder.v') `
        (Join-Path $repoRoot 'tb\floppy_mfm_track_decoder_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & "$vivadoBin\xelab.bat" floppy_mfm_track_decoder_tb `
        -s floppy_mfm_track_decoder_sim
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    & "$vivadoBin\xsim.bat" floppy_mfm_track_decoder_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed: $LASTEXITCODE" }
    $pass = Select-String -Path xsim.log -SimpleMatch `
        'PASS: CoCo DECB MFM track decoder and CRC'
    if (-not $pass) { throw 'MFM decoder regression did not report PASS' }
} finally {
    Pop-Location
}
