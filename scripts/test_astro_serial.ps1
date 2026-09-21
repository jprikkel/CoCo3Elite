param(
    [string]$Port = 'COM5',
    [ValidateRange(20, 1000)][int]$KeyDelayMs = 140,
    [ValidateRange(5, 120)][int]$MenuTimeoutSeconds = 15,
    [ValidateRange(10, 180)][int]$LaunchTimeoutSeconds = 60,
    [ValidateRange(5, 120)][int]$MainMenuDelaySeconds = 15,
    [ValidateRange(10, 300)][int]$GameplaySeconds = 45,
    [ValidateRange(20, 500)][int]$FirePulseMs = 60,
    [string]$OutputPath = 'build\test-output\astro-serial.log',
    [string]$ScreenshotName = 'astro-after-45-seconds',
    [switch]$SkipBrowserRoot,
    [switch]$SkipScreenshot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$serial = [IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 80
$serial.WriteTimeout = 1000
$trace = [Collections.Generic.List[string]]::new()
$completed = $false

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
        } catch [TimeoutException] { }
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

    Send-SerialCommand -Command ('KD {0:X2}' -f $Key) `
        -WaitMilliseconds $KeyDelayMs
    Send-SerialCommand -Command ('KU {0:X2}' -f $Key) `
        -WaitMilliseconds ([Math]::Max(180, $KeyDelayMs))
}

function Press-FunctionKey {
    param([Parameter(Mandatory)][ValidateRange(0,7)][int]$Slot)

    Send-SerialCommand -Command ('FK {0:X2}' -f (($Slot -shl 1) -bor 1)) `
        -WaitMilliseconds $KeyDelayMs
    Send-SerialCommand -Command ('FK {0:X2}' -f ($Slot -shl 1)) `
        -WaitMilliseconds ([Math]::Max(250, $KeyDelayMs))
}

function Pulse-Fire {
    Send-SerialCommand -Command 'KD 1F' -WaitMilliseconds $FirePulseMs
    Send-SerialCommand -Command 'KU 1F' -WaitMilliseconds 70
}

function Wait-ForTrace {
    param(
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Description
    )

    $checked = $StartIndex
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        while ($checked -lt $trace.Count) {
            $line = $trace[$checked++]
            if ($line -match $Pattern) { return $line }
        }
        Receive-Serial -Milliseconds 250
    }
    throw "Timed out waiting for $Description on $Port"
}

