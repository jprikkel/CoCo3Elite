param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\native_text_scroll'
New-Item -ItemType Directory -Force -Path "$runDir\rtl\core" | Out-Null
Copy-Item "$repoRoot\rtl\core\coco3gen.mem" "$runDir\rtl\core\coco3gen.mem" -Force
Push-Location $runDir
try {
 & "$VivadoBin\xvlog.bat" -d NEW_SRAM "$repoRoot\rtl\core\coco3_char_rom.v" "$repoRoot\rtl\coco3vid.v" "$repoRoot\tb\native_text_scroll_tb.v"
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" native_text_scroll_tb -s native_text_scroll_sim
 if($LASTEXITCODE){throw 'xelab failed'}
 & "$VivadoBin\xsim.bat" native_text_scroll_sim -runall
 if($LASTEXITCODE){throw 'xsim failed'}
 if(-not(Select-String -Path xsim.log -SimpleMatch 'PASS: native text scroll natural raster')){throw 'Scroll regression failed'}
} finally {Pop-Location}
