param(
    [string]$Gcc = 'C:\AMD\2025.2\tps\mingw\10.0.0\win64.o\nt\bin\gcc.exe',
    [string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = if ($RunDirectory) { $RunDirectory } else { Join-Path $repoRoot 'build\tests\decb-bin-format' }
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

$bankedTestExe = Join-Path $runDir 'coco3_banked_bin_format_test.exe'
& $Gcc '-std=c11' '-Wall' '-Wextra' '-Werror' `
    '-I' (Join-Path $repoRoot 'firmware\management') `
    (Join-Path $repoRoot 'firmware\management\coco3_banked_bin_format.c') `
    (Join-Path $repoRoot 'tb\coco3_banked_bin_format_test.c') `
    '-o' $bankedTestExe
if ($LASTEXITCODE) { throw "Banked BIN parser compile failed: $LASTEXITCODE" }
& $bankedTestExe
if ($LASTEXITCODE) { throw "Banked BIN parser tests failed: $LASTEXITCODE" }
