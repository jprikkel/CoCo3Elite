$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$out=Join-Path $repoRoot 'build\tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
& "$repoRoot\tools\asm6809\asm6809.exe" -C -d ORIGIN=24576 -e 24576 -o "$out\zenfill.bin" -l "$out\zenfill.lst" "$repoRoot\tb\asm\ZENFILL.asm"
if($LASTEXITCODE){throw 'Zenix-derived helper assembly failed'}
