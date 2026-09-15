param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\test-manager-osd'
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'rtl\management') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'rtl\management\manager_fonts.mem') -Destination (Join-Path $runDir 'rtl\management\manager_fonts.mem') -Force
Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" (Join-Path $repoRoot 'rtl\management\manager_font_rom.v') (Join-Path $repoRoot 'rtl\management\manager_osd.v') (Join-Path $repoRoot 'tb\manager_osd_tb.v')
    if($LASTEXITCODE){throw "xvlog failed: $LASTEXITCODE"}
    & "$VivadoBin\xelab.bat" manager_osd_tb -s manager_osd_sim --timescale 1ns/1ps
    if($LASTEXITCODE){throw "xelab failed: $LASTEXITCODE"}
    & "$VivadoBin\xsim.bat" manager_osd_sim -runall
    if($LASTEXITCODE){throw "xsim failed: $LASTEXITCODE"}
    if(-not(Select-String -LiteralPath xsim.log -SimpleMatch 'PASS: aligned frame, RGB logo, font styles, arrows, and selection')){throw 'manager OSD regression did not report PASS'}
} finally {Pop-Location}
