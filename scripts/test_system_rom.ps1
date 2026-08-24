param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\system_rom'
$romImage = Join-Path $repoRoot 'build\roms\coco3.mem'

if (-not (Test-Path -LiteralPath $romImage -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') `
        -InputPath (Join-Path $repoRoot 'roms\coco3.rom') `
        -OutputPath $romImage
}

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
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_system_rom.v'),
        (Join-Path $repoRoot 'tb\system_rom_tb.v')
    )
    Invoke-VivadoTool xelab @('system_rom_tb', '-s', 'system_rom_tb_sim')
    Invoke-VivadoTool xsim @('system_rom_tb_sim', '-runall')
} finally {
    Pop-Location
}
