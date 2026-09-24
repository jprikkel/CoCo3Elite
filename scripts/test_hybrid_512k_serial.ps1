param(
    [string]$Port = 'COM5',
    [ValidateRange(20, 500)][int]$KeyDelayMs = 70,
    [string]$CaptureName = 'hybrid-upper-384k-basic-test'
)

$ErrorActionPreference = 'Stop'
$serial = [IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.ReadTimeout = 50
$serial.WriteTimeout = 1000

function Send-Line([string]$line, [int]$delay = 70) {
    $serial.Write("$line`n")
    Start-Sleep -Milliseconds $delay
    if ($serial.BytesToRead) { [void]$serial.ReadExisting() }
}

function Get-Key([char]$character) {
    $code = [int]$character
    if ($character -eq "`r" -or $character -eq "`n") {
        return @{ Key = 48; Shift = $false }
    }
    if ($character -eq ' ') { return @{ Key = 31; Shift = $false } }
    if ($character -ge 'a' -and $character -le 'z') {
        return @{ Key = $code - [int][char]'a' + 1; Shift = $false }
    }
    if ($character -ge '0' -and $character -le '7') {
        return @{ Key = $code - [int][char]'0' + 32; Shift = $false }
    }
    if ($character -eq '8') { return @{ Key = 40; Shift = $false } }
    if ($character -eq '9') { return @{ Key = 41; Shift = $false } }
    $plain = @{ '@'=0; ':'=42; ';'=43; ','=44; '-'=45; '.'=46; '/'=47 }
    $shifted = @{ '!'=33; '"'=34; '#'=35; '$'=36; '%'=37; '&'=38; "'"=39;
                  '('=40; ')'=41; '*'=42; '+'=43; '<'=44; '='=45; '>'=46; '?'=47 }
    $name = [string]$character
    if ($plain.ContainsKey($name)) {
        return @{ Key = $plain[$name]; Shift = $false }
    }
    if ($shifted.ContainsKey($name)) {
        return @{ Key = $shifted[$name]; Shift = $true }
    }
    throw "Unsupported test-program character '$character'"
}

function Type-CoCoText([string]$text) {
    foreach ($character in $text.ToCharArray()) {
        $mapping = Get-Key $character
        if ($mapping.Shift) { Send-Line 'SH 1' 45 }
        Send-Line ('KD {0:X2}' -f $mapping.Key) $KeyDelayMs
        Send-Line ('KU {0:X2}' -f $mapping.Key) $KeyDelayMs
        if ($mapping.Shift) { Send-Line 'SH 0' 45 }
    }
}

try {
    $serial.Open()
    Send-Line 'RELEASE' 100
    Send-Line 'RESET' 100
    Start-Sleep -Seconds 3
    Type-CoCoText "10 for p=0 to 47:poke &hffa2,p:poke &h4000,p+1:next`r"
    Start-Sleep -Milliseconds 500
    Type-CoCoText "20 f=0:for p=0 to 47:poke &hffa2,p:if peek(&h4000)<>p+1 then f=1`r"
    Start-Sleep -Milliseconds 500
    Type-CoCoText "30 next:poke &hffa2,&h3a:print f`r"
    Start-Sleep -Milliseconds 500
    Type-CoCoText "run`r"
    Start-Sleep -Seconds 4
    Send-Line 'RELEASE' 100
} finally {
    if ($serial.IsOpen) { $serial.Close() }
}

& (Join-Path $PSScriptRoot 'capture_video_serial.ps1') `
    -Port $Port -Name $CaptureName
if ($LASTEXITCODE) { throw "Frame capture failed: $LASTEXITCODE" }
