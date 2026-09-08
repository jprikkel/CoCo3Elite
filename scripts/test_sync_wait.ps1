param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\sync_wait'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
& "$repoRoot\tools\asm6809\asm6809.exe" -B -o "$runDir\sync_wait.bin" "$repoRoot\tb\asm\SYNCWAIT.asm"
if($LASTEXITCODE){throw 'assembly failed'}
$hex=[System.IO.File]::ReadAllBytes("$runDir\sync_wait.bin") | ForEach-Object {$_.ToString('x2')}
[System.IO.File]::WriteAllLines("$runDir\sync_wait.mem",[string[]]$hex)
foreach($item in @(@{Name='hven_harness';Source='HVENHARNESS'},@{Name='hven_helper';Source='HVENFILL'})) {
 & "$repoRoot\tools\asm6809\asm6809.exe" -B -d ORIGIN=24576 -o "$runDir\$($item.Name).bin" "$repoRoot\tb\asm\$($item.Source).asm"
 if($LASTEXITCODE){throw 'HVEN assembly failed'}
 $hex=[System.IO.File]::ReadAllBytes("$runDir\$($item.Name).bin") | ForEach-Object {$_.ToString('x2')}
 [System.IO.File]::WriteAllLines("$runDir\$($item.Name).mem",[string[]]$hex)
}
Push-Location $runDir
try {
 $sources=@('rtl\third-party\MC6809\mc6809i.v','rtl\core\cpu09.v',
 'rtl\core\coco3_128k_ram.v','rtl\core\coco3_system_rom.v','rtl\core\coco3_disk_rom.v',
 'rtl\core\coco3_diagnostic_cartridge.v','rtl\core\coco3_disk_image.v','rtl\core\coco3_fdc.v',
 'rtl\core\coco3_keyboard_matrix.v','rtl\core\coco3_gime_timer.v','rtl\core\coco3_gime_interrupt.v',
 'rtl\core\coco3_boot_machine.v','tb\sync_wait_tb.v','tb\hven_fill_tb.v') | ForEach-Object {Join-Path $repoRoot $_}
 & "$VivadoBin\xvlog.bat" @sources
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" sync_wait_tb -s sync_wait_sim
 if($LASTEXITCODE){throw 'xelab failed'}
 foreach($mode in @('NORMAL','FAST')) {
  & "$VivadoBin\xsim.bat" sync_wait_sim -testplusarg $mode -runall
  if($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch 'PASS: CPU polls latched VSYNC')) {throw "Sync regression failed: $mode"}
 }
 & "$VivadoBin\xelab.bat" hven_fill_tb -s hven_fill_sim
 if($LASTEXITCODE){throw 'HVEN elaboration failed'}
 & "$VivadoBin\xsim.bat" hven_fill_sim -runall
 if($LASTEXITCODE -or -not (Select-String -Path xsim.log -SimpleMatch 'PASS: HVEN helper')) {throw 'HVEN helper regression failed'}
} finally {Pop-Location}
