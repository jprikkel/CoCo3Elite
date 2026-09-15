param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\test-ntsc-artifact'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" `
        (Join-Path $repoRoot 'rtl\wukong\ntsc_artifact_filter.v') `
        (Join-Path $repoRoot 'tb\ntsc_artifact_filter_tb.v')
    if($LASTEXITCODE){throw "xvlog failed: $LASTEXITCODE"}
    & "$VivadoBin\xelab.bat" ntsc_artifact_filter_tb -s artifact_sim --timescale 1ns/1ps
    if($LASTEXITCODE){throw "xelab failed: $LASTEXITCODE"}
    & "$VivadoBin\xsim.bat" artifact_sim -runall
    if($LASTEXITCODE){throw "xsim failed: $LASTEXITCODE"}
    if(-not(Select-String -LiteralPath xsim.log -SimpleMatch 'PASS: NTSC artifact filter')){
        throw 'artifact filter regression did not report PASS'
    }
} finally { Pop-Location }
