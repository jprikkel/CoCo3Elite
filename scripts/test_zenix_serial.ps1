param(
    [string]$Port = 'COM5',
    [ValidateRange(20, 1000)]
    [int]$KeyDelayMs = 140,
    [ValidateRange(5, 120)]
    [int]$MenuTimeoutSeconds = 15,
    [ValidateRange(10, 180)]
    [int]$LaunchTimeoutSeconds = 60,
    [ValidateRange(10, 300)]
    [int]$MainMenuTimeoutSeconds = 90,
    [ValidateRange(5, 300)]
    [int]$GameplaySeconds = 45,
    [ValidateRange(20, 500)]
    [int]$FirePulseMs = 60,
    [string]$OutputPath,
    [switch]$SkipBrowserRoot
)

$ErrorActionPreference = 'Stop'

$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 80
$serial.WriteTimeout = 1000
$trace = [System.Collections.Generic.List[string]]::new()

function Receive-Serial {
    param([Parameter(Mandatory)][int]$Milliseconds)

    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $Milliseconds) {
        try {
            $line = $serial.ReadLine().TrimEnd("`r")
            if ($line.Length) {
                $trace.Add($line)
                Write-Host $line
            }
        } catch [System.TimeoutException] { }
    }
}

function Send-SerialCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$WaitMilliseconds = 180
    )

    $serial.Write("$Command`n")
    Receive-Serial -Milliseconds $WaitMilliseconds
}

function Press-CoCoKey {
    param([Parameter(Mandatory)][ValidateRange(0,55)][int]$Key)

    Send-SerialCommand -Command ('KD {0:X2}' -f $Key) -WaitMilliseconds $KeyDelayMs
    Send-SerialCommand -Command ('KU {0:X2}' -f $Key) `
        -WaitMilliseconds ([Math]::Max(180, $KeyDelayMs))
}

function Press-F12 {
    # Function-key command encoding is (slot << 1) | pressed.  F12 is slot 7.
    Send-SerialCommand -Command 'FK 0F' -WaitMilliseconds $KeyDelayMs
    Send-SerialCommand -Command 'FK 0E' `
        -WaitMilliseconds ([Math]::Max(250, $KeyDelayMs))
}

