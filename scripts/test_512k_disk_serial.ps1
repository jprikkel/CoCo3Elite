param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ValidateRange(1,30)][int]$DiskIndex,
    [ValidateRange(0,30)][int]$FolderIndex = 0,
    [string]$BasicCommand = '',
    [string]$Port = 'COM5',
    [ValidateRange(1,120)][int]$RunSeconds = 25,
    [string]$OutputDirectory = 'build\test-output\hybrid-512k-games'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$trace = [Collections.Generic.List[string]]::new()
$serial = [IO.Ports.SerialPort]::new($Port, 460800, 'None', 8, 'One')
$serial.NewLine = "`n"
$serial.ReadTimeout = 80
$serial.WriteTimeout = 1000

function Receive([int]$Milliseconds) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $Milliseconds) {
        try {
            $line = $serial.ReadLine().TrimEnd("`r")
            if ($line.Length) {
                $trace.Add($line)
                if ($line -match '^(MOUNT|ERR|FDC|CART FAULT|COCO3 UART READY|STATUS)') {
                    Write-Host $line
                }
            }
        } catch [TimeoutException] { }
    }
}

function Send([string]$Line, [int]$Delay = 110) {
    $serial.Write("$Line`n")
    Receive $Delay
}

function Key([int]$Index) {
    Send ('KD {0:X2}' -f $Index) 120
    Send ('KU {0:X2}' -f $Index) 170
}

function Function-Key([int]$Slot) {
    Send ('FK {0:X2}' -f (($Slot -shl 1) -bor 1)) 120
    Send ('FK {0:X2}' -f ($Slot -shl 1)) 230
}

function Type-CoCo([string]$Text) {
    foreach ($character in $Text.ToCharArray()) {
        $key = 0
        $shift = $false
        $code = [int]$character
        if ($character -eq "`r" -or $character -eq "`n") {
            $key = 48
        } elseif ($character -eq ' ') {
            $key = 31
        } elseif ($character -ge 'a' -and $character -le 'z') {
            $key = $code - [int][char]'a' + 1
        } elseif ($character -ge 'A' -and $character -le 'Z') {
            $key = $code - [int][char]'A' + 1
            $shift = $true
        } elseif ($character -ge '0' -and $character -le '7') {
            $key = $code - [int][char]'0' + 32
        } elseif ($character -eq '8') {
            $key = 40
        } elseif ($character -eq '9') {
            $key = 41
        } elseif ($character -eq '"') {
            $key = 34
            $shift = $true
        } else {
            throw "Unsupported BASIC input character '$character'"
        }
        if ($shift) { Send 'SH 1' 50 }
        Key $key
        if ($shift) { Send 'SH 0' 50 }
    }
}

try {
    $serial.Open()
    Send 'RELEASE'
    Send 'ROOT'
    Function-Key 7
    # If F12 just closed an already open browser, reopen from its root.
    if (@($trace | Select-Object -Last 5) -match '^MENU CLOSE$') {
        Function-Key 7
    }
    1..9 | ForEach-Object { Key 28 }
    Key 48
    Receive 400
    1..3 | ForEach-Object { Key 28 }
    Key 48
    Receive 400
    if ($FolderIndex) {
        1..$FolderIndex | ForEach-Object { Key 28 }
        Key 48
        Receive 400
    }
    1..$DiskIndex | ForEach-Object { Key 28 }
    $mountMarker = $trace.Count
    Key 48
    Receive 3000
    if (-not (@($trace | Select-Object -Skip $mountMarker) -match '^MOUNT D0 .+\.DSK CRC32 [0-9A-F]{8}$')) {
        throw "No DSK mounted from the selected entry (see $Name.log)"
    }
    Send 'RESET' 250
    Receive 3000
    Type-CoCo "DIR 0`r"
    Receive 4500
    Send 'STATUS' 500
    if ($BasicCommand) {
        Type-CoCo "$BasicCommand`r"
        Receive ($RunSeconds * 1000)
        Send 'STATUS' 500
    }
    Send 'RELEASE'
} finally {
    if ($serial.IsOpen) {
        try { Send 'RELEASE' 100 } catch { }
        $serial.Close()
    }
    $serial.Dispose()
    $logPath = Join-Path $OutputDirectory "$Name.log"
    [IO.File]::WriteAllLines($logPath, $trace, [Text.UTF8Encoding]::new($false))
    Write-Host "TRACE $logPath"
}

& (Join-Path $PSScriptRoot 'capture_video_serial.ps1') `
    -Port $Port -OutputDirectory $OutputDirectory -Name $Name
if ($LASTEXITCODE) { throw "Frame capture failed: $LASTEXITCODE" }
