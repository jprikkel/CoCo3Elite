param(
    [Parameter(Mandatory)]
    [string]$Path,
    [string]$ComparePath
)

$ErrorActionPreference = 'Stop'

function Convert-Hex([string]$Value) {
    return [Convert]::ToUInt32($Value, 16)
}

function Read-GimeTrace([string]$TracePath) {
    $absolute = [System.IO.Path]::GetFullPath($TracePath)
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "Trace not found: $absolute"
    }
    $pattern = '^PC=(?<pc>[0-9A-F]{4}).*? V=(?<video>[0-9A-F]{40}) I=(?<irq>[0-9A-F]{2}) L=(?<line>[0-9A-F]{3}) Q=(?<rowline>[0-9A-F]) B=(?<flags>[0-9A-F]) A=(?<row>[0-9A-F]{6}) N=(?<writes>[0-9A-F]{4}) H=(?<hsync>[0-9A-F]{4}) W=(?<waddr>[0-9A-F]{2}):(?<wdata>[0-9A-F]{2})@(?<wpc>[0-9A-F]{4})/(?<wline>[0-9A-F]{3}) M=(?<mailbox>[0-9A-F]{16})$'
    $records = foreach ($lineText in [System.IO.File]::ReadLines($absolute)) {
        if ($lineText -match $pattern) {
            $video = $Matches.video
            [pscustomobject]@{
                PC = $Matches.pc
                VMODE = $video.Substring(0, 2)
                VRES = $video.Substring(2, 2)
                VBANK = $video.Substring(4, 2)
                Offset = $video.Substring(6, 4)
                HOffset = $video.Substring(10, 2)
                Line = Convert-Hex $Matches.line
                RowLine = Convert-Hex $Matches.rowline
                Flags = $Matches.flags
                RowAddress = $Matches.row
                GimeWrites = Convert-Hex $Matches.writes
                LogicalHsyncs = Convert-Hex $Matches.hsync
                LastWrite = "$($Matches.waddr):$($Matches.wdata)@$($Matches.wpc)/$($Matches.wline)"
                Mailbox = $Matches.mailbox
                Interrupt = $Matches.irq
            }
        }
    }
    if (-not $records) {
        throw "No extended GIME telemetry records found in $absolute. Capture with a telemetry-enabled bitstream."
    }
    return ,$records
}

