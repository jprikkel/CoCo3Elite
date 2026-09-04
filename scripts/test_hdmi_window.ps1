param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\hdmi_window'
New-Item -ItemType Directory -Force -Path "$runDir\rtl\core","$runDir\build\roms" | Out-Null
Copy-Item "$repoRoot\rtl\core\coco3gen.mem" "$runDir\rtl\core\coco3gen.mem" -Force
foreach($rom in @('coco3.mem','disk11.mem','diagnostic_cart.mem')){
 Copy-Item "$repoRoot\build\roms\$rom" "$runDir\build\roms\$rom" -Force
}
$sources=@('rtl/ps2_keyboard.v','rtl/cocokey.v','rtl/coco3vid.v',
 'rtl/core/coco3_keyboard_matrix.v','rtl/core/coco3_char_rom.v','rtl/core/coco3_128k_ram.v',
 'rtl/core/coco3_system_rom.v','rtl/core/coco3_disk_rom.v','rtl/core/coco3_diagnostic_cartridge.v',
 'rtl/core/coco3_disk_image.v','rtl/core/sd_spi_init.v','rtl/core/sd_spi_read_sector0.v',
 'rtl/core/coco3_fdc.v','rtl/core/coco3_gime_timer.v','rtl/core/coco3_boot_machine.v',
 'rtl/wukong/uart_tx.v','rtl/wukong/coco3_uart_debug.v','rtl/wukong/ntsc_artifact_filter.v',
 'rtl/wukong/crt_filter.v','rtl/wukong/coco3_boot_system.v','rtl/wukong/wukong_top.v',
 'tb/hdmi_window_tb.sv') | ForEach-Object {Join-Path $repoRoot $_}
$sources+=@(Get-ChildItem "$repoRoot\rtl\third_party\hdl-util-hdmi\src\*.sv" |
 Where-Object Name -ne 'serializer.sv' | ForEach-Object FullName)
Push-Location $runDir
try {
 & "$VivadoBin\xvhdl.bat" --2008 "$repoRoot\rtl\cpu09l_128.vhd"
 if($LASTEXITCODE){throw 'xvhdl failed'}
 & "$VivadoBin\xvlog.bat" -sv -d COCO3_BOOT -d NEW_SRAM -d HDMI_LIBRARY_TEST -d HDMI_LIBRARY_COCO -d HDMI_LIBRARY_AUDIO -d HDMI_RASTER_800X525 @sources
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" hdmi_window_tb -s hdmi_window_sim
 if($LASTEXITCODE){throw 'xelab failed'}
 & "$VivadoBin\xsim.bat" hdmi_window_sim -runall
 if($LASTEXITCODE){throw 'xsim failed'}
 if(-not(Select-String -Path xsim.log -SimpleMatch 'PASS: full HDMI content window')){throw 'HDMI window regression failed'}
} finally {Pop-Location}
