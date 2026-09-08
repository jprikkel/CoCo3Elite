param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\zenix_video'
New-Item -ItemType Directory -Force -Path "$runDir\rtl\core" | Out-Null
Copy-Item "$repoRoot\rtl\core\coco3gen.mem" "$runDir\rtl\core\coco3gen.mem" -Force
Push-Location $runDir
try {
 & "$VivadoBin\xvlog.bat" -d NEW_SRAM -d HDMI_RASTER_800X525 "$repoRoot\rtl\core\coco3_128k_ram.v" "$repoRoot\rtl\core\coco3_char_rom.v" "$repoRoot\rtl\third-party\coco3fpga\coco3vid.v" "$repoRoot\tb\zenix_video_tb.v"
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" zenix_video_tb -s zenix_graphics_check
 if($LASTEXITCODE){throw 'xelab failed'}
 & "$VivadoBin\xsim.bat" zenix_graphics_check -runall
 if($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch 'PASS: Zenix')){throw 'Zenix video regression failed'}
} finally {Pop-Location}
