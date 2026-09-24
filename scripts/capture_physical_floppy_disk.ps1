param(
    [string]$Port = 'COM5',
    [ValidateRange(0, 83)][int]$LastTrack = 34,
    [ValidateRange(0, 1)][int]$PhysicalSide = 1,
    [ValidateRange(0, 1)][int]$LogicalHead = 0,
    [ValidateRange(-1, 1)][int]$LogicalTrackOffset = 0,
    [ValidateRange(10, 500)][int]$TrackSettleMs = 30,
    [ValidateRange(100, 10000)][int]$MotorSpinupMs = 700,
    [ValidateRange(0, 2000)][int]$HeadLoadSettleMs = 100,
    [ValidateRange(1, 65535)][int]$MinimumIntervals = 1000,
    [ValidateRange(1, 10)][int]$RevolutionsPerTrack = 3,
    [ValidateRange(0, 5)][int]$CaptureRetries = 2,
    [switch]$AllowUnstableTrackZero,
    [string]$OutputDirectory = 'build\test-output\floppy-disks',
    [string]$Name = '',
    [switch]$Indexless,
    [switch]$AssembleOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
if (-not $Name) {
    $Name = 'coco-decb-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
}
$captureDirectory = Join-Path $OutputDirectory $Name
New-Item -ItemType Directory -Force -Path $captureDirectory | Out-Null

$transferBaud = 460800
$captureClockHz = 25200000.0
$homeDirection = 1
$awayDirection = 0
$trackCaptures = [Collections.Generic.List[object]]::new()
$failedTracks = [Collections.Generic.List[object]]::new()
$motorRefreshTimer = $null

function Get-Crc32([byte[]]$Bytes) {
    [uint32]$crc = [uint32]::MaxValue
    [uint32]$poly = [uint32]::Parse(
        'EDB88320', [Globalization.NumberStyles]::HexNumber)
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

function Start-Or-RefreshMotor([int]$SettleMs) {
    Send-Command 'FLOPPY START' | Out-Null
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
    $script:motorRefreshTimer = [Diagnostics.Stopwatch]::StartNew()
}

function Ensure-MotorWatchdog {
    # Refresh with three seconds of margin on the independent ten-second FPGA
    # watchdog. Do not cycle select on every track: older mechanisms unload
    # their head whenever drive-select drops.
    if (-not $script:motorRefreshTimer -or
        $script:motorRefreshTimer.Elapsed.TotalSeconds -ge 4.0) {
        Start-Or-RefreshMotor $HeadLoadSettleMs
    }
}

function Home-Drive {
    Send-Command "FLOPPY DIR $homeDirection" | Out-Null
    $before = Send-Command 'FLOPPY'
    if ($before -notmatch 'DONE=([01])') { throw 'HOME status lacks DONE state' }
    $doneBefore = $Matches[1]
    Send-Command 'FLOPPY HOME' | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $status = Send-Command 'FLOPPY'
        if ($status -match 'TRACK0=([01]).*HOME=0 DONE=([01]) OK=([01]) STEPS=([0-9A-Fa-f]{2})' -and
            $Matches[2] -ne $doneBefore) {
            if ($Matches[3] -ne '1') {
                throw "HOME failed: $status"
            }
            if ($Matches[1] -ne '1' -and -not $AllowUnstableTrackZero) {
                throw "HOME completed without a stable TRACK0 signal: $status"
            }
            if ($Matches[1] -ne '1') {
                Write-Warning ('HOME used its latched success because the ' +
                    'live TRACK0 signal is unstable')
            }
            return
        }
    }
    throw 'HOME timed out'
}

function Capture-Track([int]$Track) {
    $allIntervals = [Collections.Generic.List[uint16]]::new()
    $revolutions = [Collections.Generic.List[object]]::new()
    $chunks = [Collections.Generic.List[object]]::new()
    $revolutionSamples = [Collections.Generic.List[uint32]]::new()
    for ($revolution = 0; $revolution -lt $RevolutionsPerTrack; $revolution++) {
        $trackIntervals = [Collections.Generic.List[uint16]]::new()
        if ($Indexless) {
            Ensure-MotorWatchdog
            $serial.Write("FLUX BULK`r")
        } else {
            Ensure-MotorWatchdog
            $serial.Write("FLUX TRACK`r")
        }
        $header = Read-MatchingLine '^FLUX BULK BEGIN ' 8
        $pattern = '^FLUX BULK BEGIN CLK=([0-9]{8}) SCALE=([0-9]+) ' +
            'INDEXED=([01]) SIDE=([01]) DIR=([01]) COUNT=([0-9A-F]{4}) ' +
            'CYCLES=([0-9A-F]{8}) MIN=([0-9A-F]{4}) ' +
            'MAX=([0-9A-F]{4}) HASH=([0-9A-F]{8})$'
        if ($header -notmatch $pattern) { throw "Invalid bulk flux header: $header" }
        $clockHz = [uint32]$Matches[1]
        $scale = [int]$Matches[2]
        $indexed = [int]$Matches[3]
        $reportedSide = [int]$Matches[4]
        $reportedDirection = [int]$Matches[5]
        $count = [Convert]::ToUInt16($Matches[6], 16)
        $cycles = [Convert]::ToUInt32($Matches[7], 16)
        $minimum = [Convert]::ToUInt16($Matches[8], 16)
        $maximum = [Convert]::ToUInt16($Matches[9], 16)
        $hash = [Convert]::ToUInt32($Matches[10], 16)
        if ($clockHz -ne [uint32]$captureClockHz -or $scale -ne 2 -or
            $indexed -ne [int](-not $Indexless) -or
            $reportedSide -ne $PhysicalSide -or
            $reportedDirection -ne $awayDirection) {
            throw "Bulk flux metadata mismatch on track $Track"
        }
        $payload = Read-ExactBytes $count
        $trailer = Read-MatchingLine '^FLUX BULK END CRC32=([0-9A-F]{8})$' 8
        $expectedCrc = [Convert]::ToUInt32(
            ($trailer -replace '^FLUX BULK END CRC32=', ''), 16)
        $actualCrc = Get-Crc32 $payload
        if ($actualCrc -ne $expectedCrc) {
            throw ('Bulk flux CRC mismatch on track {0}: FPGA={1:X8}, host={2:X8}' -f
                $Track, $expectedCrc, $actualCrc)
        }
        foreach ($sample in $payload) {
            if ($sample) {
                $interval = [uint16]($sample * $scale)
                $trackIntervals.Add($interval)
                $allIntervals.Add($interval)
            }
        }
        $revolutionSamples.Add($cycles)
        $revolutions.Add([pscustomobject]@{
            intervals = $trackIntervals.ToArray()
            cycles = $cycles
        })
        $chunks.Add([pscustomobject]@{
            revolution = $revolution; offset = 0
            count = $count; reportedTotal = $count
            revolutionCycles = $cycles; minimum = $minimum; maximum = $maximum
            scale = $scale; indexed = [bool]$indexed
            hash = ('{0:X8}' -f $hash)
            crc32 = ('{0:X8}' -f $actualCrc)
        })
    }

    [uint64]$cycleTotal = 0
    foreach ($sample in $revolutionSamples) { $cycleTotal += $sample }
    $averageCycles = [uint32][Math]::Round(
        [double]$cycleTotal / [double]$revolutionSamples.Count)
    $intervals = $allIntervals.ToArray()
    if ($intervals.Length -lt $MinimumIntervals) {
        throw ('Only {0} flux intervals were captured; at least {1} are ' +
            'required to reject disconnected-head noise') -f
            $intervals.Length, $MinimumIntervals
    }
    $raw = [byte[]]::new(2 * $intervals.Length)
    for ($n = 0; $n -lt $intervals.Length; $n++) {
        $raw[2 * $n] = [byte]($intervals[$n] -band 0xff)
        $raw[2 * $n + 1] = [byte](($intervals[$n] -shr 8) -band 0xff)
    }
    $prefix = 'track{0:D2}-physical-side{1}' -f $Track, $PhysicalSide
    $rawPath = Join-Path $captureDirectory "$prefix.flux16le"
    $metadataPath = Join-Path $captureDirectory "$prefix.json"
    [IO.File]::WriteAllBytes($rawPath, $raw)
    [ordered]@{
        track = $Track
        physicalSide = $PhysicalSide
        logicalHead = $LogicalHead
        captureClockHz = [uint32]$captureClockHz
        transferBaud = $transferBaud
        intervalCount = $intervals.Length
        revolutions = $RevolutionsPerTrack
        averageRevolutionCycles = $averageCycles
        reconstruction = if ($Indexless) {
            'One uninterrupted 205 ms indexless capture; two-clock interval units'
        } else {
            'One contiguous index-to-index capture; two-clock interval units'
        }
        chunks = $chunks
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8

    [pscustomobject]@{
        track = $Track
        logicalTrack = 2 * ($Track + $LogicalTrackOffset) + $LogicalHead
        intervals = $intervals
        revolutions = $revolutions.ToArray()
        revolutionCycles = $averageCycles
        raw = $rawPath
        metadata = $metadataPath
    }
}

function Convert-ToScpWords([uint16[]]$Intervals) {
    $words = [Collections.Generic.List[uint16]]::new()
    foreach ($interval in $Intervals) {
        [uint64]$scaled = [uint64][Math]::Round(
            [double]$interval * 1000000000.0 / $captureClockHz / 25.0)
        while ($scaled -gt 65535) {
            $words.Add([uint16]0)
            $scaled -= 65536
        }
        if ($scaled -eq 0) { $scaled = 1 }
        $words.Add([uint16]$scaled)
    }
    $words.ToArray()
}

function New-ScpImage([string]$Path) {
    $trackBlobs = [Collections.Generic.SortedDictionary[int, byte[]]]::new()
    foreach ($capture in $trackCaptures) {
        $trackStream = [IO.MemoryStream]::new()
        $writer = [IO.BinaryWriter]::new($trackStream)
        try {
            $writer.Write([Text.Encoding]::ASCII.GetBytes('TRK'))
            $writer.Write([byte]$capture.logicalTrack)
            $wordSets = [Collections.Generic.List[object]]::new()
            $dataOffset = 4 + 12 * $capture.revolutions.Count
            foreach ($revolution in $capture.revolutions) {
                $words = Convert-ToScpWords $revolution.intervals
                $wordSets.Add($words)
                $indexUnits = [uint32][Math]::Round(
                    [double]$revolution.cycles * 1000000000.0 /
                    $captureClockHz / 25.0)
                $writer.Write($indexUnits)
                $writer.Write([uint32]$words.Length)
                $writer.Write([uint32]$dataOffset)
                $dataOffset += 2 * $words.Length
            }
            foreach ($words in $wordSets) {
                foreach ($word in $words) {
                    $writer.Write([byte](($word -shr 8) -band 0xff))
                    $writer.Write([byte]($word -band 0xff))
                }
            }
            $writer.Flush()
            $trackBlobs[[int]$capture.logicalTrack] = $trackStream.ToArray()
        } finally {
            $writer.Dispose()
            $trackStream.Dispose()
        }
    }

    $header = [byte[]]::new(0x2b0)
    $header[0] = [byte][char]'S'
    $header[1] = [byte][char]'C'
    $header[2] = [byte][char]'P'
    $header[3] = 0x25 # SCP image-format revision represented by this writer.
    $header[4] = 0x41 # Tandy single-sided double-density.
    $header[5] = [byte]$RevolutionsPerTrack
    $header[6] = [byte]$LogicalHead
    $header[7] = [byte](2 * ($LastTrack + $LogicalTrackOffset) + $LogicalHead)
    $header[8] = if ($Indexless) { 0x80 } else { 0x81 }
    # 48 TPI, 300 RPM, third-party creator; bit zero marks index-cued data.
    $header[9] = 0    # 16-bit flux entries.
    $header[10] = if ($LogicalHead -eq 0) { 1 } else { 2 }
    $header[11] = 0   # 25 ns SCP resolution.

    $fileOffset = $header.Length
    foreach ($entry in $trackBlobs.GetEnumerator()) {
        [BitConverter]::GetBytes([uint32]$fileOffset).CopyTo(
            $header, 0x10 + 4 * [int]$entry.Key)
        $fileOffset += $entry.Value.Length
    }

    $imageStream = [IO.MemoryStream]::new()
    try {
        $imageStream.Write($header, 0, $header.Length)
        foreach ($entry in $trackBlobs.GetEnumerator()) {
            $imageStream.Write($entry.Value, 0, $entry.Value.Length)
        }
        $image = $imageStream.ToArray()
    } finally {
        $imageStream.Dispose()
    }
    [uint64]$checksum = 0
    for ($n = 0x10; $n -lt $image.Length; $n++) {
        $checksum = ($checksum + $image[$n]) -band 0xffffffffL
    }
    [BitConverter]::GetBytes([uint32]$checksum).CopyTo($image, 0x0c)
    [IO.File]::WriteAllBytes($Path, $image)
}

$captureError = $null
if ($AssembleOnly) {
    for ($track = 0; $track -le $LastTrack; $track++) {
        $prefix = 'track{0:D2}-physical-side{1}' -f $track, $PhysicalSide
        $rawPath = Join-Path $captureDirectory "$prefix.flux16le"
        $metadataPath = Join-Path $captureDirectory "$prefix.json"
        if ((Test-Path -LiteralPath $rawPath) -and
            (Test-Path -LiteralPath $metadataPath)) {
            $raw = [IO.File]::ReadAllBytes($rawPath)
            if (($raw.Length -band 1) -ne 0) {
                throw "Odd-length native flux file: $rawPath"
            }
            $intervals = [uint16[]]::new($raw.Length / 2)
            for ($n = 0; $n -lt $intervals.Length; $n++) {
                $intervals[$n] = [uint16]($raw[2 * $n] -bor
                    ([uint16]$raw[2 * $n + 1] -shl 8))
            }
            $metadata = Get-Content -Raw -LiteralPath $metadataPath |
                ConvertFrom-Json
            $savedRevolutions = [Collections.Generic.List[object]]::new()
            $cursor = 0
            foreach ($chunk in $metadata.chunks) {
                $savedIntervals = [uint16[]]::new([int]$chunk.count)
                for ($sample = 0; $sample -lt $savedIntervals.Length; $sample++) {
                    $savedIntervals[$sample] = $intervals[$cursor + $sample]
                }
                $cursor += $savedIntervals.Length
                $savedRevolutions.Add([pscustomobject]@{
                    intervals = $savedIntervals
                    cycles = [uint32]$chunk.revolutionCycles
                })
            }
            $capture = [pscustomobject]@{
                track = $track
                logicalTrack = 2 * ($track + $LogicalTrackOffset) + $LogicalHead
                intervals = $intervals
                revolutions = $savedRevolutions.ToArray()
                revolutionCycles = [uint32]$metadata.averageRevolutionCycles
                raw = $rawPath
                metadata = $metadataPath
            }
            $trackCaptures.Add($capture)
            Write-Host ('TRACK {0:D2}: loaded {1} intervals' -f
                $track, $intervals.Length)
        } else {
            $failedTracks.Add([pscustomobject]@{
                track = $track
                error = 'No saved native flux capture'
            })
            Write-Warning ('TRACK {0:D2}: no saved native flux capture' -f $track)
        }
    }
} else {
    $serial = [IO.Ports.SerialPort]::new($Port, $transferBaud,
        [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
    $serial.NewLine = "`n"
    $serial.ReadTimeout = 500
    $serial.WriteTimeout = 2000
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false

    try {
        $serial.Open()
        Start-Sleep -Milliseconds 100
        $serial.DiscardInBuffer()
        Home-Drive
        Send-Command "FLOPPY SIDE $PhysicalSide" | Out-Null
        Send-Command "FLOPPY DIR $awayDirection" | Out-Null
        Start-Or-RefreshMotor $MotorSpinupMs

        for ($track = 0; $track -le $LastTrack; $track++) {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $capture = $null
            $lastCaptureError = $null
            for ($attempt = 0; $attempt -le $CaptureRetries; $attempt++) {
                try {
                    $capture = Capture-Track $track
                    break
                } catch {
                    $lastCaptureError = $_
                    $serial.DiscardInBuffer()
                    if ($attempt -lt $CaptureRetries) {
                        Write-Warning ('TRACK {0:D2}: capture attempt {1} failed; ' +
                            'retrying without stepping ({2})' -f
                            $track, ($attempt + 1), $_.Exception.Message)
                        Ensure-MotorWatchdog
                        Start-Sleep -Milliseconds 50
                    }
                }
            }
            $timer.Stop()
            if ($capture) {
                $trackCaptures.Add($capture)
                Write-Host ('TRACK {0:D2}: {1} intervals, {2:F1} ms, {3:F1} s' -f
                    $track, $capture.intervals.Length,
                    (1000.0 * $capture.revolutionCycles / $captureClockHz),
                    $timer.Elapsed.TotalSeconds)
            } else {
                $failedTracks.Add([pscustomobject]@{
                    track = $track
                    error = $lastCaptureError.Exception.Message
                })
                Write-Warning ('TRACK {0:D2}: no usable flux ({1})' -f
                    $track, $lastCaptureError.Exception.Message)
                $serial.DiscardInBuffer()
            }
            if ($track -lt $LastTrack) {
                Ensure-MotorWatchdog
                Send-Command 'FLOPPY STEP' | Out-Null
                Start-Sleep -Milliseconds $TrackSettleMs
            }
        }
    } catch {
        $captureError = $_
    } finally {
        if ($serial.IsOpen) {
            try { Send-Command 'FLOPPY STOP' | Out-Null }
            catch { Write-Warning "Could not confirm FLOPPY STOP: $_" }
            $serial.Close()
        }
        $serial.Dispose()
    }
}

$manifestPath = Join-Path $captureDirectory "$Name.json"
[ordered]@{
    capturedAt = (Get-Date).ToString('o')
    port = $Port
    transferBaud = $transferBaud
    format = if ($Indexless) {
        'CoCo DECB 35-track single-sided double-density, indexless timed capture'
    } else {
        'CoCo DECB 35-track single-sided double-density'
    }
    physicalSide = $PhysicalSide
    logicalHead = $LogicalHead
    logicalTrackOffset = $LogicalTrackOffset
    motorSpinupMs = $MotorSpinupMs
    headLoadSettleMs = $HeadLoadSettleMs
    allowUnstableTrackZero = [bool]$AllowUnstableTrackZero
    revolutionsPerTrack = $RevolutionsPerTrack
    captureRetries = $CaptureRetries
    requestedTracks = $LastTrack + 1
    completedTracks = $trackCaptures.Count
    failedTracks = @($failedTracks)
    status = if ($captureError -or $trackCaptures.Count -eq 0) { 'FAILED' }
        elseif ($failedTracks.Count) { 'CAPTURED_WITH_MISSING_TRACKS' }
        else { 'CAPTURED' }
    tracks = @($trackCaptures | ForEach-Object {
        [ordered]@{
            track = $_.track
            logicalTrack = $_.logicalTrack
            intervals = $_.intervals.Length
            revolutionCycles = $_.revolutionCycles
            raw = $_.raw
            metadata = $_.metadata
        }
    })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if ($captureError) { throw $captureError }
if ($trackCaptures.Count -eq 0) {
    throw "No tracks contained at least $MinimumIntervals usable flux intervals"
}

$scpPath = Join-Path $captureDirectory "$Name.scp"
New-ScpImage $scpPath
if ($failedTracks.Count) {
    Write-Host "PARTIAL: captured $($trackCaptures.Count) tracks"
    Write-Warning "$($failedTracks.Count) track(s) had no usable flux"
} else {
    Write-Host "PASS: captured $($trackCaptures.Count) tracks"
}
Write-Host "SCP: $scpPath"
Write-Host "Manifest: $manifestPath"
