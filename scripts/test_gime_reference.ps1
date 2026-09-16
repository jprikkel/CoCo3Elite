param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$suiteDir = Join-Path $repoRoot 'build\sim\gime_reference'
$systemRomSourceDir = Join-Path $suiteDir '_roms'
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-VivadoTool {
    param(
        [string]$Tool,
        [string[]]$Arguments
    )
    $toolPath = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "$Tool was not found at: $toolPath"
    }
    & $toolPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE"
    }
}

function Clear-GimeTestArtifacts {
    param([string]$RunDirectory)

    $fullSuite = [System.IO.Path]::GetFullPath($suiteDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar)
    $fullRun = [System.IO.Path]::GetFullPath($RunDirectory)
    $requiredPrefix = $fullSuite + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullRun.StartsWith($requiredPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean test directory outside '$fullSuite': $fullRun"
    }

    # Keep the three useful text logs and discard generated snapshots,
    # copied ROMs, journals, protocol buffers, and crash backups.
    foreach ($directoryName in @('xsim.dir', 'build', 'rtl')) {
        $directory = Join-Path $fullRun $directoryName
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
    Get-ChildItem -LiteralPath $fullRun -File | Where-Object {
        $_.Name -notin @('xvlog.log', 'xelab.log', 'xsim.log')
    } | Remove-Item -Force
}

function Invoke-GimeTest {
    param(
        [string]$Name,
        [string]$Top,
        [string]$PassPattern,
        [string[]]$Sources,
        [string[]]$Defines = @(),
        [switch]$NeedsCharacterRom,
        [switch]$NeedsSystemRoms
    )

    $runDir = Join-Path $suiteDir $Name
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    if ($NeedsCharacterRom) {
        $romDir = Join-Path $runDir 'rtl\core'
        New-Item -ItemType Directory -Force -Path $romDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\core\coco3gen.mem') `
            -Destination (Join-Path $romDir 'coco3gen.mem') -Force
    }
    if ($NeedsSystemRoms) {
        $systemRomDir = Join-Path $runDir 'build\roms'
        New-Item -ItemType Directory -Force -Path $systemRomDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $systemRomSourceDir 'coco3.mem') `
            -Destination (Join-Path $systemRomDir 'coco3.mem') -Force
        Copy-Item -LiteralPath (Join-Path $systemRomSourceDir 'disk11.mem') `
            -Destination (Join-Path $systemRomDir 'disk11.mem') -Force
    }

    Push-Location $runDir
    try {
        $compileArguments = [System.Collections.Generic.List[string]]::new()
        foreach ($define in $Defines) {
            $compileArguments.Add('-d')
            $compileArguments.Add($define)
        }
        foreach ($source in $Sources) {
            $compileArguments.Add((Join-Path $repoRoot $source))
        }
        Invoke-VivadoTool xvlog $compileArguments.ToArray()
        Invoke-VivadoTool xelab @($Top, '-s', "${Top}_sim")
        Invoke-VivadoTool xsim @("${Top}_sim", '-runall')
        if (Select-String -LiteralPath 'xsim.log' -SimpleMatch 'Fatal:') {
            throw 'simulation reported a fatal conformance failure'
        }
        if (-not (Select-String -LiteralPath 'xsim.log' -SimpleMatch $PassPattern)) {
            throw "simulation did not report: $PassPattern"
        }
        Write-Host "PASS $Name" -ForegroundColor Green
    }
    catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Host "FAIL $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Pop-Location
        Clear-GimeTestArtifacts -RunDirectory $runDir
    }
}

Invoke-GimeTest -Name 'timer' -Top 'gime_reference_timer_tb' `
    -PassPattern 'PASS: GIME timer write, reload, source, and stop behavior' -Sources @(
    'rtl\core\coco3_gime_timer.v',
    'tb\gime_reference_timer_tb.v'
)

Invoke-GimeTest -Name 'interrupt' -Top 'gime_reference_interrupt_tb' `
    -PassPattern 'PASS: all six GIME sources latch, mask, route, and acknowledge' -Sources @(
    'rtl\core\coco3_gime_interrupt.v',
    'tb\gime_reference_interrupt_tb.v'
)

New-Item -ItemType Directory -Force -Path $systemRomSourceDir | Out-Null
& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath (Join-Path $systemRomSourceDir 'coco3.mem')
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
    -OutputPath (Join-Path $systemRomSourceDir 'disk11.mem')

Invoke-GimeTest -Name 'sync_cadence' -Top 'gime_reference_sync_cadence_tb' `
    -PassPattern 'PASS: GIME HBORD and slow timer use logical CoCo HSYNC only' `
    -NeedsSystemRoms -Sources @(
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
        'tb\gime_reference_sync_cadence_tb.v'
    )

Invoke-GimeTest -Name 'video' -Top 'gime_reference_video_tb' `
    -PassPattern 'PASS: GIME LPF, LPR, HRES, and HVEN reference behavior' `
    -Defines @('NEW_SRAM', 'HDMI_RASTER_800X525') -NeedsCharacterRom -Sources @(
        'rtl\core\coco3_char_rom.v',
        'rtl\third-party\coco3fpga\coco3vid.v',
        'tb\gime_reference_video_tb.v'
    )

if (Test-Path -LiteralPath $systemRomSourceDir -PathType Container) {
    Remove-Item -LiteralPath $systemRomSourceDir -Recurse -Force
}

if ($failures.Count -ne 0) {
    Write-Host ''
    Write-Host 'GIME reference conformance failures:' -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  $failure"
    }
    throw "$($failures.Count) GIME reference test group(s) failed"
}

Write-Host 'PASS: all GIME reference test groups' -ForegroundColor Green
