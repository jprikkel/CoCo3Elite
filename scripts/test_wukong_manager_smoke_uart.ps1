param(
    [string]$VivadoBin = "C:\AMD\2025.2\Vivado\bin"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo "build\test_wukong_manager_smoke_uart"
$core = Join-Path $repo "rtl\third-party\ultraembedded-riscv\core\riscv"
$tcm = Join-Path $repo "rtl\third-party\ultraembedded-riscv\top_tcm_axi\src_v"
New-Item -ItemType Directory -Force $work | Out-Null

$sources = @()
$sources += Get-ChildItem $core -Filter '*.v' | Sort-Object Name | ForEach-Object FullName
$sources += Get-ChildItem $tcm -Filter '*.v' | Sort-Object Name | ForEach-Object FullName
$sources += Join-Path $repo 'rtl\management\ultraembedded_manager_smoke.v'
$sources += Join-Path $repo 'rtl\management\wukong_manager_smoke_top.v'
$sources += Join-Path $repo 'rtl\wukong\uart_tx.v'
$sources += Join-Path $repo 'tb\wukong_manager_smoke_uart_tb.v'

Push-Location $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') -i $core $sources
    if ($LASTEXITCODE) { throw "xvlog failed" }
    & (Join-Path $VivadoBin 'xelab.bat') wukong_manager_smoke_uart_tb -s wukong_manager_smoke_uart_tb_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw "xelab failed" }
    & (Join-Path $VivadoBin 'xsim.bat') wukong_manager_smoke_uart_tb_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed" }
} finally {
    Pop-Location
}
