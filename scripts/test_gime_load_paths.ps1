param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$suiteDir = Join-Path $repoRoot 'build\sim\gime_load_paths'
$probeBin = Join-Path $suiteDir 'gime_reference.bin'
$probeMem = Join-Path $suiteDir 'gime_reference.bin.mem'
$diskLoaderBin = Join-Path $suiteDir 'gime_reference_dsk_loader.bin'
$diskLoaderMem = Join-Path $suiteDir 'gime_reference_dsk_loader.mem'
$diskImage = Join-Path $suiteDir 'gime_reference.dsk'
$diskMem = Join-Path $suiteDir 'gime_reference.dsk.mem'
$decb = Join-Path $repoRoot 'tools\toolshed\decb.exe'
$assembler = Join-Path $repoRoot 'tools\asm6809\asm6809.exe'

New-Item -ItemType Directory -Force -Path $suiteDir | Out-Null
if (-not (Test-Path -LiteralPath $decb -PathType Leaf)) {
    throw "ToolShed decb executable not found at $decb"
}
if (-not (Test-Path -LiteralPath $assembler -PathType Leaf)) {
    throw "asm6809 executable not found at $assembler"
}

& $assembler '-C' '-e' '0x6000' '-o' $probeBin `
    (Join-Path $repoRoot 'tb\asm\GIMEREF.asm')
if ($LASTEXITCODE -ne 0) { throw "GIME probe assembly failed: $LASTEXITCODE" }

$probeBytes = [System.IO.File]::ReadAllBytes($probeBin)
$probeLines = $probeBytes | ForEach-Object { '{0:X2}' -f $_ }
[System.IO.File]::WriteAllLines($probeMem, $probeLines,
    [System.Text.UTF8Encoding]::new($false))

& $assembler '-B' '-o' $diskLoaderBin `
    (Join-Path $repoRoot 'tb\asm\GIMEDSK.asm')
