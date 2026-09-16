param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\elite_diagnostic'
$artifactDir = Join-Path $repoRoot 'build\diagnostics'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

try {
    & (Join-Path $PSScriptRoot 'build_elite_diagnostic.ps1')
    $binary = Join-Path $artifactDir 'ELITEDIAG.BIN'
    $bytes = [System.IO.File]::ReadAllBytes($binary)
    $byteLines = $bytes | ForEach-Object { '{0:X2}' -f $_ }
    [System.IO.File]::WriteAllLines(
        (Join-Path $runDir 'elite_diagnostic.mem'), $byteLines,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $runDir 'elite_diagnostic_size.vh'),
        "``define ELITE_DIAGNOSTIC_BIN_SIZE $($bytes.Length)`n",
        [System.Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $runDir
    $loader = [System.IO.File]::ReadAllBytes(
        (Join-Path $runDir 'decb_bin_loader.bin'))
    $loaderLines = $loader | ForEach-Object { '{0:X2}' -f $_ }
    [System.IO.File]::WriteAllLines(
        (Join-Path $runDir 'decb_bin_loader.mem'), $loaderLines,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $runDir 'decb_bin_loader_size.vh'),
        "``define DECB_BIN_LOADER_SIZE $($loader.Length)`n",
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
        'tb\elite_diagnostic_tb.v'
    ) | ForEach-Object { Join-Path $repoRoot $_ }

    Push-Location $runDir
    try {
        & "$VivadoBin\xvlog.bat" @sources
        if ($LASTEXITCODE) { throw 'ELITEDIAG compile failed' }
        & "$VivadoBin\xelab.bat" elite_diagnostic_tb `
            -s elite_diagnostic_sim --timescale 1ns/1ps
        if ($LASTEXITCODE) { throw 'ELITEDIAG elaboration failed' }
        & "$VivadoBin\xsim.bat" elite_diagnostic_sim -runall
        # Vivado 2025.2 on Windows can report success from xsim.bat even when
        # its just-created simulation child process loses a startup race.
        # Retry that specific transient failure once; assertion failures still
        # fail immediately below.
        if ((Test-Path -LiteralPath 'xsim.log') -and
            (Select-String -Path 'xsim.log' -SimpleMatch `
                'Simulation engine failed to start' -Quiet)) {
            Start-Sleep -Milliseconds 500
            & "$VivadoBin\xsim.bat" elite_diagnostic_sim -runall
        }
        if ($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch `
                'PASS: ELITEDIAG paged report produced 22 PASS results in native 80-column text')) {
            throw 'ELITEDIAG regression failed'
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
        (Split-Path -Leaf $resolvedRun) -ne 'elite_diagnostic') {
        throw "Refusing to clean unexpected simulation path: $resolvedRun"
    }
    if (Test-Path -LiteralPath $resolvedRun -PathType Container) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
