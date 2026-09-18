$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$run = Join-Path $repo 'build\test-uart-rx'
$vivadoBin = 'C:\AMD\2025.2\Vivado\bin'
New-Item -ItemType Directory -Force -Path $run | Out-Null
Push-Location $run
try {
    & (Join-Path $vivadoBin 'xvlog.bat') `
        (Join-Path $repo 'rtl\wukong\uart_rx.v') `
        (Join-Path $repo 'tb\uart_rx_tb.v')
    if ($LASTEXITCODE) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $vivadoBin 'xelab.bat') uart_rx_tb -s uart_rx_tb_sim
    if ($LASTEXITCODE) { throw "xelab failed: $LASTEXITCODE" }
    $output = & (Join-Path $vivadoBin 'xsim.bat') uart_rx_tb_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or (($output -join "`n") -notmatch 'PASS: UART RX')) {
        throw 'UART RX simulation failed'
    }
} finally { Pop-Location }
