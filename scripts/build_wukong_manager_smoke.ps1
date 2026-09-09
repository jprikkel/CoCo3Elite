param(
    [string]$Vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Vivado)) { throw "Vivado was not found at: $Vivado" }
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$env:XILINX_TCLAPP_REPO = Join-Path $vivadoRoot 'data\XilinxTclStore'
$env:XILINX_LOCAL_USER_DATA = 'NO'
& $Vivado -mode batch -nojournal -nolog `
    -source (Join-Path $repo 'scripts\build_wukong_manager_smoke.tcl')
if ($LASTEXITCODE) { throw "Wukong manager smoke build failed: $LASTEXITCODE" }