function Assert-AstroMainMenu {
    param([Parameter(Mandatory)][int]$StartIndex)

    Write-Host "Waiting $MainMenuDelaySeconds seconds for the Astro main-menu loop"
    Receive-Serial -Milliseconds ($MainMenuDelaySeconds * 1000)

    $lines = @($trace | Select-Object -Skip $StartIndex)
    $pcs = [Collections.Generic.HashSet[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^PC=([0-9A-F]{4})\b') {
            $pc = $Matches[1]
            if ($pc -notmatch '^A7D[3-8]$' -and $pc -notmatch '^C0[0-9A-F]{2}$') {
                [void]$pcs.Add($pc)
            }
        }
        if ($line -match '^(CART FAULT|MOUNT ERR)') {
            throw "Astro startup fault/reset detected: $line"
        }
    }
    if ($pcs.Count -lt 2) {
        throw "Astro did not establish a live main-menu loop ($($pcs.Count) unique PCs)"
    }

    $marker = $trace.Count
    Send-SerialCommand -Command 'STATUS' -WaitMilliseconds 800
    $status = Wait-ForTrace -StartIndex $marker -Pattern '^STATUS PC=[0-9A-F]{4} ' `
        -TimeoutSeconds 5 -Description 'Astro main-menu status'
    if ($status -match '^STATUS PC=A7D[3-8]') {
        throw "Astro returned to BASIC instead of its main menu: $status"
    }
    Write-Host "Astro main menu is active ($status)"
}

function Test-AstroRuntime {
    param([Parameter(Mandatory)][int]$StartIndex)

    $lines = @($trace | Select-Object -Skip $StartIndex)
    $pcs = [Collections.Generic.HashSet[string]]::new()
    $pcSamples = 0
    $stackSamples = 0
    $gimeSamples = 0

    foreach ($line in $lines) {
        if ($line -match '^PC=([0-9A-F]{4})\b') {
            $pcSamples++
            [void]$pcs.Add($Matches[1])
            if ($line -match '\bS=([0-9A-F]{2})\b') {
                $stackPage = [Convert]::ToInt32($Matches[1], 16)
                if ($stackPage -ge 0x70 -and $stackPage -le 0xBF) {
                    $stackSamples++
                }
            }
            if ($line -match '\bG=[0-9A-F]{5}\b' -and
                $line -match '\bM=[0-9A-F]{32}\b') {
                $gimeSamples++
            }
        }
        if ($line -match '^(CART FAULT|MOUNT ERR|COCO3 UART READY)') {
            throw "Astro runtime fault/reset detected: $line"
        }
    }

    if ($pcSamples -lt 10) { throw "Only $pcSamples runtime PC samples were captured" }
    if ($pcs.Count -lt 3) { throw "CPU progress failed: only $($pcs.Count) unique PCs" }
    if ($stackSamples -lt 8) {
        throw "Only $stackSamples runtime samples had a plausible 6809 stack page"
    }
    if ($gimeSamples -lt 8) {
        throw "Only $gimeSamples runtime samples included complete GIME/MMU state"
    }

    $marker = $trace.Count
    Send-SerialCommand -Command 'STATUS' -WaitMilliseconds 800
    $status = Wait-ForTrace -StartIndex $marker -Pattern '^STATUS PC=[0-9A-F]{4} ' `
        -TimeoutSeconds 5 -Description 'final Astro status'
    if ($status -match '^STATUS PC=A7D[3-8]') {
        throw "Astro returned unexpectedly to BASIC: $status"
    }

    $marker = $trace.Count
    Send-SerialCommand -Command 'PING' -WaitMilliseconds 400
    Wait-ForTrace -StartIndex $marker -Pattern '^PONG$' -TimeoutSeconds 5 `
        -Description 'management processor PONG' | Out-Null

    [pscustomobject]@{
        PcSamples = $pcSamples
        UniquePcs = $pcs.Count
        StackSamples = $stackSamples
        GimeSamples = $gimeSamples
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

    Write-Host 'STEP 1/12: Open the F12 disk browser'
    $marker = $trace.Count
    Press-FunctionKey -Slot 7
    $menuEvent = Wait-ForTrace -StartIndex $marker -Pattern '^MENU (OPEN|CLOSE)$' `
        -TimeoutSeconds $MenuTimeoutSeconds -Description 'disk-browser event'
    if ($menuEvent -eq 'MENU CLOSE') {
        $marker = $trace.Count
        Press-FunctionKey -Slot 7
        Wait-ForTrace -StartIndex $marker -Pattern '^MENU OPEN$' `
            -TimeoutSeconds $MenuTimeoutSeconds -Description 'disk browser reopening' |
            Out-Null
    }

    Write-Host 'STEP 2/12: Select the bin folder (Up x3)'
    1..3 | ForEach-Object { Press-CoCoKey -Key 27 }

    Write-Host 'STEP 3/12: Open the bin folder'
    Press-CoCoKey -Key 48
    Receive-Serial -Milliseconds 750

    Write-Host 'STEP 4/12: Select ASTRO.BIN (Up x3)'
    1..3 | ForEach-Object { Press-CoCoKey -Key 27 }

    Write-Host 'STEP 5/12: Launch Astro'
    $launchMarker = $trace.Count
    Press-CoCoKey -Key 48
    $ready = Wait-ForTrace -StartIndex $launchMarker `
        -Pattern '^BIN READY .*ASTRO.*\.BIN EXEC [0-9A-F]{4}$' `
        -TimeoutSeconds $LaunchTimeoutSeconds -Description 'Astro BIN READY message'
    Write-Host "Confirmed: $ready"
    Write-Host 'STEP 6/12: Wait for the Astro main-menu loop'
    Assert-AstroMainMenu -StartIndex $launchMarker

    Write-Host 'STEP 7/12: Press F8 twice for right-joystick keyboard mapping'
    Press-FunctionKey -Slot 3
    Press-FunctionKey -Slot 3

    Write-Host 'STEP 8/12: Pulse fire repeatedly to begin play'
    1..6 | ForEach-Object {
        Pulse-Fire
        Receive-Serial -Milliseconds 120
    }

    Write-Host "STEP 9/12: Alternate left/right and fire for $GameplaySeconds seconds"
    $runtimeMarker = $trace.Count
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
        foreach ($direction in @(29, 30)) {
            if ($timer.Elapsed.TotalSeconds -ge $GameplaySeconds) { break }
            Send-SerialCommand -Command ('KD {0:X2}' -f $direction) `
                -WaitMilliseconds 80
            $directionTimer = [Diagnostics.Stopwatch]::StartNew()
            while ($directionTimer.ElapsedMilliseconds -lt 850 -and
                   $timer.Elapsed.TotalSeconds -lt $GameplaySeconds) {
                Pulse-Fire
                Receive-Serial -Milliseconds 50
            }
            Send-SerialCommand -Command ('KU {0:X2}' -f $direction) `
                -WaitMilliseconds 80
        }
    }

    Write-Host 'STEP 10/12: Release all emulated keys'
    Send-SerialCommand -Command 'RELEASE' -WaitMilliseconds 500

    Write-Host 'STEP 11/12: Validate CPU, stack, GIME/MMU and manager health'
    $health = Test-AstroRuntime -StartIndex $runtimeMarker
    $summary = ('PASS: Astro runtime healthy; {0} PC samples, {1} unique PCs, ' +
        '{2} valid stack samples, {3} GIME/MMU samples; {4}') -f
        $health.PcSamples, $health.UniquePcs, $health.StackSamples,
        $health.GimeSamples, $health.Status
    Write-Host $summary
    $completed = $true
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
        if (-not [IO.Path]::IsPathRooted($OutputPath)) {
            $OutputPath = Join-Path $repoRoot $OutputPath
        }
        $parent = Split-Path -Parent $OutputPath
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        [IO.File]::WriteAllLines(
            $OutputPath, $trace, [Text.UTF8Encoding]::new($false))
        Write-Host "Saved serial trace: $OutputPath"
    }
}

if ($completed -and -not $SkipScreenshot) {
    Write-Host 'STEP 12/12: Capture the full-resolution Astro gameplay frame'
    & (Join-Path $PSScriptRoot 'capture_video_serial.ps1') `
        -Port $Port -Name $ScreenshotName
    if ($LASTEXITCODE) { throw "Astro screenshot capture failed: $LASTEXITCODE" }
}
