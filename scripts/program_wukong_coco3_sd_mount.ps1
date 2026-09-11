$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat'
& $vivado -mode batch -nojournal -nolog -source (Join-Path $PSScriptRoot 'program_wukong_coco3_sd_mount.tcl')
if ($LASTEXITCODE) { throw "CoCo SD mount JTAG programming failed: $LASTEXITCODE" }
