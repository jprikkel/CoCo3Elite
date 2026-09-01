param(
    [string]$InputPath = 'roms\ziadiag.ccc',
    [string]$OutputPath = 'build\roms\diagnostic_cart.mem'
)

$ErrorActionPreference = 'Stop'
$supportedSizes = @(2KB, 4KB, 8KB)

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Diagnostic cartridge image was not found at '$InputPath'."
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$rom = [System.IO.File]::ReadAllBytes($resolvedInput)
if ($rom.Length -notin $supportedSizes) {
    throw "Diagnostic cartridge must be 2, 4, or 8 KiB; '$resolvedInput' is $($rom.Length) bytes."
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$mappedSize = 8KB
$hexLines = [string[]]::new($mappedSize)
for ($index = 0; $index -lt $mappedSize; $index++) {
    # Smaller physical ROMs repeat throughout the 8 KiB cartridge window.
    $hexLines[$index] = $rom[$index % $rom.Length].ToString('X2')
}
[System.IO.File]::WriteAllLines($OutputPath, $hexLines, [System.Text.Encoding]::ASCII)

$sha256 = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash
Write-Host 'Prepared diagnostic cartridge:'
Write-Host "  Input:        $resolvedInput"
Write-Host "  Size:         $($rom.Length) bytes"
Write-Host "  Mapped size:  $mappedSize bytes"
Write-Host "  SHA-256:      $sha256"
Write-Host "  Vivado image: $OutputPath"
