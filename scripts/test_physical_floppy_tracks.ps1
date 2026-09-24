param(
    [string]$Port = 'COM5',
    [ValidateRange(1,84)][int]$LastTrack = 39,
    [ValidateRange(1,16)][int]$Increment = 2,
    [ValidateRange(0,10000)][int]$TrackPauseMs = 0,
    [ValidateRange(0,1)][int]$AwayDirection = 0,
    [ValidateRange(0,1)][int]$HomeDirection = 1
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.NewLine = "`r`n"
$serial.ReadTimeout = 250
$serial.WriteTimeout = 1000

function Send-FloppyCommand {
    param([Parameter(Mandatory)][string]$Line)
    $serial.Write("$Line`n")
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $reply = $serial.ReadLine().Trim()
            if ($reply -match '^(OK|ERR|FLOPPY)') {
                Write-Host $reply
                if ($reply -match '^ERR') { throw $reply }
                return $reply
            }
        } catch [System.TimeoutException] { }
    }
    throw "No management reply to '$Line' on $Port"
}

function Start-FloppyInterval {
    Send-FloppyCommand 'FLOPPY START' | Out-Null
}

function Refresh-FloppyInterval {
    param([Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Timer)
    if ($Timer.ElapsedMilliseconds -ge 6000) {
        Start-FloppyInterval
        $Timer.Restart()
    }
}

function Wait-AtTrack {
    if ($TrackPauseMs -gt 0) { Start-Sleep -Milliseconds $TrackPauseMs }
}

function Step-Floppy {
    param([Parameter(Mandatory)][int]$Count)
    for ($step = 0; $step -lt $Count; $step++) {
        Send-FloppyCommand 'FLOPPY STEP' | Out-Null
        Start-Sleep -Milliseconds 10
    }
}

function Home-Floppy {
    Send-FloppyCommand "FLOPPY DIR $HomeDirection" | Out-Null
    $before = Send-FloppyCommand 'FLOPPY'
    if ($before -notmatch 'DONE=([01])') { throw 'HOME status lacks DONE state' }
    $doneBefore = $Matches[1]
    Send-FloppyCommand 'FLOPPY HOME' | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $status = Send-FloppyCommand 'FLOPPY'
        if ($status -match 'HOME=0 DONE=([01]) OK=([01]) STEPS=([0-9A-Fa-f]{2})' -and
            $Matches[1] -ne $doneBefore) {
            if ($Matches[2] -ne '1') { throw "HOME failed: $status" }
            return
        }
    }
    throw 'HOME timed out'
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()

    Home-Floppy
    Write-Host 'TRACK 0 (HOME)'
    Wait-AtTrack

    Send-FloppyCommand "FLOPPY DIR $AwayDirection" | Out-Null
    Start-FloppyInterval
    $motorTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $track = 0
    while (($track + $Increment) -le $LastTrack) {
        Refresh-FloppyInterval $motorTimer
        Step-Floppy $Increment
        $track += $Increment
        Write-Host "TRACK $track"
        Wait-AtTrack
    }
    if ($track -lt $LastTrack) {
        Refresh-FloppyInterval $motorTimer
        Step-Floppy ($LastTrack - $track)
        $track = $LastTrack
        Write-Host "TRACK $track"
        Wait-AtTrack
    }

    Send-FloppyCommand "FLOPPY DIR $HomeDirection" | Out-Null
    Start-FloppyInterval
    $motorTimer.Restart()
    while (($track - $Increment) -ge 0) {
        Refresh-FloppyInterval $motorTimer
        Step-Floppy $Increment
        $track -= $Increment
        Write-Host "TRACK $track"
        Wait-AtTrack
    }
    if ($track -gt 0) {
        Refresh-FloppyInterval $motorTimer
        Step-Floppy $track
        $track = 0
        Write-Host 'TRACK 0'
        Wait-AtTrack
    }

    $final = Send-FloppyCommand 'FLOPPY'
    if ($final -notmatch 'TRACK0=1') {
        throw "Sweep returned to estimated track 0 but TRACK0 is not asserted: $final"
    }
    Write-Host "PASS: swept tracks 0 through $LastTrack and returned to TRACK0"
} finally {
    if ($serial.IsOpen) {
        try { Send-FloppyCommand 'FLOPPY STOP' | Out-Null } catch {
            Write-Warning "Could not confirm FLOPPY STOP: $($_.Exception.Message)"
        }
        $serial.Close()
    }
    $serial.Dispose()
}
