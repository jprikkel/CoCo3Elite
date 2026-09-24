param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin',
    [string]$CaptureDirectory =
        'build\test-output\floppy-disks\new-drive-complete',
    [string]$DskPath =
        'disks\physical-floppy\teac-fd55bv-pro-bas.dsk',
    [ValidateRange(0,34)][int]$Track = 17
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($CaptureDirectory)) {
    $CaptureDirectory = Join-Path $repoRoot $CaptureDirectory
}
if (-not [IO.Path]::IsPathRooted($DskPath)) {
    $DskPath = Join-Path $repoRoot $DskPath
}
$fluxPath = Join-Path $CaptureDirectory ('track{0:D2}-physical-side1.flux16le' -f $Track)
if (-not (Test-Path -LiteralPath $fluxPath) -or
    -not (Test-Path -LiteralPath $DskPath)) {
    throw 'Known-good TEAC track capture and DSK are required'
}
$runDir = Join-Path $repoRoot 'build\floppy_mfm_captured_track'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$raw = [IO.File]::ReadAllBytes($fluxPath)
if ($raw.Length % 2) { throw 'Flux interval file has an odd byte count' }
$sampleLines = [Collections.Generic.List[string]]::new()
for ($offset = 0; $offset -lt $raw.Length; $offset += 2) {
    $clocks = [int]$raw[$offset] + ([int]$raw[$offset + 1] -shl 8)
    $sample = [Math]::Min(255, [Math]::Floor($clocks / 2))
    $sampleLines.Add(('{0:X2}' -f $sample))
}
$samplePath = Join-Path $runDir 'captured_samples.mem'
$sampleLines | Set-Content -LiteralPath $samplePath -Encoding ascii
('{0:X4}' -f $sampleLines.Count) | Set-Content `
    -LiteralPath (Join-Path $runDir 'captured_count.mem') -Encoding ascii
('{0:X2}' -f $Track) | Set-Content `
    -LiteralPath (Join-Path $runDir 'captured_track.mem') -Encoding ascii

$dsk = [IO.File]::ReadAllBytes($DskPath)
$trackBytes = $dsk[($Track * 18 * 256)..(($Track + 1) * 18 * 256 - 1)]
$expectedPath = Join-Path $runDir 'captured_expected.mem'
$trackBytes | ForEach-Object { '{0:X2}' -f $_ } |
    Set-Content -LiteralPath $expectedPath -Encoding ascii

Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" `
        (Join-Path $repoRoot 'rtl\wukong\floppy_mfm_track_decoder.v') `
        (Join-Path $repoRoot 'tb\floppy_mfm_captured_track_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & "$VivadoBin\xelab.bat" floppy_mfm_captured_track_tb `
        -s floppy_mfm_captured_track_sim
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    & "$VivadoBin\xsim.bat" floppy_mfm_captured_track_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed: $LASTEXITCODE" }
    $pass = Select-String -Path xsim.log -SimpleMatch `
        "PASS: captured TEAC track $Track decoded byte-for-byte"
    if (-not $pass) { throw 'Captured-track MFM regression did not report PASS' }
} finally {
    Pop-Location
}
