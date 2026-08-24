param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\boot_machine'
$romImage = Join-Path $repoRoot 'build\roms\coco3.mem'

& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
    -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
    -OutputPath $romImage

New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
Copy-Item -LiteralPath $romImage -Destination (Join-Path $runDir 'build\roms\coco3.mem') -Force

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
        (Join-Path $repoRoot 'rtl\core\coco3_keyboard_matrix.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_boot_machine.v'),
        (Join-Path $repoRoot 'tb\boot_machine_tb.v')
    )
    Invoke-VivadoTool xelab @('boot_machine_tb', '-s', 'boot_machine_tb_sim')
    Invoke-VivadoTool xsim @('boot_machine_tb_sim', '-runall')
} finally {
    Pop-Location
}