function Show-Summary([string]$Name, [object[]]$Records) {
    $writes = ($Records | Measure-Object -Property GimeWrites -Sum).Sum
    $hsyncAverage = [math]::Round(
        ($Records | Measure-Object -Property LogicalHsyncs -Average).Average, 1)
    Write-Host "$Name records=$($Records.Count) GIME-writes=$writes average-logical-HSYNC/s=$hsyncAverage"
    Write-Host '  Video states (VMODE VRES VBANK OFFSET HOFFSET):'
    $Records | Group-Object VMODE,VRES,VBANK,Offset,HOffset | Sort-Object Count -Descending |
        ForEach-Object { Write-Host ("    {0,4}  {1}" -f $_.Count, $_.Name) }
    Write-Host '  Last-write samples:'
    $Records | Group-Object LastWrite | Sort-Object Count -Descending | Select-Object -First 12 |
        ForEach-Object { Write-Host ("    {0,4}  {1}" -f $_.Count, $_.Name) }
    $mailboxes = $Records | Where-Object Mailbox -ne '0000000000000000' |
        Select-Object -ExpandProperty Mailbox -Unique
    if ($mailboxes) {
        Write-Host "  Probe mailbox records: $($mailboxes -join ', ')"
        foreach ($mailbox in $mailboxes) {
            switch ($mailbox.Substring(0, 2)) {
                '53' {
                    Write-Host ("    ELITEDIAG summary total={0} passes={1} failures={2}" -f `
                        (Convert-Hex $mailbox.Substring(2, 2)),
                        (Convert-Hex $mailbox.Substring(6, 2)),
                        (Convert-Hex $mailbox.Substring(8, 2)))
                }
                '44' {
                    $result = if ($mailbox.Substring(4, 2) -eq '00') { 'PASS' } else { 'FAIL' }
                    Write-Host ("    ELITEDIAG test={0} {1} passes={2} failures={3}" -f `
                        (Convert-Hex $mailbox.Substring(2, 2)), $result,
                        (Convert-Hex $mailbox.Substring(6, 2)),
                        (Convert-Hex $mailbox.Substring(8, 2)))
                }
                '4D' {
                    Write-Host '    ELITEMEM menu ready (Q=quick, L=long, A=all)'
                }
                '50' {
                    $mode = switch ($mailbox.Substring(2, 2)) {
                        '40' { 'QUICK' }
                        '80' { 'LONG' }
                        'C0' { 'ALL' }
                        default { "UNKNOWN/$($mailbox.Substring(2, 2))" }
                    }
                    Write-Host "    ELITEMEM suite started: $mode"
                }
                '51' {
                    $result = if ($mailbox.Substring(4, 2) -eq '00') { 'PASS' } else { 'FAIL' }
                    Write-Host ("    ELITEMEM phase={0} {1} code={2}" -f `
                        (Convert-Hex $mailbox.Substring(2, 2)), $result,
                        $mailbox.Substring(4, 2))
                }
                '52' {
                    Write-Host ("    ELITEMEM first failure page={0} address={1} value={2}" -f `
                        (Convert-Hex $mailbox.Substring(6, 2)),
                        $mailbox.Substring(8, 4), $mailbox.Substring(12, 4))
                }
                '54' {
                    Write-Host '    ELITEMEM March initialization complete'
                }
                '49' {
                    Write-Host ("    INIT S={0} DP={1} CC={2} FF90={3} FF91={4} warm={5}" -f `
                        $mailbox.Substring(2, 4), $mailbox.Substring(6, 2),
                        $mailbox.Substring(8, 2), $mailbox.Substring(10, 2),
                        $mailbox.Substring(12, 2), $mailbox.Substring(14, 2))
                }
                '42' {
                    Write-Host ("    LPR frame={0} hold={1}-{2} HBORD={3} FF98={4} FF99={5}" -f `
                        (Convert-Hex $mailbox.Substring(2, 2)),
                        (Convert-Hex $mailbox.Substring(4, 2)),
                        (Convert-Hex $mailbox.Substring(6, 2)),
                        (Convert-Hex $mailbox.Substring(8, 4)),
                        $mailbox.Substring(12, 2), $mailbox.Substring(14, 2))
                }
                '47' {
                    Write-Host ("    RASTER phase={0} frame={1} HBORD={2} FF98={3} FF99={4} FF9F={5}" -f `
                        (Convert-Hex $mailbox.Substring(2, 2)),
                        (Convert-Hex $mailbox.Substring(4, 2)),
                        (Convert-Hex $mailbox.Substring(6, 4)),
                        $mailbox.Substring(10, 2), $mailbox.Substring(12, 2),
                        $mailbox.Substring(14, 2))
                }
            }
        }
    }
}

$primary = Read-GimeTrace $Path
Show-Summary ([System.IO.Path]::GetFileName($Path)) $primary

if ($ComparePath) {
    $comparison = Read-GimeTrace $ComparePath
    Show-Summary ([System.IO.Path]::GetFileName($ComparePath)) $comparison
    Write-Host 'Comparison:'
    Write-Host "  GIME writes: $((($primary | Measure-Object GimeWrites -Sum).Sum)) vs $((($comparison | Measure-Object GimeWrites -Sum).Sum))"
    Write-Host "  Unique video states: $(($primary | Group-Object VMODE,VRES,VBANK,Offset,HOffset).Count) vs $(($comparison | Group-Object VMODE,VRES,VBANK,Offset,HOffset).Count)"
}
