param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Read-BdfFont {
    param([Parameter(Mandatory)][string]$Path)

    $lines = Get-Content -LiteralPath $Path
    $ascent = 12
    $glyphs = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^FONT_ASCENT\s+(\d+)') {
            $ascent = [int]$Matches[1]
        }
        if ($lines[$i] -ne 'STARTCHAR' -and $lines[$i] -notmatch '^STARTCHAR ') {
            continue
        }

        $encoding = -1
        $dwidth = 8
        $bbx = @(8, 16, 0, -4)
        $bitmap = @()
        while ($i -lt $lines.Count -and $lines[$i] -ne 'ENDCHAR') {
            if ($lines[$i] -match '^ENCODING\s+(-?\d+)') {
                $encoding = [int]$Matches[1]
            } elseif ($lines[$i] -match '^DWIDTH\s+(\d+)') {
                $dwidth = [int]$Matches[1]
            } elseif ($lines[$i] -match '^BBX\s+(\d+)\s+(\d+)\s+(-?\d+)\s+(-?\d+)') {
                $bbx = @([int]$Matches[1], [int]$Matches[2],
                         [int]$Matches[3], [int]$Matches[4])
            } elseif ($lines[$i] -eq 'BITMAP') {
                for ($row = 0; $row -lt $bbx[1]; $row++) {
                    $i++
                    $bitmap += [Convert]::ToUInt32($lines[$i], 16)
                }
            }
            $i++
        }

        if ($encoding -ge 0 -and $encoding -lt 128) {
            $rows = [byte[]]::new(16)
            $top = $ascent - ($bbx[3] + $bbx[1])
            $cellInset = [Math]::Max(0, [Math]::Floor((8 - $dwidth) / 2))
            $shift = $cellInset + $bbx[2]
            for ($row = 0; $row -lt $bitmap.Count; $row++) {
                $target = $top + $row
                if ($target -lt 0 -or $target -ge 16) { continue }
                $sourceBits = $bitmap[$row]
                $sourceBytes = [Math]::Ceiling($bbx[0] / 8.0)
                if ($sourceBytes -gt 1) { $sourceBits = $sourceBits -shr (8 * ($sourceBytes - 1)) }
                if ($shift -ge 0) { $sourceBits = $sourceBits -shr $shift }
                else { $sourceBits = $sourceBits -shl (-$shift) }
                $rows[$target] = [byte]($sourceBits -band 0xff)
            }
            $glyphs[$encoding] = $rows
        }
    }
    return $glyphs
}

function Add-FontRows {
    param([System.Collections.Generic.List[string]]$Output, $Glyphs, [byte[][]]$Fallback)
    for ($code = 0; $code -lt 128; $code++) {
        $rows = if ($Glyphs.ContainsKey($code)) { $Glyphs[$code] } else { $Fallback[$code] }
        foreach ($value in $rows) { $Output.Add(('{0:x2}' -f $value)) }
    }
}

function Add-MemBank {
    param([System.Collections.Generic.List[string]]$Output,
          [Parameter(Mandatory)][string]$Path)
    $rows = Get-Content -LiteralPath $Path
    if ($rows.Count -ne 2048) {
        throw "$Path must contain exactly 2048 rows."
    }
    foreach ($row in $rows) {
        if ($row -notmatch '^[0-9A-Fa-f]{2}$') {
            throw "$Path contains an invalid font byte: $row"
        }
        $Output.Add($row.ToLowerInvariant())
    }
}

$fontDirectory = Join-Path $RepoRoot 'rtl\management\fonts'
$existing = Get-Content -LiteralPath (Join-Path $fontDirectory 'Spleen8x16.mem')
if ($existing.Count -lt 2048) { throw 'Existing Spleen font ROM is incomplete.' }
$spleen = [byte[][]]::new(128)
for ($code = 0; $code -lt 128; $code++) {
    $spleen[$code] = [byte[]]::new(16)
    for ($row = 0; $row -lt 16; $row++) {
        $spleen[$code][$row] = [Convert]::ToByte($existing[$code * 16 + $row], 16)
    }
}

$output = [System.Collections.Generic.List[string]]::new(6144)
Add-MemBank $output (Join-Path $fontDirectory 'Spleen8x16.mem')
Add-FontRows $output (Read-BdfFont (Join-Path $fontDirectory 'Tamzen8x16r.bdf')) $spleen
Add-MemBank $output (Join-Path $fontDirectory 'Terminus8x16.mem')

Set-Content -LiteralPath (Join-Path $RepoRoot 'rtl\management\manager_fonts.mem') `
    -Value $output -Encoding ascii
Write-Host "Generated $($output.Count) font bytes in rtl/management/manager_fonts.mem"