function Press-F8 {
    # F8 is function-key slot 3.  The FPGA cycles joystick-keyboard mapping
    # through off, left and right; two presses from reset select right.
    Send-SerialCommand -Command 'FK 07' -WaitMilliseconds $KeyDelayMs
    Send-SerialCommand -Command 'FK 06' `
        -WaitMilliseconds ([Math]::Max(250, $KeyDelayMs))
}

function Pulse-Fire {
    Send-SerialCommand -Command 'KD 1F' -WaitMilliseconds $FirePulseMs
    Send-SerialCommand -Command 'KU 1F' -WaitMilliseconds 90
}

function Wait-ForTrace {
    param(
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Description
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        for ($index = $StartIndex; $index -lt $trace.Count; $index++) {
            if ($trace[$index] -match $Pattern) {
                return $trace[$index]
            }
        }
        Receive-Serial -Milliseconds 250
    }
    throw "Timed out waiting for $Description on $Port"
}

function Wait-ForZenixMainMenu {
    param(
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    # The patched Zenix main menu alternates between its DBB0-DBBF display
    # loop and the FE1C-FE1E interrupt service path.  Requiring several clean
    # samples prevents a transient pass while the BIN loader is still active.
    $samples = 0
    $checked = $StartIndex
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        while ($checked -lt $trace.Count) {
            $line = $trace[$checked++]
            if ($line -match '^PC=(DBB[0-9A-F]|FE1[CEF])\b' -and
                $line -match '\bG=7C205\b') {
                $samples++
                if ($samples -ge 5) {
                    return $line
                }
            }
        }
        Receive-Serial -Milliseconds 500
    }
    throw "Zenix did not reach its main-menu loop within $TimeoutSeconds seconds"
}

function Test-ZenixRuntime {
    param([Parameter(Mandatory)][int]$StartIndex)

    $runtimeLines = @($trace | Select-Object -Skip $StartIndex)
    $pcValues = [System.Collections.Generic.HashSet[string]]::new()
    $pcSamples = 0
    $validGimeSamples = 0

    foreach ($line in $runtimeLines) {
        if ($line -match '^PC=([0-9A-F]{4})\b') {
            $pcSamples++
            [void]$pcValues.Add($Matches[1])
            if ($line -match '\bG=7C205\b' -and
                $line -match '\bM=[0-9A-F]{32}\b') {
                $validGimeSamples++
            }
        }
        if ($line -match '^(CART FAULT|MOUNT ERR|COCO3 UART READY)') {
            throw "Runtime fault/reset detected: $line"
        }
    }

    if ($pcSamples -lt 10) {
        throw "Only $pcSamples runtime PC samples were captured"
    }
    if ($pcValues.Count -lt 3) {
        throw "CPU progress check failed: only $($pcValues.Count) unique PC values"
    }
    if ($validGimeSamples -lt 5) {
        throw "Only $validGimeSamples runtime samples had the expected Zenix GIME/MMU state"
    }

    $statusMarker = $trace.Count
    Send-SerialCommand -Command 'STATUS' -WaitMilliseconds 1000
    $status = Wait-ForTrace -StartIndex $statusMarker `
        -Pattern '^STATUS PC=[0-9A-F]{4} I0=7C I1=20 VM=80 VR=7E$' `
        -TimeoutSeconds 5 -Description 'valid Zenix CPU/GIME status'
    if ($status -match '^STATUS PC=A7D[3-8]') {
        throw "Zenix returned unexpectedly to the BASIC idle loop: $status"
    }

    $pingMarker = $trace.Count
    Send-SerialCommand -Command 'PING' -WaitMilliseconds 500
    Wait-ForTrace -StartIndex $pingMarker -Pattern '^PONG$' -TimeoutSeconds 5 `
        -Description 'the management processor PONG response' | Out-Null

    [pscustomobject]@{
        PcSamples = $pcSamples
        UniquePcs = $pcValues.Count
        GimeSamples = $validGimeSamples
        Status = $status
    }
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    Send-SerialCommand -Command 'RELEASE' -WaitMilliseconds 250
    if (-not $SkipBrowserRoot) {
        $rootMarker = $trace.Count
        Send-SerialCommand -Command 'ROOT' -WaitMilliseconds 250
        Wait-ForTrace -StartIndex $rootMarker -Pattern '^OK ROOT$' `
            -TimeoutSeconds 5 -Description 'browser root reset' | Out-Null
    }

    Write-Host 'STEP 1/11: Open the F12 disk browser'
    $menuMarker = $trace.Count
    Press-F12
    Receive-Serial -Milliseconds 500

    $menuEvent = Wait-ForTrace -StartIndex $menuMarker `
        -Pattern '^MENU (OPEN|CLOSE)$' -TimeoutSeconds $MenuTimeoutSeconds `
        -Description 'the disk-browser event'
    if ($menuEvent -eq 'MENU CLOSE') {
        # Make reruns deterministic if a previous interrupted test left the
        # browser open.
        $menuMarker = $trace.Count
        Press-F12
        Wait-ForTrace -StartIndex $menuMarker -Pattern '^MENU OPEN$' `
            -TimeoutSeconds $MenuTimeoutSeconds `
            -Description 'the disk browser to reopen' | Out-Null
    }

    Write-Host 'STEP 2/11: Select the bin folder (Up x3)'
    1..3 | ForEach-Object { Press-CoCoKey -Key 27 }

    Write-Host 'STEP 3/11: Open the bin folder'
    Press-CoCoKey -Key 48
    Receive-Serial -Milliseconds 750

    Write-Host 'STEP 4/11: Select the Zenix BIN (Up x2)'
    1..2 | ForEach-Object { Press-CoCoKey -Key 27 }

    Write-Host 'STEP 5/11: Launch Zenix'
    $launchMarker = $trace.Count
    Press-CoCoKey -Key 48
    $readyLine = Wait-ForTrace -StartIndex $launchMarker `
        -Pattern '^BIN READY .*ZENIX.*\.BIN EXEC [0-9A-F]{4}$' `
        -TimeoutSeconds $LaunchTimeoutSeconds `
        -Description 'the Zenix BIN READY message'
    Write-Host "Confirmed: $readyLine"

    Write-Host 'STEP 6/11: Wait for the Zenix main-menu loop'
    $menuLine = Wait-ForZenixMainMenu -StartIndex $launchMarker `
        -TimeoutSeconds $MainMenuTimeoutSeconds
    Write-Host "Zenix main menu is running ($menuLine)"

    Write-Host 'STEP 7/11: Press F8 twice for right-joystick keyboard mapping'
    Press-F8
    Press-F8

    Write-Host 'STEP 8/11: Pulse the fire button'
    Pulse-Fire

    Write-Host "STEP 9/11: Alternate left/right and fire for $GameplaySeconds seconds"
    $runtimeMarker = $trace.Count
    $gameplayTimer = [Diagnostics.Stopwatch]::StartNew()
    while ($gameplayTimer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
        Send-SerialCommand -Command 'KD 1D' -WaitMilliseconds 100
        $directionTimer = [Diagnostics.Stopwatch]::StartNew()
        while ($directionTimer.ElapsedMilliseconds -lt 900 -and
               $gameplayTimer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
            Pulse-Fire
            Receive-Serial -Milliseconds 70
        }
        Send-SerialCommand -Command 'KU 1D' -WaitMilliseconds 100

        if ($gameplayTimer.Elapsed.TotalSeconds -ge $GameplaySeconds) { break }

        Send-SerialCommand -Command 'KD 1E' -WaitMilliseconds 100
        $directionTimer.Restart()
        while ($directionTimer.ElapsedMilliseconds -lt 900 -and
               $gameplayTimer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
            Pulse-Fire
            Receive-Serial -Milliseconds 70
        }
        Send-SerialCommand -Command 'KU 1E' -WaitMilliseconds 100
    }

    Write-Host 'STEP 10/11: Stop after the timed gameplay run and release all keys'
    Send-SerialCommand -Command 'RELEASE' -WaitMilliseconds 500

    Write-Host 'STEP 11/11: Validate CPU, GIME/MMU and management-processor health'
    $health = Test-ZenixRuntime -StartIndex $runtimeMarker
    $summary = ("PASS: Zenix runtime healthy; {0} PC samples, {1} unique PCs, " +
        "{2} valid GIME/MMU samples; {3}") -f $health.PcSamples,
        $health.UniquePcs, $health.GimeSamples, $health.Status
    Write-Host $summary
} finally {
    if ($serial.IsOpen) {
        try {
            $serial.Write("RELEASE`n")
            Receive-Serial -Milliseconds 150
        } catch { }
        $serial.Close()
    }
    $serial.Dispose()

    if ($OutputPath) {
        $absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
        $parent = Split-Path -Parent $absoluteOutput
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        [System.IO.File]::WriteAllLines(
            $absoluteOutput, $trace, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Saved serial trace: $absoluteOutput"
    }
}
