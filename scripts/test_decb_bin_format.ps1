param([string]$Gcc = 'C:\AMD\2025.2\tps\mingw\10.0.0\win64.o\nt\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\tests\decb-bin-format'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$testExe = Join-Path $runDir 'decb_bin_format_test.exe'

& $Gcc '-std=c11' '-Wall' '-Wextra' '-Werror' `
    '-I' (Join-Path $repoRoot 'firmware\management') `
    (Join-Path $repoRoot 'firmware\management\decb_bin_format.c') `
    (Join-Path $repoRoot 'tb\decb_bin_format_test.c') `
    '-o' $testExe
if ($LASTEXITCODE) { throw "DECB BIN parser compile failed: $LASTEXITCODE" }
& $testExe
if ($LASTEXITCODE) { throw "DECB BIN parser tests failed: $LASTEXITCODE" }
