$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat'
& $vivado -mode batch -nojournal -nolog -source (Join-Path $repo 'scripts\program_wukong_manager_sd_fat32.tcl')
if ($LASTEXITCODE) { throw "Wukong JTAG programming failed: $LASTEXITCODE" }
