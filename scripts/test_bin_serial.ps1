param(
    [Parameter(Mandatory)][ValidateRange(1,64)][int]$ItemUpCount,
    [Parameter(Mandatory)][string]$ExpectedFile,
    [Parameter(Mandatory)][string]$Name,
    [string]$Port = 'COM5',
    [ValidatePattern('^[0-9E]*$')][string]$StartupChoices = '',
    [ValidateRange(10,300)][int]$GameplaySeconds = 45,
    [string]$OutputDirectory = 'build\test-output\hybrid-512k-games',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$safeName = $Name -replace '[^A-Za-z0-9._-]', '-'
$tracePath = Join-Path $OutputDirectory "$safeName.log"

$serial = [IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 80
$serial.WriteTimeout = 1000
$trace = [Collections.Generic.List[string]]::new()

function Receive-Serial([int]$Milliseconds) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $Milliseconds) {
        try {
            $line = $serial.ReadLine().TrimEnd("`r")
            if ($line.Length) {
                $trace.Add($line)
                if (-not $Quiet) { Write-Host $line }
            }
        } catch [TimeoutException] { }
    }
}

function Send-SerialCommand([string]$Command, [int]$WaitMilliseconds = 160) {
    $serial.Write("$Command`n")
    Receive-Serial $WaitMilliseconds
}

function Wait-ForTrace(
    [int]$StartIndex,
    [string]$Pattern,
    [int]$TimeoutSeconds,
    [string]$Description
) {
    $checked = $StartIndex
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        while ($checked -lt $trace.Count) {
            $line = $trace[$checked++]
            if ($line -match $Pattern) { return $line }
        }
        Receive-Serial 250
    }
    throw "Timed out waiting for $Description"
}

function Press-CoCoKey([int]$Key) {
    Send-SerialCommand ('KD {0:X2}' -f $Key) 120
    Send-SerialCommand ('KU {0:X2}' -f $Key) 170
}

function Press-FunctionKey([int]$Slot) {
    Send-SerialCommand ('FK {0:X2}' -f (($Slot -shl 1) -bor 1)) 120
    Send-SerialCommand ('FK {0:X2}' -f ($Slot -shl 1)) 220
}

function Pulse-Fire {
    Send-SerialCommand 'KD 1F' 55
    Send-SerialCommand 'KU 1F' 65
}

