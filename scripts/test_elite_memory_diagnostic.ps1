param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin',
    [ValidateSet('Comprehensive', 'Menu', 'Quick', 'Long', 'All')]
    [string]$Suite = 'Comprehensive'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\elite_memory_diagnostic'
$artifactDir = Join-Path $repoRoot 'build\diagnostics'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

try {
    & (Join-Path $PSScriptRoot 'build_elite_diagnostic.ps1')
    $cart = [System.IO.File]::ReadAllBytes(
        (Join-Path $artifactDir 'ELITEMEM.CCC'))
    if ($cart.Length -ne 8192) {
        throw "ELITEMEM cartridge must be exactly 8192 bytes; got $($cart.Length)"
    }
    [System.IO.File]::WriteAllLines(
        (Join-Path $runDir 'elite_memory_cart.mem'),
        ($cart | ForEach-Object { '{0:X2}' -f $_ }),
        [System.Text.UTF8Encoding]::new($false))

    $romDir = Join-Path $runDir 'build\roms'
    New-Item -ItemType Directory -Force -Path $romDir | Out-Null
    & (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
        -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
        -OutputPath (Join-Path $romDir 'coco3.mem')
    & (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
        -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
        -OutputPath (Join-Path $romDir 'disk11.mem')

    $sources = @(
        'rtl\third-party\MC6809\mc6809i.v',
        'rtl\core\cpu09.v',
        'rtl\core\coco3_128k_ram.v',
        'rtl\core\coco3_system_rom.v',
        'rtl\core\coco3_disk_rom.v',
        'rtl\core\coco3_sd_cartridge.v',
        'rtl\core\coco3_fdc.v',
        'rtl\core\coco3_keyboard_matrix.v',
        'rtl\core\coco3_gime_timer.v',
        'rtl\core\coco3_gime_interrupt.v',
        'rtl\core\coco3_boot_machine.v',
        'tb\elite_memory_diagnostic_tb.v'
    ) | ForEach-Object { Join-Path $repoRoot $_ }

    Push-Location $runDir
    try {
        & "$VivadoBin\xvlog.bat" @sources
        if ($LASTEXITCODE) { throw 'ELITEMEM compile failed' }
        & "$VivadoBin\xelab.bat" elite_memory_diagnostic_tb `
            -s elite_memory_diagnostic_sim --timescale 1ns/1ps
        if ($LASTEXITCODE) { throw 'ELITEMEM elaboration failed' }
        $suites = switch ($Suite) {
            'Quick' { ,@{ Name = 'QUICK'; Arguments = @(); SelectionOnly = $false; Count = 4 } }
            'Long' { ,@{ Name = 'LONG'; Arguments = @('SUITE_LONG'); SelectionOnly = $false; Count = 2 } }
            'All' { ,@{ Name = 'ALL'; Arguments = @('SUITE_ALL'); SelectionOnly = $false; Count = 6 } }
            'Menu' {
                @(
                    @{ Name = 'QUICK'; Arguments = @('SELECTION_ONLY'); SelectionOnly = $true },
                    @{ Name = 'LONG'; Arguments = @('SUITE_LONG', 'SELECTION_ONLY'); SelectionOnly = $true },
                    @{ Name = 'ALL'; Arguments = @('SUITE_ALL', 'SELECTION_ONLY'); SelectionOnly = $true }
                )
            }
            default {
                @(
                    @{ Name = 'QUICK'; Arguments = @(); SelectionOnly = $false; Count = 4 },
                    @{ Name = 'LONG'; Arguments = @('SUITE_LONG'); SelectionOnly = $false; Count = 2 },
                    @{ Name = 'ALL'; Arguments = @('SUITE_ALL', 'SELECTION_ONLY'); SelectionOnly = $true }
                )
            }
        }
        foreach ($suiteCase in $suites) {
            $arguments = @('elite_memory_diagnostic_sim', '-runall')
            foreach ($argument in $suiteCase.Arguments) {
                $arguments += @('-testplusarg', $argument)
            }
            & "$VivadoBin\xsim.bat" @arguments
            $success = if ($suiteCase.SelectionOnly) {
                "$($suiteCase.Name) menu selection"
            } else {
                "$($suiteCase.Name) suite reported $($suiteCase.Count) passing full-memory tests"
            }
            if ($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch $success)) {
                throw "ELITEMEM $($suiteCase.Name) regression failed"
            }
        }
    } finally {
        Pop-Location
    }
} finally {
    $resolvedBuild = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot 'build')).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar)
    $resolvedRun = [System.IO.Path]::GetFullPath($runDir)
    if (-not $resolvedRun.StartsWith(
            $resolvedBuild + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRun) -ne 'elite_memory_diagnostic') {
        throw "Refusing to clean unexpected simulation path: $resolvedRun"
    }
    if (Test-Path -LiteralPath $resolvedRun -PathType Container) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
