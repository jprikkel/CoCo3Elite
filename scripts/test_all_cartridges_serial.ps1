param(
    [string]$Port = 'COM5',
    [ValidateRange(1, 31)][int]$StartIndex = 1,
    [ValidateRange(1, 31)][int]$EndIndex = 31,
    [ValidateRange(10, 300)][int]$GameplaySeconds = 45,
    [string]$OutputDirectory = 'build\test-output\cartridges'
)

$ErrorActionPreference = 'Stop'
if ($EndIndex -lt $StartIndex) { throw 'EndIndex must be at least StartIndex' }
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$resultsPath = Join-Path $OutputDirectory 'results-automated.csv'

$cartridges = @(
    'Androne 1983',
    'Downland v1.1',
    'Music 1980',
    'Reactoid 1983 variant',
    'Reactoid 1983',
    'Temple of ROM',
    'Mega-Bug 1982',
    'Galactic Attack 1982',
    'Dungeons of Daggorath Shield Fix',
    'Dungeons of Daggorath 1982',
    'Dino Wars 1981',
    'Diagnostics v2.0',
    'Diagnostics 1980',
    'Downland v1.0',
    'Skiing 1981',
    'ZIADIAG',
    'Bustout 1981',
    'Stellar Lifeline 1983',
    'Starblaze 1983',
    'Spidercide 1983',
    'Spectaculator 1983',
    'Slay the Nereis 1983',
    'SDS80C 1981',
    'Roman Checkers 1981',
    'Panic Button 1983',
    'Gomoku-Renju 1983',
    'Fraction Fever 1984',
    'Direct Connect Modem Pak 1985',
    'Demolition Derby 1984',
    'Color Baseball 1980',
    'CoCo Tuner'
)

$results = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $resultsPath) {
    foreach ($row in @(Import-Csv -LiteralPath $resultsPath)) { $results.Add($row) }
}

for ($index = $StartIndex; $index -le $EndIndex; $index++) {
    $name = $cartridges[$index - 1]
    $slug = ('{0:D2}-{1}' -f $index, ($name -replace '[^A-Za-z0-9._-]', '-'))
    Write-Host ("BEGIN {0:D2}/31 {1}" -f $index, $name)
    $started = Get-Date
    $health = 'ERROR'
    $detail = ''
    try {
        $lines = @(& (Join-Path $PSScriptRoot 'test_cartridge_serial.ps1') `
            -Port $Port -CartIndex $index -Name $slug `
            -GameplaySeconds $GameplaySeconds -OutputDirectory $OutputDirectory `
            -Quiet *>&1 | ForEach-Object { "$_" })
        foreach ($line in $lines) {
            if ($line -match '^(CONFIRMED|RESULT|PASS: captured|PNG:|TRACE)') {
                Write-Host $line
            }
            if ($line -match '^RESULT (PASS|WARN|FAIL) ') {
                $health = $Matches[1]
                $detail = $line
            }
        }
        if ($health -eq 'ERROR') { $detail = 'No RESULT line returned' }
    } catch {
        $detail = $_.Exception.Message
        Write-Warning $detail
    }
    $results.Add([pscustomobject]@{
        Index = $index
        Name = $name
        AutomatedHealth = $health
        Detail = $detail
        Screenshot = "$slug.png"
        Trace = "$slug.log"
        DurationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        TestedAt = (Get-Date).ToString('o')
    })
    @($results | Group-Object Index | ForEach-Object { $_.Group[-1] } |
        Sort-Object { [int]$_.Index }) | Export-Csv -NoTypeInformation `
        -LiteralPath $resultsPath
    Write-Host ("END {0:D2}/31 health={1}" -f $index, $health)
}

Write-Host "RESULTS $resultsPath"
