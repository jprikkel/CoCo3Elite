param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'build\test-video-frame-capture'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') `
        (Join-Path $repo 'rtl\wukong\video_frame_capture.v') `
        (Join-Path $repo 'tb\video_frame_capture_tb.v')
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') video_frame_capture_tb `
        -s video_frame_capture_sim --timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'xelab failed' }
    $output = & (Join-Path $VivadoBin 'xsim.bat') `
        video_frame_capture_sim -runall 2>&1
    $output | Write-Host
    if ($LASTEXITCODE -or ($output -join "`n") -notmatch
        'PASS: full-width RGB332 stripe capture') {
        throw 'xsim failed'
    }
} finally {
    Pop-Location
}
