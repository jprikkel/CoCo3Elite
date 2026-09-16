[CmdletBinding()]
param(
    [string]$OutputDirectory = 'build\diagnostics'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $repoRoot $OutputDirectory
}
$assembler = Join-Path $repoRoot 'tools\asm6809\asm6809.exe'
$decb = Join-Path $repoRoot 'tools\toolshed\decb.exe'
$source = Join-Path $repoRoot 'tb\asm\ELITEDIAG.asm'
$binary = Join-Path $outputRoot 'ELITEDIAG.BIN'
$shortBinary = Join-Path $outputRoot 'ELTDIAG.BIN'
$listing = Join-Path $outputRoot 'ELITEDIAG.LST'
$memorySource = Join-Path $repoRoot 'tb\asm\ELITEMEM.asm'
$memoryRaw = Join-Path $outputRoot 'ELITEMEM.raw'
$memoryCart = Join-Path $outputRoot 'ELITEMEM.CCC'
$memoryListing = Join-Path $outputRoot 'ELITEMEM.LST'
$disk = Join-Path $outputRoot 'ELITETST.DSK'

foreach ($tool in @($assembler, $decb)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required tool not found: $tool"
    }
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

& $assembler '-C' '-e' '0x6000' '-o' $binary '-l' $listing $source
if ($LASTEXITCODE -ne 0) { throw "ELITEDIAG assembly failed: $LASTEXITCODE" }
# Keep an 8.3 standalone alias matching the filename placed in ELITETST.DSK.
# The management browser reads the physical SD card; build artifacts do not
# appear there until this file is copied to the card.
Copy-Item -LiteralPath $binary -Destination $shortBinary -Force

& $assembler '-B' '-o' $memoryRaw '-l' $memoryListing $memorySource
if ($LASTEXITCODE -ne 0) { throw "ELITEMEM assembly failed: $LASTEXITCODE" }
$memoryBytes = [System.IO.File]::ReadAllBytes($memoryRaw)
if ($memoryBytes.Length -gt 8192) {
    throw "ELITEMEM is $($memoryBytes.Length) bytes and exceeds the 8 KiB cartridge window"
}
$paddedMemory = [byte[]]::new(8192)
[Array]::Fill($paddedMemory, [byte]0xff)
[Array]::Copy($memoryBytes, $paddedMemory, $memoryBytes.Length)
[System.IO.File]::WriteAllBytes($memoryCart, $paddedMemory)
Remove-Item -LiteralPath $memoryRaw -Force

if (Test-Path -LiteralPath $disk -PathType Leaf) {
    Remove-Item -LiteralPath $disk -Force
}
& $decb dskini $disk -3
if ($LASTEXITCODE -ne 0) { throw "ELITETST disk creation failed: $LASTEXITCODE" }
& $decb copy -2 -b $shortBinary "${disk},ELTDIAG.BIN"
if ($LASTEXITCODE -ne 0) { throw "Adding ELTDIAG.BIN failed: $LASTEXITCODE" }

Write-Host "Built $binary"
Write-Host "Built $shortBinary"
Write-Host "Built $memoryCart"
Write-Host "Built $disk"
