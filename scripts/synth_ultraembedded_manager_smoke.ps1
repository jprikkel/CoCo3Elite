param(
    [string]$VivadoBin = "C:\AMD\2025.2\Vivado\bin"
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
& (Join-Path $VivadoBin 'vivado.bat') -mode batch -nojournal -nolog `
    -source (Join-Path $repo 'scripts\synth_ultraembedded_manager_smoke.tcl')
if ($LASTEXITCODE) { throw "UltraEmbedded management synthesis failed: $LASTEXITCODE" }
