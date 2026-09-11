param([string]$Gcc = 'C:\AMD\2025.2\tps\mingw\10.0.0\win64.o\nt\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\management\tests'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$testExe = Join-Path $runDir 'sd_spi_test.exe'
& $Gcc -std=c11 -O2 -Wall -Wextra -Werror -static `
    -I (Join-Path $repoRoot 'firmware\management') `
    (Join-Path $repoRoot 'firmware\management\sd_spi.c') `
    (Join-Path $repoRoot 'tb\sd_spi_test.c') -o $testExe
if ($LASTEXITCODE -ne 0) { throw "SD firmware test compilation failed: $LASTEXITCODE" }
$output = & $testExe 2>&1
$testExit = $LASTEXITCODE
$output | Out-Host
if ($testExit -ne 0 -or ($output -join "`n") -notmatch 'PASS: sd_spi_test') {
    throw "SD firmware test failed or lacked a PASS marker: $testExit"
}
