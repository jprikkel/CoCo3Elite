param(
    [string]$Port = 'COM5',
    [ValidateRange(0,1)][int]$Direction = 1,
    [ValidateRange(2,15)][int]$TimeoutSeconds = 5
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

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    $before = Send-FloppyCommand 'FLOPPY'
    if ($before -notmatch 'DONE=([01])') {
        throw "Pre-home status lacks DONE state: $before"
    }
    $doneBefore = $Matches[1]
    Send-FloppyCommand "FLOPPY DIR $Direction" | Out-Null
    Send-FloppyCommand 'FLOPPY HOME' | Out-Null

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $final = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $status = Send-FloppyCommand 'FLOPPY'
        if ($status -match 'HOME=0 DONE=([01]) OK=([01]) STEPS=([0-9A-Fa-f]{2})' -and
            $Matches[1] -ne $doneBefore) {
            $final = $status
            break
        }
    }
    if (-not $final) { throw 'Physical floppy HOME did not complete in time' }
    if ($final -notmatch 'OK=1') {
        throw "Physical floppy did not assert TRACK0 within 85 steps: $final"
    }
    Write-Host 'PASS: physical floppy reached TRACK0 within the bounded seek'
} finally {
    if ($serial.IsOpen) {
        try { Send-FloppyCommand 'FLOPPY STOP' | Out-Null } catch {
            Write-Warning "Could not confirm FLOPPY STOP: $($_.Exception.Message)"
        }
        $serial.Close()
    }
    $serial.Dispose()
}
