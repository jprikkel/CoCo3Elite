param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\boot_machine'
$romImage = Join-Path $repoRoot 'build\roms\coco3.mem'
$diskRomImage = Join-Path $repoRoot 'build\roms\disk11.mem'
$diskImage = Join-Path $repoRoot 'build\disks\intruders.mem'
$disk1Image = Join-Path $repoRoot 'build\disks\daggorat.mem'

& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath $romImage
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\disk11.rom') `
    -OutputPath $diskRomImage
& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath (Join-Path $repoRoot 'disks\INTRUDERS.DSK') `
    -OutputPath $diskImage
& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath (Join-Path $repoRoot 'disks\DAGGORAT.DSK') `
    -OutputPath $disk1Image

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\disks') | Out-Null
Copy-Item -LiteralPath $romImage -Destination (Join-Path $runDir 'build\roms\coco3.mem') -Force
Copy-Item -LiteralPath $diskRomImage -Destination (Join-Path $runDir 'build\roms\disk11.mem') -Force
Copy-Item -LiteralPath $diskImage -Destination (Join-Path $runDir 'build\disks\intruders.mem') -Force
Copy-Item -LiteralPath $disk1Image -Destination (Join-Path $runDir 'build\disks\daggorat.mem') -Force

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
    Invoke-VivadoTool xvhdl @('--2008', (Join-Path $repoRoot 'rtl\cpu09l_128.vhd'))
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_system_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_disk_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_disk_image.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_keyboard_matrix.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_boot_machine.v'),
        (Join-Path $repoRoot 'tb\boot_machine_tb.v')
    )
    Invoke-VivadoTool xelab @('boot_machine_tb', '-s', 'boot_machine_tb_sim')
    Invoke-VivadoTool xsim @('boot_machine_tb_sim', '-runall')
} finally {
    Pop-Location
}
