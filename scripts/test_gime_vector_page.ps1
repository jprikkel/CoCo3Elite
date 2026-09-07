param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\gime_vector_page'
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
& (Join-Path $PSScriptRoot 'prepare_coco3_rom.ps1') -InputPath (Join-Path $repoRoot 'roms\coco3.rom') -OutputPath (Join-Path $runDir 'build\roms\coco3.mem')
& (Join-Path $PSScriptRoot 'prepare_disk_rom.ps1') -InputPath (Join-Path $repoRoot 'roms\disk11.rom') -OutputPath (Join-Path $runDir 'build\roms\disk11.mem')
& (Join-Path $PSScriptRoot 'prepare_diagnostic_cartridge.ps1') -InputPath (Join-Path $repoRoot 'roms\ziadiag.ccc') -OutputPath (Join-Path $runDir 'build\roms\diagnostic_cart.mem')
Push-Location $runDir
try {
 $sources=@('coco3_128k_ram.v','coco3_system_rom.v','coco3_disk_rom.v','coco3_diagnostic_cartridge.v','coco3_disk_image.v','sd_spi_init.v','sd_spi_read_sector0.v','coco3_fdc.v','coco3_keyboard_matrix.v','coco3_gime_timer.v','coco3_boot_machine.v') | ForEach-Object {Join-Path $repoRoot "rtl\core\$_"}
 & (Join-Path $VivadoBin 'xvlog.bat') (Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v') (Join-Path $repoRoot 'rtl\core\cpu09.v'); if($LASTEXITCODE){throw 'xvlog failed'}
 & (Join-Path $VivadoBin 'xvlog.bat') @sources (Join-Path $repoRoot 'tb\gime_vector_page_tb.v'); if($LASTEXITCODE){throw 'xvlog failed'}
 & (Join-Path $VivadoBin 'xelab.bat') gime_vector_page_tb -s gime_vector_page_tb_sim; if($LASTEXITCODE){throw 'xelab failed'}
 & (Join-Path $VivadoBin 'xsim.bat') gime_vector_page_tb_sim -runall; if($LASTEXITCODE){throw 'xsim failed'}
} finally {Pop-Location}