try {
    $serial.Open()
    Receive-Serial 120
    Send-SerialCommand 'RELEASE' 220
    $resetMarker = $trace.Count
    Send-SerialCommand 'RESET' 300
    Wait-ForTrace $resetMarker '^OK RESET$' 5 'reset acknowledgement' | Out-Null
    Receive-Serial 2500

    $rootMarker = $trace.Count
    Send-SerialCommand 'ROOT' 220
    Wait-ForTrace $rootMarker '^OK ROOT$' 5 'browser root reset' | Out-Null

    $menuMarker = $trace.Count
    Press-FunctionKey 7
    $menuEvent = Wait-ForTrace $menuMarker '^MENU (OPEN|CLOSE)$' 15 'F12 menu event'
    if ($menuEvent -eq 'MENU CLOSE') {
        $menuMarker = $trace.Count
        Press-FunctionKey 7
        Wait-ForTrace $menuMarker '^MENU OPEN$' 15 'F12 menu reopening' | Out-Null
    }

    # BIN is three Up presses from the initial root selection.
    1..3 | ForEach-Object { Press-CoCoKey 27 }
    Press-CoCoKey 48
    Receive-Serial 500
    1..$ItemUpCount | ForEach-Object { Press-CoCoKey 27 }

    $launchMarker = $trace.Count
    Press-CoCoKey 48
    $escapedFile = [regex]::Escape($ExpectedFile)
    $loaded = Wait-ForTrace $launchMarker `
        "^BIN READY .*${escapedFile}.* EXEC [0-9A-F]{4}$" 60 'BIN load confirmation'
    Write-Host "CONFIRMED $loaded"
    Wait-ForTrace $launchMarker '^BIN STARTED$' 60 'BIN start confirmation' | Out-Null
    Receive-Serial 5000

    foreach ($choice in $StartupChoices.ToCharArray()) {
        if ($choice -eq 'E') {
            Press-CoCoKey 48
        } else {
            Press-CoCoKey (32 + [int][string]$choice)
        }
        Receive-Serial 4000
    }

    # Exercise all joystick-keyboard mapping states so both left- and
    # right-joystick games receive movement and fire regardless of prior state.
    1..3 | ForEach-Object {
        Press-FunctionKey 3
        foreach ($direction in @(29,30)) {
            Send-SerialCommand ('KD {0:X2}' -f $direction) 80
            Pulse-Fire
            Send-SerialCommand ('KU {0:X2}' -f $direction) 80
        }
    }
    1..6 | ForEach-Object { Pulse-Fire; Receive-Serial 100 }

    $runtimeMarker = $trace.Count
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $nextJoystickCycle = 10.0
    while ($timer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
        if ($timer.Elapsed.TotalSeconds -ge $nextJoystickCycle) {
            Press-FunctionKey 3
            $nextJoystickCycle += 10.0
        }
        foreach ($direction in @(29,30)) {
            if ($timer.Elapsed.TotalSeconds -ge $GameplaySeconds) { break }
            Send-SerialCommand ('KD {0:X2}' -f $direction) 65
            $directionTimer = [Diagnostics.Stopwatch]::StartNew()
            while ($directionTimer.ElapsedMilliseconds -lt 800 -and
                   $timer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
                Pulse-Fire
                Receive-Serial 35
            }
            Send-SerialCommand ('KU {0:X2}' -f $direction) 65
        }
    }
    Send-SerialCommand 'RELEASE' 500

    $statusMarker = $trace.Count
    Send-SerialCommand 'STATUS' 700
    $status = Wait-ForTrace $statusMarker '^STATUS PC=[0-9A-F]{4} ' 5 'final status'
    $runtimeLines = @($trace | Select-Object -Skip $runtimeMarker)
    $pcs = [Collections.Generic.HashSet[string]]::new()
    $pcSamples = 0
    $gimeSamples = 0
    $faults = [Collections.Generic.List[string]]::new()
    foreach ($line in $runtimeLines) {
        if ($line -match '^PC=([0-9A-F]{4})\b') {
            $pcSamples++
            [void]$pcs.Add($Matches[1])
            if ($line -match '\bG=[0-9A-F]{5}\b' -and
                $line -match '\bM=[0-9A-F]{32}\b') { $gimeSamples++ }
        }
        if ($line -match '^(CART FAULT|MOUNT ERR|COCO3 UART READY)') {
            $faults.Add($line)
        }
    }
    $health = if ($faults.Count -or $status -match '^STATUS PC=A7D[3-8]') {
        'FAIL'
    } elseif ($pcSamples -lt 8 -or $pcs.Count -lt 2 -or $gimeSamples -lt 8) {
        'WARN'
    } else {
        'PASS'
    }
    Write-Host ("RESULT {0} name={1} samples={2} unique={3} gime={4} status='{5}' faults={6}" -f `
        $health, $Name, $pcSamples, $pcs.Count, $gimeSamples, $status, $faults.Count)
} finally {
    if ($serial.IsOpen) {
        try { $serial.Write("RELEASE`n"); Receive-Serial 120 } catch { }
        $serial.Close()
    }
    $serial.Dispose()
    [IO.File]::WriteAllLines($tracePath, $trace, [Text.UTF8Encoding]::new($false))
    Write-Host "TRACE $tracePath"
}

& (Join-Path $PSScriptRoot 'capture_video_serial.ps1') `
    -Port $Port -OutputDirectory $OutputDirectory -Name $safeName
if ($LASTEXITCODE) { throw "Screenshot capture failed: $LASTEXITCODE" }
