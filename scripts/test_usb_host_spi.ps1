param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\usb_host_spi'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repoRoot 'rtl\management\usb_host_spi.v') `
        (Join-Path $repoRoot 'tb\usb_host_spi_tb.v')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    $testTop = 'usb_host_spi_tb'
    & (Join-Path $VivadoBin 'xelab.bat') $testTop -s "${testTop}_sim"
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    $simOutput = & (Join-Path $VivadoBin 'xsim.bat') "${testTop}_sim" -runall 2>&1
    $simExit = $LASTEXITCODE
    $simOutput | Out-Host
    $simText = $simOutput -join "`n"
    if ($simExit -ne 0 -or $simText -match '(?im)\b(FAIL|FATAL|ERROR)\b' -or
        $simText -notmatch "PASS: $testTop") {
        throw "$testTop failed or did not reach its PASS marker (exit $simExit)"
    }
} finally { Pop-Location }
