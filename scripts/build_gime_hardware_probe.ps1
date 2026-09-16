param(
    [string]$OutputDirectory = 'build\gime_1987_probe'
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
$disk = Join-Path $outputRoot 'GIME1987.DSK'

foreach ($tool in @($assembler, $decb)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required tool not found: $tool"
    }
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$programs = @(
    @{ Name = 'GIMERAST'; Entry = '0x6000' },
    @{ Name = 'GIMEINIT'; Entry = '0x6000' },
    @{ Name = 'GIMELPR'; Entry = '0x7000' }
)

foreach ($program in $programs) {
    $source = Join-Path $repoRoot "tb\asm\$($program.Name).asm"
    $binary = Join-Path $outputRoot "$($program.Name).BIN"
    & $assembler '-C' '-e' $program.Entry '-o' $binary $source
    if ($LASTEXITCODE -ne 0) {
        throw "$($program.Name) assembly failed: $LASTEXITCODE"
    }
}

if (Test-Path -LiteralPath $disk -PathType Leaf) {
    Remove-Item -LiteralPath $disk -Force
}
& $decb dskini $disk -3
if ($LASTEXITCODE -ne 0) { throw "GIMERAST disk creation failed: $LASTEXITCODE" }
foreach ($program in $programs) {
    $binary = Join-Path $outputRoot "$($program.Name).BIN"
    & $decb copy -2 -b $binary "${disk},$($program.Name).BIN"
    if ($LASTEXITCODE -ne 0) {
        throw "Adding $($program.Name).BIN to disk failed: $LASTEXITCODE"
    }
    Write-Host "Built $binary"
}

Write-Host "Built $disk"
