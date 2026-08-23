param(
    [string]$Vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat',
    [string]$Part = 'xc7a100tfgg676-2',
    [ValidateSet('TEST_PATTERN', 'COCO_VIDEO', 'CPU_DIAGNOSTIC')]
    [string]$Mode = 'TEST_PATTERN'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado was not found at: $Vivado"
}

# This installation's per-user Tcl Store catalog is corrupt. Use the bundled
# store directly and disable the per-user cache for a reproducible batch run.
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$env:XILINX_TCLAPP_REPO = Join-Path $vivadoRoot 'data\XilinxTclStore'
$env:XILINX_LOCAL_USER_DATA = 'NO'

& $Vivado -mode batch -nojournal -nolog `
    -source scripts/build_wukong.tcl -tclargs $Part $Mode

if ($LASTEXITCODE -ne 0) {
    throw "Vivado failed with exit code $LASTEXITCODE"
}
