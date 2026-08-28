param(
    [string]$VivadoBin = "C:\AMD\2025.2\Vivado\bin"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo "build\test_sd_spi_init"
New-Item -ItemType Directory -Force $work | Out-Null

Push-Location $work
try {
    & (Join-Path $VivadoBin "xvlog.bat") (Join-Path $repo "rtl\core\sd_spi_init.v") (Join-Path $repo "tb\sd_spi_init_tb.v")
    if ($LASTEXITCODE) { throw "xvlog failed" }
    & (Join-Path $VivadoBin "xelab.bat") sd_spi_init_tb -s sd_spi_init_tb_sim
    if ($LASTEXITCODE) { throw "xelab failed" }
    & (Join-Path $VivadoBin "xsim.bat") sd_spi_init_tb_sim -runall
    if ($LASTEXITCODE) { throw "xsim failed" }
} finally {
    Pop-Location
}
