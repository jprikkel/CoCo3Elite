param(
    [string]$PortName = 'COM5',
    [ValidateRange(1, 600)]
    [int]$Seconds = 8,
    [string]$OutputPath,
    [switch]$Passive
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($PortName, 115200, 'None', 8, 'One')
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 250
$serial.NewLine = "`n"
try {
    $serial.Open()
    if (-not $Passive) {
        $serial.Write("TRACE ON`n")
    }
    $until = [Diagnostics.Stopwatch]::StartNew()
    $received = New-Object System.Text.StringBuilder
    while ($until.Elapsed.TotalSeconds -lt $Seconds) {
        try {
            $line = $serial.ReadLine().TrimEnd("`r")
            if ($line.Length) {
                [void]$received.AppendLine($line)
                Write-Output $line
            }
        } catch [System.TimeoutException] { }
    }
    if ($received.Length -eq 0) {
        throw "No UART data received from $PortName in $Seconds seconds. Verify the board is powered and the CH340 port is not open in PuTTY."
    }
    if ($OutputPath) {
        $absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
        $parent = Split-Path -Parent $absoluteOutput
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        [System.IO.File]::WriteAllText($absoluteOutput, $received.ToString(),
            [System.Text.UTF8Encoding]::new($false))
        Write-Host "Captured UART trace: $absoluteOutput"
    }
} finally {
    if ($serial.IsOpen) {
        if (-not $Passive) {
            try {
                $serial.Write("TRACE OFF`n")
                Start-Sleep -Milliseconds 200
            } catch { }
        }
        $serial.Close()
    }
    $serial.Dispose()
}
