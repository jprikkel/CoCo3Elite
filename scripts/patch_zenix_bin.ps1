param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$Gcc = 'C:\AMD\2025.2\tps\mingw\10.0.0\win64.o\nt\bin\gcc.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$inputFile = [IO.Path]::GetFullPath((Join-Path (Get-Location) $InputPath))
$outputFile = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
if ($inputFile -eq $outputFile) { throw 'Input and output paths must differ.' }
if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
    throw "Missing input file: $inputFile"
}
$toolDir = Join-Path $repoRoot 'build\tools\zenix-patch'
$tool = Join-Path $toolDir 'patch_zenix_bin.exe'
New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFile) | Out-Null
& $Gcc '-std=c11' '-Wall' '-Wextra' '-Werror' '-O2' `
    (Join-Path $repoRoot 'tools\zenix\patch_zenix_bin.c') '-o' $tool
if ($LASTEXITCODE) { throw "Zenix patch tool compile failed: $LASTEXITCODE" }
& $tool $inputFile $outputFile
if ($LASTEXITCODE) { throw "Zenix conversion failed: $LASTEXITCODE" }
