param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\uart_video_trace'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
 & "$VivadoBin\xvlog.bat" "$repoRoot\rtl\wukong\uart_tx.v" "$repoRoot\rtl\wukong\coco3_uart_debug.v" "$repoRoot\tb\uart_video_trace_tb.v"
 if($LASTEXITCODE){throw 'UART compile failed'}
 & "$VivadoBin\xelab.bat" uart_video_trace_tb -s uart_video_trace_sim --timescale 1ns/1ps
 if($LASTEXITCODE){throw 'UART elaboration failed'}
 & "$VivadoBin\xsim.bat" uart_video_trace_sim -runall
 if($LASTEXITCODE -or -not(Select-String -Path xsim.log -SimpleMatch 'PASS: UART emits')){throw 'UART regression failed'}
} finally {Pop-Location}
