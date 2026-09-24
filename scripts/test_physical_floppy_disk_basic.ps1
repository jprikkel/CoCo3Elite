param(
    [string]$Port = 'COM5',
    [string]$BasicCommand = 'dir',
    [ValidateRange(3,60)][int]$CaptureSeconds = 15,
    [ValidateRange(40,500)][int]$KeyDelayMs = 90,
    [string]$ExpectedSectorPrefix = '',
    [switch]$SkipMount
)

$ErrorActionPreference = 'Stop'
$serial = [IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.NewLine = "`r`n"
$serial.ReadTimeout = 200
$serial.WriteTimeout = 1000
$transcript = [Text.StringBuilder]::new()

function Read-LineUntil {
    param([DateTime]$Deadline, [string]$Pattern)
    while ([DateTime]::UtcNow -lt $Deadline) {
        try {
            $line = $serial.ReadLine().Trim()
            if ($line) {
                [void]$transcript.AppendLine($line)
                Write-Host $line
                if ($line -match $Pattern) { return $line }
            }
        } catch [TimeoutException] { }
    }
    throw "Timed out waiting for '$Pattern'"
}

function Send-Command {
    param([string]$Line, [string]$Pattern = '^(OK|PONG|STATUS|TRACE|FLOPPY)')
    $serial.Write("$Line`n")
    $reply = Read-LineUntil ([DateTime]::UtcNow.AddSeconds(8)) $Pattern
    if ($reply -match '^ERR') { throw "Manager rejected '$Line': $reply" }
}

function Get-Key {
    param([char]$Character)
    $code = [int][char]$Character
    if ($Character -eq "`r" -or $Character -eq "`n") { return @{ Key=48; Shift=$false } }
    if ($Character -eq ' ') { return @{ Key=31; Shift=$false } }
    if ($Character -ge 'a' -and $Character -le 'z') { return @{ Key=$code-[int][char]'a'+1; Shift=$false } }
    if ($Character -ge 'A' -and $Character -le 'Z') { return @{ Key=$code-[int][char]'A'+1; Shift=$true } }
    if ($Character -ge '0' -and $Character -le '7') { return @{ Key=$code-[int][char]'0'+32; Shift=$false } }
    if ($Character -eq '8') { return @{ Key=40; Shift=$false } }
    if ($Character -eq '9') { return @{ Key=41; Shift=$false } }
    $plain = @{ '@'=0; ':'=42; ';'=43; ','=44; '-'=45; '.'=46; '/'=47 }
    $shifted = @{ '!'=33; '"'=34; '#'=35; '$'=36; '%'=37; '&'=38; "'"=39;
                  '('=40; ')'=41; '*'=42; '+'=43; '<'=44; '='=45; '>'=46; '?'=47 }
    $name = [string]$Character
    if ($plain.ContainsKey($name)) { return @{ Key=$plain[$name]; Shift=$false } }
    if ($shifted.ContainsKey($name)) { return @{ Key=$shifted[$name]; Shift=$true } }
    throw "Character '$Character' has no CoCo keyboard-matrix mapping"
}

function Press-Key {
    param([char]$Character)
    $mapping = Get-Key $Character
    if ($mapping.Shift) { Send-Command 'SH 1' '^OK SHIFT' }
    Send-Command ('KD {0:X2}' -f $mapping.Key) '^OK KEY'
    Start-Sleep -Milliseconds $KeyDelayMs
    Send-Command ('KU {0:X2}' -f $mapping.Key) '^OK KEY'
    if ($mapping.Shift) { Send-Command 'SH 0' '^OK SHIFT' }
    Start-Sleep -Milliseconds ([Math]::Max(20,[int]($KeyDelayMs/2)))
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 150
    Send-Command 'TRACE OFF' '^OK TRACE OFF'
    if (-not $SkipMount) { Send-Command 'FLOPPY MOUNT' '^OK FLOPPY MOUNT' }
    foreach ($character in ($BasicCommand + "`r").ToCharArray()) { Press-Key $character }

    $deadline = [DateTime]::UtcNow.AddSeconds($CaptureSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $line = $serial.ReadLine().Trim()
            if ($line) {
                [void]$transcript.AppendLine($line)
                Write-Host $line
            }
        } catch [TimeoutException] { }
    }

    $text = $transcript.ToString()
    if ($text -notmatch '(?m)^FDC PHYSICAL ') { throw 'No physical-floppy FDC reads were observed' }
    if ($text -match '(?m)^FDC ERR ') { throw 'Disk BASIC reported a physical-floppy FDC read failure' }
    if ($ExpectedSectorPrefix) {
        $expectedBytes = ($ExpectedSectorPrefix -split '\s+' |
            Where-Object { $_ }) -join '\s+'
        if ($text -notmatch ('(?m)^FDC CPU\s+' + $expectedBytes + '\s*$')) {
            throw "Disk BASIC did not receive expected sector prefix '$ExpectedSectorPrefix'"
        }
    }
    Write-Host "PASS: Disk BASIC '$BasicCommand' used the physical read-only drive"
} finally {
    if ($serial.IsOpen) {
        try { $serial.Write("RELEASE`n") } catch { }
        Start-Sleep -Milliseconds 20
        $serial.Close()
    }
    $serial.Dispose()
}
