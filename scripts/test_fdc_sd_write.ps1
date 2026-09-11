param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('coco3elite-fdc-write-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repo 'rtl\core\coco3_fdc.v') `
        (Join-Path $repo 'tb\fdc_sd_write_tb.v')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') fdc_sd_write_tb `
        -s fdc_sd_write_tb_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'xelab failed' }
    $output = & (Join-Path $VivadoBin 'xsim.bat') `
        fdc_sd_write_tb_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch `
        'PASS: FDC write cache transfer and flush acknowledgement') {
        throw 'xsim failed'
    }
} finally {
    Pop-Location
    $resolvedWork = [System.IO.Path]::GetFullPath($work)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedWork.StartsWith($resolvedTemp,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean test path outside temp: $resolvedWork"
    }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}
