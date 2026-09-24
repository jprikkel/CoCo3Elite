param(
    [string]$Port = 'COM5',
    [ValidateRange(1,8)][int]$RunSeconds = 6
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
    Send-FloppyCommand 'FLOPPY START' | Out-Null
    Start-Sleep -Milliseconds 200
    $first = Send-FloppyCommand 'FLOPPY'
    if ($first -notmatch 'ACTIVE=1') {
        throw "Drive did not report active after start: $first"
    }
    Start-Sleep -Seconds $RunSeconds
    Send-FloppyCommand 'FLOPPY' | Out-Null
    Write-Host 'PASS: bounded physical floppy motor/select interval completed'
} finally {
    if ($serial.IsOpen) {
        try { Send-FloppyCommand 'FLOPPY STOP' | Out-Null } catch {
            Write-Warning "Could not confirm FLOPPY STOP: $($_.Exception.Message)"
        }
        $serial.Close()
    }
    $serial.Dispose()
}
