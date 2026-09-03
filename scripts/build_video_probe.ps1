param([switch]$Simulation)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$out=Join-Path $repoRoot 'build\tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$name=if($Simulation){'vidhelp_sim'}else{'vidhelp'}
$argsList=@('-C','-e','0x6000','-o',(Join-Path $out "$name.bin"),'-l',(Join-Path $out "$name.lst"))
if($Simulation){$argsList+=@('-d','WAIT_COUNT=4','-d','WAIT_OUTER=1')}
else {$argsList+=@('-d','WAIT_COUNT=65535','-d','WAIT_OUTER=8')}
& (Join-Path $repoRoot 'tools\asm6809\asm6809.exe') @argsList (Join-Path $repoRoot 'tb\asm\VIDPROBE.asm')
if($LASTEXITCODE -ne 0){throw 'Video probe assembly failed'}
Write-Host "Built $out\$name.bin"
