param(
    [string]$Port = 'COM5',
    [ValidateSet('Ping', 'Status', 'Floppy', 'FloppyStart', 'FloppyHome', 'FloppyStop',
                 'FloppyDirection', 'FloppySide', 'FloppyStep', 'FloppyMount',
                 'FloppyUnmount', 'FloppyRead',
                 'Reset', 'Release', 'TypeText',
                 'TraceOn', 'TraceOff', 'TraceSnap', 'TraceStatus',
                 'BrowserRoot', 'KeyDown', 'KeyUp', 'FunctionKey')]
    [string]$Command = 'Ping',
    [string]$Text = '',
    [ValidateRange(0,55)][int]$Key = 0,
    [ValidateSet(3,6,7,8,9,10,11,12)][int]$Function = 12,
    [ValidateRange(0,1)][int]$FloppyValue = 1,
    [ValidateRange(1,85)][int]$FloppySteps = 1,
    [ValidateRange(0,39)][int]$FloppyTrack = 17,
    [ValidateRange(1,18)][int]$FloppySector = 1,
    [ValidateRange(3,30)][int]$ResponseTimeoutSeconds = 3,
    [ValidateRange(20,1000)][int]$KeyDelayMs = 70
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.NewLine = "`r`n"
$serial.ReadTimeout = 200
$serial.WriteTimeout = 1000

function Send-ManagerCommand {
    param([Parameter(Mandatory)][string]$Line)
    $serial.Write("$Line`n")
    $deadline = [DateTime]::UtcNow.AddSeconds($ResponseTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $reply = $serial.ReadLine().Trim()
            if ($reply -match '^(OK|ERR|PONG|STATUS|TRACE|FLOPPY)') {
                Write-Host $reply
                if ($reply -match '^ERR') { throw "Manager rejected '$Line': $reply" }
                return $reply
            }
            if ($reply) { Write-Verbose $reply }
        } catch [System.TimeoutException] { }
    }
    throw "No management reply to '$Line' on $Port"
}

function Get-CoCoKey {
    param([char]$Character)
    $code = [int][char]$Character
    if ($Character -eq "`r" -or $Character -eq "`n") { return @{ Key = 48; Shift = $false } }
    if ($Character -eq ' ') { return @{ Key = 31; Shift = $false } }
    if ($Character -ge 'a' -and $Character -le 'z') { return @{ Key = $code - [int][char]'a' + 1; Shift = $false } }
    if ($Character -ge 'A' -and $Character -le 'Z') { return @{ Key = $code - [int][char]'A' + 1; Shift = $true } }
    if ($Character -ge '0' -and $Character -le '7') { return @{ Key = $code - [int][char]'0' + 32; Shift = $false } }
    if ($Character -eq '8') { return @{ Key = 40; Shift = $false } }
    if ($Character -eq '9') { return @{ Key = 41; Shift = $false } }
    $plain = @{ '@'=0; ':'=42; ';'=43; ','=44; '-'=45; '.'=46; '/'=47 }
    $shifted = @{ '!'=33; '"'=34; '#'=35; '$'=36; '%'=37; '&'=38; "'"=39;
                  '('=40; ')'=41; '*'=42; '+'=43; '<'=44; '='=45; '>'=46; '?'=47 }
    $name = [string]$Character
    if ($plain.ContainsKey($name)) { return @{ Key = $plain[$name]; Shift = $false } }
    if ($shifted.ContainsKey($name)) { return @{ Key = $shifted[$name]; Shift = $true } }
    throw "Character '$Character' has no CoCo keyboard-matrix mapping"
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    switch ($Command) {
        'Ping'    { Send-ManagerCommand 'PING' | Out-Null }
        'Status'  { Send-ManagerCommand 'STATUS' | Out-Null }
        'Floppy'  { Send-ManagerCommand 'FLOPPY' | Out-Null }
        'FloppyStart' { Send-ManagerCommand 'FLOPPY START' | Out-Null }
        'FloppyHome' { Send-ManagerCommand 'FLOPPY HOME' | Out-Null }
        'FloppyStop' { Send-ManagerCommand 'FLOPPY STOP' | Out-Null }
        'FloppyMount' { Send-ManagerCommand 'FLOPPY MOUNT' | Out-Null }
        'FloppyUnmount' { Send-ManagerCommand 'FLOPPY UNMOUNT' | Out-Null }
        'FloppyRead' {
            Send-ManagerCommand ('FLOPPY READ {0:X2} {1:X2}' -f $FloppyTrack, $FloppySector) | Out-Null
        }
        'FloppyDirection' {
            Send-ManagerCommand ("FLOPPY DIR $FloppyValue") | Out-Null
        }
        'FloppySide' {
            Send-ManagerCommand ("FLOPPY SIDE $FloppyValue") | Out-Null
        }
        'FloppyStep' {
            for ($step = 0; $step -lt $FloppySteps; $step++) {
                Send-ManagerCommand 'FLOPPY STEP' | Out-Null
                Start-Sleep -Milliseconds 10
            }
        }
        'TraceOn' { Send-ManagerCommand 'TRACE ON' | Out-Null }
        'TraceOff' { Send-ManagerCommand 'TRACE OFF' | Out-Null }
        'TraceSnap' {
            Send-ManagerCommand 'TRACE SNAP' | Out-Null
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            $found = $false
            while ([DateTime]::UtcNow -lt $deadline) {
                try {
                    $line = $serial.ReadLine().Trim()
                    if ($line -match '^PC=') {
                        Write-Host $line
                        $found = $true
                        break
                    }
                } catch [System.TimeoutException] { }
            }
            if (-not $found) { throw 'No one-shot trace line received' }
        }
        'TraceStatus' { Send-ManagerCommand 'TRACE STATUS' | Out-Null }
        'Reset'   { Send-ManagerCommand 'RESET' | Out-Null }
        'Release' { Send-ManagerCommand 'RELEASE' | Out-Null }
        'BrowserRoot' { Send-ManagerCommand 'ROOT' | Out-Null }
        'KeyDown' { Send-ManagerCommand ('KD {0:X2}' -f $Key) | Out-Null }
        'KeyUp'   { Send-ManagerCommand ('KU {0:X2}' -f $Key) | Out-Null }
        'FunctionKey' {
            $functionMap = @{ 3=0; 6=1; 7=2; 8=3; 9=4; 10=5; 11=6; 12=7 }
            $slot = $functionMap[$Function]
            Send-ManagerCommand ('FK {0:X2}' -f (($slot -shl 1) -bor 1)) | Out-Null
            Start-Sleep -Milliseconds $KeyDelayMs
            Send-ManagerCommand ('FK {0:X2}' -f ($slot -shl 1)) | Out-Null
        }
        'TypeText' {
            foreach ($character in $Text.ToCharArray()) {
                $mapping = Get-CoCoKey $character
                if ($mapping.Shift) { Send-ManagerCommand 'SH 1' | Out-Null }
                Send-ManagerCommand ('KD {0:X2}' -f $mapping.Key) | Out-Null
                Start-Sleep -Milliseconds $KeyDelayMs
                Send-ManagerCommand ('KU {0:X2}' -f $mapping.Key) | Out-Null
                if ($mapping.Shift) { Send-ManagerCommand 'SH 0' | Out-Null }
                Start-Sleep -Milliseconds ([Math]::Max(20, [int]($KeyDelayMs / 2)))
            }
        }
    }
} finally {
    if ($serial.IsOpen) {
        try { $serial.Write("RELEASE`n") } catch { }
        Start-Sleep -Milliseconds 20
        $serial.Close()
    }
    $serial.Dispose()
}
