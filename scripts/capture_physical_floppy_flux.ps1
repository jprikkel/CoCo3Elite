param(
    [string]$Port = 'COM5',
    [ValidateRange(0, 1)][int]$Side = 1,
    [ValidateRange(0, 1)][int]$Direction = 1,
    [string]$OutputDirectory = 'build\test-output\floppy-flux',
    [string]$Name = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (-not $Name) {
    $Name = 'track-side{0}-dir{1}-{2}' -f $Side, $Direction,
        (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-Crc32([byte[]]$Bytes) {
    [uint32]$crc = [uint32]::MaxValue
    [uint32]$poly = [uint32]::Parse('EDB88320',
        [Globalization.NumberStyles]::HexNumber)
    foreach ($value in $Bytes) {
        $crc = [uint32]($crc -bxor [uint32]$value)
        for ($bit = 0; $bit -lt 8; $bit++) {
            $crc = if ($crc -band 1) {
                [uint32](($crc -shr 1) -bxor $poly)
            } else { [uint32]($crc -shr 1) }
        }
    }
    [uint32]($crc -bxor [uint32]::MaxValue)
}

function Read-MatchingLine {
    param([string]$Pattern, [int]$Seconds = 4)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $line = $serial.ReadLine().Trim() }
        catch [TimeoutException] { continue }
        if ($line -match $Pattern) { return $line }
        if ($line -match '^(ERR|FLUX ERROR)') { throw $line }
    }
    throw "Timed out waiting for serial response: $Pattern"
}

function Read-ExactBytes([int]$Count) {
    $bytes = [byte[]]::new($Count)
    $offset = 0
    while ($offset -lt $Count) {
        $received = $serial.Read($bytes, $offset, $Count - $offset)
        if ($received -le 0) {
            throw "Flux payload ended at byte $offset of $Count"
        }
        $offset += $received
    }
    $bytes
}

function Send-Command([string]$Command, [string]$Pattern = '^(OK|FLOPPY)') {
    $serial.Write("$Command`r")
    Read-MatchingLine $Pattern 4
}

$serial = [IO.Ports.SerialPort]::new($Port, 460800,
    [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.NewLine = "`n"
$serial.ReadTimeout = 500
$serial.WriteTimeout = 2000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$allIntervals = [Collections.Generic.List[uint16]]::new()
$chunks = [Collections.Generic.List[object]]::new()
$clockHz = 25200000.0
$offset = 0

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    Send-Command "FLOPPY SIDE $Side" | Out-Null
    Send-Command "FLOPPY DIR $Direction" | Out-Null
    Send-Command 'FLOPPY START' | Out-Null
    Start-Sleep -Milliseconds 700

    while ($true) {
        # Refresh the independent ten-second motor watchdog before every turn.
        Send-Command 'FLOPPY START' | Out-Null
        $serial.Write(("FLUX {0:X4}`r" -f $offset))
        $header = Read-MatchingLine '^FLUX BEGIN ' 4
        $pattern = '^FLUX BEGIN CLK=([0-9]{8}) SIDE=([01]) DIR=([01]) ' +
            'OFFSET=([0-9A-F]{4}) TOTAL=([0-9A-F]{4}) COUNT=([0-9A-F]{4}) ' +
            'CYCLES=([0-9A-F]{8}) MIN=([0-9A-F]{4}) MAX=([0-9A-F]{4}) ' +
            'HASH=([0-9A-F]{8})$'
        if ($header -notmatch $pattern) { throw "Invalid flux header: $header" }
        $clockHz = [uint32]$Matches[1]
        $reportedSide = [int]$Matches[2]
        $reportedDirection = [int]$Matches[3]
        $reportedOffset = [Convert]::ToUInt16($Matches[4], 16)
        $total = [Convert]::ToUInt16($Matches[5], 16)
        $count = [Convert]::ToUInt16($Matches[6], 16)
        $cycles = [Convert]::ToUInt32($Matches[7], 16)
        $minimum = [Convert]::ToUInt16($Matches[8], 16)
        $maximum = [Convert]::ToUInt16($Matches[9], 16)
        $hash = [Convert]::ToUInt32($Matches[10], 16)
        if ($reportedSide -ne $Side -or $reportedDirection -ne $Direction -or
            $reportedOffset -ne $offset) {
            throw "Flux metadata does not match the requested side/direction/offset"
        }

        $payload = Read-ExactBytes (2 * $count)
        $trailer = Read-MatchingLine '^FLUX END CRC32=([0-9A-F]{8})$' 4
        $expectedCrc = [Convert]::ToUInt32(
            ($trailer -replace '^FLUX END CRC32=', ''), 16)
        $actualCrc = Get-Crc32 $payload
        if ($actualCrc -ne $expectedCrc) {
            throw ('Flux CRC mismatch: FPGA={0:X8}, host={1:X8}' -f
                $expectedCrc, $actualCrc)
        }
        for ($n = 0; $n -lt $count; $n++) {
            $allIntervals.Add([uint16]($payload[2 * $n] -bor
                ([uint16]$payload[2 * $n + 1] -shl 8)))
        }
        $chunks.Add([pscustomobject]@{
            offset = $offset; count = $count; total = $total
            revolutionCycles = $cycles; minimum = $minimum; maximum = $maximum
            hash = ('{0:X8}' -f $hash); crc32 = ('{0:X8}' -f $actualCrc)
        })
        Write-Host ('Captured interval {0}..{1} of {2}' -f
            $offset, ($offset + $count - 1), $total)
        if ($count -eq 0 -or ($offset + $count) -ge $total) { break }
        $offset += $count
        if ($offset -gt 0xffff) { throw 'Flux interval offset exceeded 16 bits' }
    }
} finally {
    if ($serial.IsOpen) {
        try {
            Send-Command 'FLOPPY STOP' | Out-Null
        } catch { Write-Warning "Could not confirm FLOPPY STOP: $_" }
        $serial.Close()
    }
    $serial.Dispose()
}

$forward = $allIntervals.ToArray()
$reverse = [uint16[]]$forward.Clone()
[Array]::Reverse($reverse)
$raw = [byte[]]::new(2 * $forward.Length)
for ($n = 0; $n -lt $forward.Length; $n++) {
    $raw[2 * $n] = [byte]($forward[$n] -band 0xff)
    $raw[2 * $n + 1] = [byte](($forward[$n] -shr 8) -band 0xff)
}
$rawPath = Join-Path $OutputDirectory "$Name.flux16le"
$forwardPath = Join-Path $OutputDirectory "$Name-forward.csv"
$reversePath = Join-Path $OutputDirectory "$Name-reverse.csv"
$metadataPath = Join-Path $OutputDirectory "$Name.json"
[IO.File]::WriteAllBytes($rawPath, $raw)

$index = 0
$forward | ForEach-Object {
    [pscustomobject]@{ index = $index++; clocks = $_;
        microseconds = [Math]::Round(1000000.0 * $_ / $clockHz, 4) }
} | Export-Csv -NoTypeInformation -LiteralPath $forwardPath
$index = 0
$reverse | ForEach-Object {
    [pscustomobject]@{ index = $index++; clocks = $_;
        microseconds = [Math]::Round(1000000.0 * $_ / $clockHz, 4) }
} | Export-Csv -NoTypeInformation -LiteralPath $reversePath

[ordered]@{
    capturedAt = (Get-Date).ToString('o')
    port = $Port
    captureClockHz = $clockHz
    transferBaud = 460800
    side = $Side
    direction = $Direction
    intervalCount = $forward.Length
    reconstruction = 'Index-aligned chunks captured on successive revolutions'
    chunks = $chunks
    raw = $rawPath
    forwardCsv = $forwardPath
    reverseCsv = $reversePath
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8

Write-Host "PASS: captured $($forward.Length) flux intervals at 460800 baud"
Write-Host "Raw: $rawPath"
Write-Host "Forward: $forwardPath"
Write-Host "Reverse: $reversePath"
Write-Host "Metadata: $metadataPath"
