param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\gime_1987_sim'
$artifactDir = Join-Path $repoRoot 'build\gime_1987_probe'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
& (Join-Path $PSScriptRoot 'build_gime_hardware_probe.ps1')

$binary = Join-Path $artifactDir 'GIMERAST.BIN'
$bytes = [System.IO.File]::ReadAllBytes($binary)
$byteLines = $bytes | ForEach-Object { '{0:X2}' -f $_ }
[System.IO.File]::WriteAllLines((Join-Path $runDir 'gime_hardware_probe.mem'),
    $byteLines, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $runDir 'gime_hardware_probe_size.vh'),
    "``define GIME_HARDWARE_PROBE_BIN_SIZE $($bytes.Length)`n",
    [System.Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $runDir
$loader = [System.IO.File]::ReadAllBytes((Join-Path $runDir 'decb_bin_loader.bin'))
$loaderLines = $loader | ForEach-Object { '{0:X2}' -f $_ }
[System.IO.File]::WriteAllLines((Join-Path $runDir 'decb_bin_loader.mem'),
    $loaderLines, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $runDir 'decb_bin_loader_size.vh'),
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
    'tb\gime_hardware_probe_tb.v'
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" @sources
    if ($LASTEXITCODE) { throw 'GIME hardware probe compile failed' }
    & "$VivadoBin\xelab.bat" gime_hardware_probe_tb `
        -s gime_hardware_probe_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'GIME hardware probe elaboration failed' }
    & "$VivadoBin\xsim.bat" gime_hardware_probe_sim -runall
    if ($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch `
            'PASS: 1987 GIME hardware probe loads, fills video RAM, and publishes telemetry')) {
        throw 'GIME hardware probe regression failed'
    }
} finally {
    Pop-Location
    $resolvedBuild = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot 'build')).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar)
    $resolvedRun = [System.IO.Path]::GetFullPath($runDir)
    if (-not $resolvedRun.StartsWith(
            $resolvedBuild + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRun) -ne 'gime_1987_sim') {
        throw "Refusing to clean unexpected simulation path: $resolvedRun"
    }
    if (Test-Path -LiteralPath $resolvedRun -PathType Container) {
        Remove-Item -LiteralPath $resolvedRun -Recurse -Force
    }
}
