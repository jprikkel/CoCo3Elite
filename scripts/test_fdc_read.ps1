param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\fdc_read'
$diskDir = Join-Path $repoRoot 'build\disks'
$decb = Join-Path $repoRoot 'tools\toolshed\decb.exe'
$drive0Dsk = Join-Path $diskDir 'fdc_test0.dsk'
$drive1Dsk = Join-Path $diskDir 'fdc_test1.dsk'
$drive0Image = Join-Path $diskDir 'fdc_test0.mem'
$drive1Image = Join-Path $diskDir 'fdc_test1.mem'

if (-not (Test-Path -LiteralPath $decb -PathType Leaf)) {
    throw "ToolShed decb executable not found at $decb"
}
New-Item -ItemType Directory -Force -Path $diskDir | Out-Null

foreach ($disk in @($drive0Dsk, $drive1Dsk)) {
    if (Test-Path -LiteralPath $disk) { Remove-Item -LiteralPath $disk -Force }
    & $decb dskini $disk -3
    if ($LASTEXITCODE -ne 0) { throw "decb dskini failed for $disk" }
}

# Populate directory sector 3 with deterministic entries.  The contents are
# irrelevant to the FDC test; only the DECB directory name/type fields matter.
$source = Join-Path $repoRoot 'tb\basic\TESTMENU.BAS'
& $decb copy $source "$drive0Dsk,FDCREAD.BAS"
if ($LASTEXITCODE -ne 0) { throw 'decb copy failed for FDCREAD.BAS' }
& $decb copy -2 -b $source "$drive1Dsk,FDCREAD2.BIN"
if ($LASTEXITCODE -ne 0) { throw 'decb copy failed for FDCREAD2.BIN' }

& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath $drive0Dsk `
    -OutputPath $drive0Image
& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath $drive1Dsk `
    -OutputPath $drive1Image

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\disks') | Out-Null
Copy-Item -LiteralPath $drive0Image -Destination (Join-Path $runDir 'build\disks\fpgatest.mem') -Force
Copy-Item -LiteralPath $drive1Image -Destination (Join-Path $runDir 'build\disks\games.mem') -Force

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    $path = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$Tool was not found at: $path"
    }
    & $path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE"
    }
}

Push-Location $runDir
try {
    Invoke-VivadoTool xvlog @('-d', 'EMBEDDED_TEST_DISKS',
        (Join-Path $repoRoot 'rtl\core\coco3_disk_image.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'tb\fdc_read_tb.v')
    )
    Invoke-VivadoTool xelab @('fdc_read_tb', '-s', 'fdc_read_tb_sim')
    Invoke-VivadoTool xsim @('fdc_read_tb_sim', '-runall')
} finally {
    Pop-Location
}