if ($LASTEXITCODE -ne 0) { throw "GIME DSK loader assembly failed: $LASTEXITCODE" }
$diskLoaderBytes = [System.IO.File]::ReadAllBytes($diskLoaderBin)
$diskLoaderLines = $diskLoaderBytes | ForEach-Object { '{0:X2}' -f $_ }
[System.IO.File]::WriteAllLines($diskLoaderMem, $diskLoaderLines,
    [System.Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $diskImage) {
    Remove-Item -LiteralPath $diskImage -Force
}
& $decb dskini $diskImage -3
if ($LASTEXITCODE -ne 0) { throw "decb dskini failed: $LASTEXITCODE" }
& $decb copy -2 -b $probeBin "${diskImage},GIMEREF.BIN"
if ($LASTEXITCODE -ne 0) { throw "decb copy failed: $LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath $diskImage -OutputPath $diskMem

& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\coco3.mem')
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
    -OutputPath (Join-Path $repoRoot 'build\roms\disk11.mem')

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $toolPath = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "$Tool was not found at: $toolPath"
    }
    & $toolPath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

function Clear-GeneratedSimulationFiles {
    param([string]$RunDirectory)
    $fullSuite = [System.IO.Path]::GetFullPath($suiteDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar)
    $fullRun = [System.IO.Path]::GetFullPath($RunDirectory)
    if (-not $fullRun.StartsWith(
            $fullSuite + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean path outside '$fullSuite': $fullRun"
    }
    foreach ($directoryName in @('xsim.dir', 'build')) {
        $directory = Join-Path $fullRun $directoryName
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
    Get-ChildItem -LiteralPath $fullRun -File | Where-Object {
        $_.Name -notin @('xvlog.log', 'xelab.log', 'xsim.log')
    } | Remove-Item -Force
}

$commonSources = @(
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
    'rtl\core\coco3_boot_machine.v'
)

function Invoke-LoadPathTest {
    param(
        [string]$Name,
        [string]$Top,
        [string]$TestBench,
        [string]$PassPattern,
        [switch]$DirectBin
    )
    $runDir = Join-Path $suiteDir $Name
    $romDir = Join-Path $runDir 'build\roms'
    New-Item -ItemType Directory -Force -Path $romDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\coco3.mem') `
        -Destination (Join-Path $romDir 'coco3.mem') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'build\roms\disk11.mem') `
        -Destination (Join-Path $romDir 'disk11.mem') -Force

    if ($DirectBin) {
        Copy-Item -LiteralPath $probeMem `
            -Destination (Join-Path $runDir 'gime_reference.bin.mem') -Force
        [System.IO.File]::WriteAllText(
            (Join-Path $runDir 'gime_reference_bin_size.vh'),
            "``define GIME_REFERENCE_BIN_SIZE $($probeBytes.Length)`n",
            [System.Text.UTF8Encoding]::new($false))
        & (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') `
            -OutputDirectory $runDir
        $loaderBytes = [System.IO.File]::ReadAllBytes(
            (Join-Path $runDir 'decb_bin_loader.bin'))
        $loaderLines = $loaderBytes | ForEach-Object { '{0:X2}' -f $_ }
        [System.IO.File]::WriteAllLines(
            (Join-Path $runDir 'decb_bin_loader.mem'), $loaderLines,
            [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText(
            (Join-Path $runDir 'decb_bin_loader_size.vh'),
            "``define DECB_BIN_LOADER_SIZE $($loaderBytes.Length)`n",
            [System.Text.UTF8Encoding]::new($false))
    } else {
        Copy-Item -LiteralPath $diskMem `
            -Destination (Join-Path $runDir 'gime_reference.dsk.mem') -Force
        Copy-Item -LiteralPath $diskLoaderMem `
            -Destination (Join-Path $runDir 'gime_reference_dsk_loader.mem') -Force
        [System.IO.File]::WriteAllText(
            (Join-Path $runDir 'gime_reference_dsk_loader_size.vh'),
            "``define GIME_REFERENCE_DSK_LOADER_SIZE $($diskLoaderBytes.Length)`n",
            [System.Text.UTF8Encoding]::new($false))
    }

    Push-Location $runDir
    try {
        $sources = $commonSources | ForEach-Object { Join-Path $repoRoot $_ }
        Invoke-VivadoTool xvlog @($sources + (Join-Path $repoRoot $TestBench))
        Invoke-VivadoTool xelab @($Top, '-s', "${Top}_sim")
        $simulationOutput = & (Join-Path $VivadoBin 'xsim.bat') `
            "${Top}_sim" '-runall' 2>&1
        $simulationExitCode = $LASTEXITCODE
        $simulationOutput | ForEach-Object { Write-Host $_ }
        $simulationText = $simulationOutput -join "`n"
        if ($simulationExitCode -ne 0 -or $simulationText -match 'Fatal:' -or
            $simulationText -notmatch [regex]::Escape($PassPattern)) {
            throw "$Name simulation failed with exit code $simulationExitCode"
        }
    }
    finally {
        Pop-Location
        Clear-GeneratedSimulationFiles -RunDirectory $runDir
    }
}

try {
    Invoke-LoadPathTest -Name 'direct_bin' -Top 'gime_reference_bin_load_tb' `
        -TestBench 'tb\gime_reference_bin_load_tb.v' -DirectBin `
        -PassPattern 'PASS: GIME reference probe loaded and executed through direct BIN path'

    Invoke-LoadPathTest -Name 'dsk_fdc' -Top 'gime_reference_dsk_load_tb' `
        -TestBench 'tb\gime_reference_dsk_load_tb.v' `
        -PassPattern 'PASS: GIME reference probe loaded and executed through DSK/FDC path'

    Write-Host 'PASS: GIME probe behaves identically through DSK and direct BIN loading' `
        -ForegroundColor Green
}
finally {
    # Keep only the compact Vivado logs under each run directory. The probe,
    # loader, and temporary disk are deterministic products rebuilt each run.
    foreach ($artifact in @($probeBin, $probeMem, $diskLoaderBin,
            $diskLoaderMem, $diskImage, $diskMem)) {
        if (Test-Path -LiteralPath $artifact -PathType Leaf) {
            Remove-Item -LiteralPath $artifact -Force
        }
    }
}
