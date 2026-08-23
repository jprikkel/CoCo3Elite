param(
    [string]$InputPath = 'roms/coco3.rom',
    [string]$OutputPath = 'build/roms/coco3.mem',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$rawSize = 32KB
$legacySize = 0x7E02

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "CoCo 3 ROM was not found at '$InputPath'. See roms/README.md."
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$inputBytes = [System.IO.File]::ReadAllBytes($resolvedInput)

$digest = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash
if ($ExpectedSha256 -and $digest -ne $ExpectedSha256.ToUpperInvariant()) {
    throw "ROM SHA-256 mismatch. Expected $($ExpectedSha256.ToUpperInvariant()), found $digest."
}

if ($inputBytes.Length -eq $rawSize) {
    $rom = $inputBytes
    $format = 'raw 32 KiB image'
} elseif ($inputBytes.Length -eq $legacySize -and
          $inputBytes[0] -eq 0x00 -and $inputBytes[1] -eq 0x80) {
    # The original CoCo3FPGA flash image begins with a little-endian $8000
    # load address and contains $8000-$FDFF. Hardware supplies $FE00-$FFEF
    # from the vector-page RAM and $FFF0-$FFFF from the FFF0 initialized RAM.
    $rom = [byte[]]::new($rawSize)
    [Array]::Copy($inputBytes, 2, $rom, 0, 0x7E00)
    [byte[]]$vectors = @(
        0x30, 0x01, 0xFE, 0xEE, 0xFE, 0xF1, 0xFE, 0xF4,
        0xFE, 0xF7, 0xFE, 0xFA, 0xFE, 0xFD, 0x8C, 0x1B
    )
    [Array]::Copy($vectors, 0, $rom, 0x7FF0, $vectors.Length)
    $format = 'legacy CoCo3FPGA $8000-$FDFF image with reconstructed vectors'
} else {
    throw "CoCo 3 ROM must be a raw $rawSize-byte image or a $legacySize-byte legacy CoCo3FPGA image with a `$8000 header; '$resolvedInput' is $($inputBytes.Length) bytes."
}

# A 32 KiB image maps to CPU addresses $8000-$FFFF. The reset vector is the
# final two bytes at $FFFE-$FFFF and must point into the internal ROM window.
$resetVector = ([int]$rom[0x7FFE] -shl 8) -bor [int]$rom[0x7FFF]
if ($resetVector -lt 0x8000) {
    throw ('ROM reset vector ${0:X4} does not point into the $8000-$FFFF ROM window.' -f $resetVector)
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

Write-Host "Prepared CoCo 3 ROM:"
Write-Host "  Input:        $resolvedInput"
Write-Host "  Format:       $format"
Write-Host "  SHA-256:      $digest"
Write-Host ('  Reset vector: ${0:X4}' -f $resetVector)
Write-Host "  Vivado image: $OutputPath"
