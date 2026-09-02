[CmdletBinding()]
param(
    [string]$OutputPath = 'disks\fpgatest.dsk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$decb = Join-Path $repoRoot 'tools\toolshed\decb.exe'
$output = Join-Path $repoRoot $OutputPath
$sourceDir = Join-Path $repoRoot 'tb\basic'

if (-not (Test-Path -LiteralPath $decb)) {
    throw "ToolShed decb executable not found at $decb"
}

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Force
}

& $decb dskini $output -3
if ($LASTEXITCODE -ne 0) { throw "decb dskini failed with exit code $LASTEXITCODE" }

$programs = @('TESTMENU', 'CPURAM', 'ROMTEST', 'CARTTEST', 'VIDEO', 'VID2', 'VID3', 'PALTEST', 'GIMETEST', 'GIMETMR', 'AUDIO', 'WIDTHS', 'INPUT')
foreach ($program in $programs) {
    $source = Join-Path $sourceDir "$program.BAS"
    $destination = "$output,$program.BAS"
    & $decb copy $source -t $destination
    if ($LASTEXITCODE -ne 0) { throw "decb copy failed for $program.BAS with exit code $LASTEXITCODE" }
}

foreach ($binary in @('MEMT2023.BIN', 'SYSINFO.BIN')) {
    $source = Join-Path $repoRoot "roms\$binary"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Diagnostic binary not found at $source"
    }
    & $decb copy -2 -b $source "$output,$binary"
    if ($LASTEXITCODE -ne 0) { throw "decb copy failed for $binary with exit code $LASTEXITCODE" }
}

Write-Host "Created CoCo 3 FPGA diagnostic disk: $output"
& $decb dir "$output,"
if ($LASTEXITCODE -ne 0) { throw "decb dir failed with exit code $LASTEXITCODE" }
