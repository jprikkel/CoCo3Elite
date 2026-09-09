param(
    [string]$PortName = 'COM5',
    [ValidateRange(1, 60)]
    [int]$Seconds = 8
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($PortName, 115200, 'None', 8, 'One')
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 250
$serial.NewLine = "`n"
try {
    $serial.Open()
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
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
