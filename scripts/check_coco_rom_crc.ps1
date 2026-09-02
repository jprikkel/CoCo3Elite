[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "CoCo 3 ROM was not found at '$InputPath'."
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$rom = [System.IO.File]::ReadAllBytes($resolvedInput)
if ($rom.Length -ne 32KB) {
    throw "CRC inspection requires a raw 32 KiB CoCo 3 ROM; '$resolvedInput' is $($rom.Length) bytes."
}

# Match cocodiag/gencrctab.py exactly. Its reflected CRC table uses polynomial
# $8005 and stores each 16-bit entry in big-endian byte order.
$table = [UInt16[]]::new(256)
for ($index = 0; $index -lt 256; $index++) {
    $value = [UInt16]$index
    for ($bit = 0; $bit -lt 8; $bit++) {
        if ($value -band 1) {
            $value = [UInt16](($value -bxor 0x8005) -shr 1)
        } else {
            $value = [UInt16]($value -shr 1)
        }
    }
    $table[$index] = $value
}

function Get-CocodiagCrc {
    param(
        [byte[]]$Bytes,
        [int]$Start,
        [int]$End
    )

    [byte]$high = 0
    [byte]$low = 0
    for ($offset = $Start; $offset -lt $End; $offset++) {
        $entry = $table[([int]$Bytes[$offset] -bxor [int]$low)]
        $entryHigh = [byte]($entry -shr 8)
        $entryLow = [byte]($entry -band 0xff)
        $newLow = [byte]([int]$entryLow -bxor [int]$high)
        $high = $entryHigh
        $low = $newLow
    }
    return ([int]$high -shl 8) -bor [int]$low
}

$knownColorBasic = @{
    0x47C3 = 'Color BASIC 1.0'
    0x3123 = 'Color BASIC 1.1'
    0x400A = 'Color BASIC 1.2'
    0x0C1F = 'Color BASIC 1.3'
    0x6EA2 = 'Color BASIC 1.4'
    0x3149 = 'Color BASIC 2.0'
}
$knownExtended = @{
    0x3441 = 'Extended Color BASIC 1.0'
    0x2D38 = 'Extended Color BASIC 1.1'
    0x5CDE = 'Extended Color BASIC 2.0'
}
$knownSuper = @{
    0x00FF = 'Super Extended BASIC NTSC'
    0xFF54 = 'Super Extended BASIC PAL'
}

$results = @(
    [pscustomobject]@{
        Region = 'Extended Color BASIC'
        CpuRange = '$8000-$9FFF'
        Crc = Get-CocodiagCrc $rom 0x0000 0x2000
        Known = $knownExtended
    },
    [pscustomobject]@{
        Region = 'Color BASIC'
        CpuRange = '$A000-$BFFF'
        Crc = Get-CocodiagCrc $rom 0x2000 0x4000
        Known = $knownColorBasic
    },
    [pscustomobject]@{
        Region = 'Super Extended BASIC'
        CpuRange = '$E000-$FDFF'
        Crc = Get-CocodiagCrc $rom 0x6000 0x7E00
        Known = $knownSuper
    }
)

Write-Host "cocodiag ROM CRCs: $resolvedInput"
foreach ($result in $results) {
    $label = if ($result.Known.ContainsKey($result.Crc)) {
        $result.Known[$result.Crc]
    } else {
        'UNK'
    }
    Write-Host ('  {0,-21} {1}  {2:X4}  {3}' -f `
        $result.Region, $result.CpuRange, $result.Crc, $label)
}

