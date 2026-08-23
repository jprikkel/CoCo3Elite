param(
    [string]$ExtendedBasicPath = 'roms/extbas11.rom',
    [string]$ColorBasicPath = 'roms/bas13.rom',
    [string]$OutputPath = 'build/roms/coco2.mem'
)

$ErrorActionPreference = 'Stop'

foreach ($path in @($ExtendedBasicPath, $ColorBasicPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required CoCo 2 ROM was not found at '$path'."
    }
}

$extended = [System.IO.File]::ReadAllBytes((Resolve-Path $ExtendedBasicPath))
$basic = [System.IO.File]::ReadAllBytes((Resolve-Path $ColorBasicPath))
if ($extended.Length -ne 8KB -or $basic.Length -ne 8KB) {
    throw 'Extended BASIC and Color BASIC ROMs must each be exactly 8192 bytes.'
}

$combined = [byte[]]::new(16KB)
[Array]::Copy($extended, 0, $combined, 0, 8KB)
[Array]::Copy($basic, 0, $combined, 8KB, 8KB)
$resetVector = ([int]$combined[0x3FFE] -shl 8) -bor [int]$combined[0x3FFF]
if ($resetVector -lt 0x8000 -or $resetVector -gt 0xBFFF) {
    throw ('CoCo 2 reset vector ${0:X4} is outside the $8000-$BFFF ROM window.' -f $resetVector)
}

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$lines = [string[]]::new($combined.Length)
for ($index = 0; $index -lt $combined.Length; $index++) {
    $lines[$index] = $combined[$index].ToString('X2')
}
[System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.Encoding]::ASCII)

Write-Host 'Prepared CoCo 2 Extended BASIC ROM:'
Write-Host "  Extended BASIC SHA-256: $((Get-FileHash $ExtendedBasicPath -Algorithm SHA256).Hash)"
Write-Host "  Color BASIC SHA-256:    $((Get-FileHash $ColorBasicPath -Algorithm SHA256).Hash)"
Write-Host ('  Reset vector:           ${0:X4}' -f $resetVector)
Write-Host "  Vivado image:           $OutputPath"
