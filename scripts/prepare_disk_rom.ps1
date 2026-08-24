param(
    [string]$InputPath = 'roms/disk11.rom',
    [string]$OutputPath = 'build/roms/disk11.mem'
)

$ErrorActionPreference = 'Stop'
$expectedSize = 8KB
$expectedSha1 = '10BDC5AA2D7D7F205F67B47B19003A4BD89DEFD1'

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Disk BASIC 1.1 ROM was not found at '$InputPath'. See roms/README.md."
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$rom = [System.IO.File]::ReadAllBytes($resolvedInput)
if ($rom.Length -ne $expectedSize) {
    throw "Disk BASIC 1.1 ROM must be exactly $expectedSize bytes; '$resolvedInput' is $($rom.Length) bytes."
}

$sha1 = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA1).Hash
if ($sha1 -ne $expectedSha1) {
    throw "Disk BASIC 1.1 ROM SHA-1 mismatch. Expected $expectedSha1, found $sha1."
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$hexLines = [string[]]::new($rom.Length)
for ($index = 0; $index -lt $rom.Length; $index++) {
    $hexLines[$index] = $rom[$index].ToString('X2')
}
[System.IO.File]::WriteAllLines($OutputPath, $hexLines, [System.Text.Encoding]::ASCII)

Write-Host 'Prepared Disk Extended Color BASIC 1.1 ROM:'
Write-Host "  Input:        $resolvedInput"
Write-Host "  Size:         $($rom.Length) bytes"
Write-Host "  SHA-1:        $sha1"
Write-Host "  Vivado image: $OutputPath"
