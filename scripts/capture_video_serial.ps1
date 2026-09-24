param(
    [string]$Port = 'COM5',
    [int]$BaudRate = 460800,
    [string]$OutputDirectory = 'build\test-output\screenshots',
    [string]$Name = '',
    [string]$ReferencePng = '',
    [ValidateRange(0, 255)][int]$PixelTolerance = 12,
    [ValidateRange(0, 100)][double]$MaxDifferentPercent = 0.0
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (-not $Name) { $Name = 'coco3-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }

function Get-Crc32([byte[]]$Bytes) {
    [uint32]$crc = [uint32]::MaxValue
    [uint32]$poly = [uint32]::Parse('EDB88320',
        [Globalization.NumberStyles]::HexNumber)
    foreach ($value in $Bytes) {
        $crc = [uint32]($crc -bxor [uint32]$value)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crc -band 1) {
                $crc = [uint32](($crc -shr 1) -bxor $poly)
            } else {
                $crc = [uint32]($crc -shr 1)
            }
        }
    }
    return [uint32]($crc -bxor [uint32]::MaxValue)
}

function Read-MatchingLine(
    [IO.Ports.SerialPort]$Serial,
    [string]$Pattern,
    [int]$Attempts = 100
) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try { $line = $Serial.ReadLine().Trim() } catch [TimeoutException] { continue }
        if ($line -match $Pattern) { return $line }
    }
    throw "Timed out waiting for serial response: $Pattern"
}

function Read-ExactBytes(
    [IO.Ports.SerialPort]$Serial,
    [int]$Count
) {
    $bytes = [byte[]]::new($Count)
    $offset = 0
    while ($offset -lt $Count) {
        $received = $Serial.Read($bytes, $offset, $Count - $offset)
        if ($received -le 0) { throw "Serial frame ended at byte $offset of $Count" }
        $offset += $received
    }
    return $bytes
}

$serial = [IO.Ports.SerialPort]::new($Port, $BaudRate,
    [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.ReadTimeout = 1000
$serial.WriteTimeout = 2000
$serial.NewLine = "`n"
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    $serial.Write("CAPTURE`r")
    $header = Read-MatchingLine $serial `
        '^FRAME BEGIN ([0-9]+) ([0-9]+) (RGB332|RGB565) ([0-9]+)$' 15
    if ($header -notmatch '^FRAME BEGIN ([0-9]+) ([0-9]+) (RGB332|RGB565) ([0-9]+)$') {
        throw "Invalid frame header: $header"
    }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    $format = $Matches[3]
    $byteCount = [int]$Matches[4]
    $bytesPerPixel = if ($format -eq 'RGB565') { 2 } else { 1 }
    if ($byteCount -ne $width * $height * $bytesPerPixel) {
        throw "Frame byte count $byteCount does not match ${width}x${height} $format"
    }

    $raw = Read-ExactBytes $serial $byteCount
    $trailer = Read-MatchingLine $serial '^FRAME END CRC32 ([0-9A-F]{8})$' 5
    $expectedCrc = [Convert]::ToUInt32(($trailer -split ' ')[3], 16)
    $actualCrc = Get-Crc32 $raw
    if ($actualCrc -ne $expectedCrc) {
        throw ('Frame CRC mismatch: FPGA={0:X8}, host={1:X8}' -f
            $expectedCrc, $actualCrc)
    }

    Start-Sleep -Milliseconds 50
    $serial.DiscardInBuffer()
    $serial.Write("STATUS`r")
    $status = Read-MatchingLine $serial '^STATUS PC=' 10
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}

$rawPath = Join-Path $OutputDirectory ("$Name." + $format.ToLowerInvariant())
$pngPath = Join-Path $OutputDirectory "$Name.png"
$jsonPath = Join-Path $OutputDirectory "$Name.json"
[IO.File]::WriteAllBytes($rawPath, $raw)

Add-Type -AssemblyName System.Drawing
$small = [Drawing.Bitmap]::new($width, $height,
    [Drawing.Imaging.PixelFormat]::Format24bppRgb)
try {
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $index = $y * $width + $x
            if ($format -eq 'RGB565') {
                $pixel = ([int]$raw[2 * $index] -shl 8) -bor $raw[2 * $index + 1]
                $red = (($pixel -shr 11) -band 31) * 255 / 31
                $green = (($pixel -shr 5) -band 63) * 255 / 63
                $blue = ($pixel -band 31) * 255 / 31
            } else {
                $pixel = [int]$raw[$index]
                $red = (($pixel -shr 5) -band 7) * 255 / 7
                $green = (($pixel -shr 2) -band 7) * 255 / 7
                $blue = ($pixel -band 3) * 255 / 3
            }
            $small.SetPixel($x, $y, [Drawing.Color]::FromArgb(
                [int]$red, [int]$green, [int]$blue))
        }
    }

    $outputWidth = $width
    $outputHeight = $height
    $large = [Drawing.Bitmap]::new($outputWidth, $outputHeight,
        [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
        $graphics = [Drawing.Graphics]::FromImage($large)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
            $graphics.DrawImage($small, [Drawing.Rectangle]::new(
                0, 0, $outputWidth, $outputHeight))
        } finally { $graphics.Dispose() }
        $large.Save($pngPath, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $large.Dispose() }

    $differencePercent = $null
    if ($ReferencePng) {
        $referencePath = (Resolve-Path -LiteralPath $ReferencePng).Path
        $reference = [Drawing.Bitmap]::new($referencePath)
        try {
            $different = 0
            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    $expected = $reference.GetPixel(
                        [Math]::Min($reference.Width - 1,
                            [int][Math]::Floor(($x + 0.5) * $reference.Width / $width)),
                        [Math]::Min($reference.Height - 1,
                            [int][Math]::Floor(($y + 0.5) * $reference.Height / $height)))
                    $actual = $small.GetPixel($x, $y)
                    $maximumDifference = [Math]::Max(
                        [Math]::Abs($expected.R - $actual.R),
                        [Math]::Max([Math]::Abs($expected.G - $actual.G),
                            [Math]::Abs($expected.B - $actual.B)))
                    if ($maximumDifference -gt $PixelTolerance) { $different++ }
                }
            }
            $differencePercent = 100.0 * $different / ($width * $height)
        } finally { $reference.Dispose() }
    }
} finally { $small.Dispose() }

$metadata = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    port = $Port
    width = $width
    height = $height
    format = $format
    crc32 = ('{0:X8}' -f $actualCrc)
    status = $status
    png = $pngPath
    raw = $rawPath
    reference = if ($ReferencePng) { $ReferencePng } else { $null }
    differentPercent = $differencePercent
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath $jsonPath -Encoding utf8

Write-Host ('PASS: captured {0}x{1}, CRC32 {2:X8}' -f
    $width, $height, $actualCrc)
Write-Host "PNG: $pngPath"
Write-Host "Status: $status"
if ($null -ne $differencePercent) {
    Write-Host ('Reference difference: {0:N3}% (tolerance {1})' -f
        $differencePercent, $PixelTolerance)
    if ($differencePercent -gt $MaxDifferentPercent) {
        throw ('Frame differs from reference by {0:N3}%, maximum is {1:N3}%' -f
            $differencePercent, $MaxDifferentPercent)
    }
}

[pscustomobject]$metadata
