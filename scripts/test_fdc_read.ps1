param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\fdc_read'
$drive0Image = Join-Path $repoRoot 'build\disks\intruders.mem'
$drive1Image = Join-Path $repoRoot 'build\disks\daggorat.mem'

& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath (Join-Path $repoRoot 'disks\INTRUDERS.DSK') `
    -OutputPath $drive0Image
& (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
    -InputPath (Join-Path $repoRoot 'disks\DAGGORAT.DSK') `
    -OutputPath $drive1Image

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\disks') | Out-Null
Copy-Item -LiteralPath $drive0Image -Destination (Join-Path $runDir 'build\disks\intruders.mem') -Force
Copy-Item -LiteralPath $drive1Image -Destination (Join-Path $runDir 'build\disks\daggorat.mem') -Force

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
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_disk_image.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'tb\fdc_read_tb.v')
    )
    Invoke-VivadoTool xelab @('fdc_read_tb', '-s', 'fdc_read_tb_sim')
    Invoke-VivadoTool xsim @('fdc_read_tb_sim', '-runall')
} finally {
    Pop-Location
}
