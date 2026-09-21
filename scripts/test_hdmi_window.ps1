param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$runDir=Join-Path $repoRoot 'build\sim\hdmi_window'
New-Item -ItemType Directory -Force -Path "$runDir\rtl\core","$runDir\rtl\management","$runDir\build\roms" | Out-Null
Copy-Item "$repoRoot\rtl\core\coco3gen.mem" "$runDir\rtl\core\coco3gen.mem" -Force
Copy-Item "$repoRoot\rtl\management\manager_fonts.mem" "$runDir\rtl\management\manager_fonts.mem" -Force
foreach($rom in @('coco3.mem','disk11.mem')){
 Copy-Item "$repoRoot\build\roms\$rom" "$runDir\build\roms\$rom" -Force
}
$firmwareDir=Join-Path $runDir 'firmware'
$toolchain='C:\AMD\2025.2\gnu\riscv\nt\bin'
New-Item -ItemType Directory -Force -Path $firmwareDir | Out-Null
$firmwareElf=Join-Path $firmwareDir 'rv32_sd_mount.elf'
$firmwareBin=Join-Path $firmwareDir 'rv32_sd_mount.bin'
& (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $firmwareDir
& (Join-Path $toolchain 'riscv64-unknown-elf-gcc.exe') '-march=rv32im_zicsr' '-mabi=ilp32' '-Os' '-ffreestanding' '-fno-builtin' '-nostdlib' `
 '-Wl,--build-id=none' '-Wl,--gc-sections' '-T' (Join-Path $repoRoot 'firmware\management\rv32_tcm.ld') `
 '-I' $firmwareDir (Join-Path $repoRoot 'firmware\management\rv32_start.S') `
 (Join-Path $repoRoot 'firmware\management\decb_bin_format.c') `
 (Join-Path $repoRoot 'firmware\management\coco3_banked_bin_format.c') `
 (Join-Path $repoRoot 'firmware\management\settings_ui.c') `
 (Join-Path $repoRoot 'firmware\management\rv32_sd_mount.c') '-o' $firmwareElf
if($LASTEXITCODE){throw "RV32 firmware link failed: $LASTEXITCODE"}
& (Join-Path $toolchain 'riscv64-unknown-elf-objcopy.exe') '-O' 'binary' $firmwareElf $firmwareBin
if($LASTEXITCODE){throw "RV32 firmware conversion failed: $LASTEXITCODE"}
& (Join-Path $PSScriptRoot 'generate_rv32_program_header.ps1') -Binary $firmwareBin -Output (Join-Path $runDir 'rv32_sd_mount_program.vh')
$managerCpuSources=@(
 Get-ChildItem -LiteralPath "$repoRoot\rtl\third-party\ultraembedded-riscv\core\riscv" -Filter '*.v'
 Get-ChildItem -LiteralPath "$repoRoot\rtl\third-party\ultraembedded-riscv\top_tcm_axi\src_v" -Filter '*.v'
) | Sort-Object FullName | ForEach-Object FullName
$verilogSources=@($managerCpuSources)+(@('rtl/third-party/PS2_Key/ps2_keyboard.v','rtl/third-party/coco3fpga/cocokey.v','rtl/third-party/coco3fpga/coco3vid.v',
 'rtl/core/coco3_keyboard_matrix.v','rtl/core/coco3_char_rom.v','rtl/core/coco3_128k_ram.v',
 'rtl/core/coco3_system_rom.v','rtl/core/coco3_disk_rom.v','rtl/core/coco3_sd_cartridge.v',
 'rtl/core/coco3_disk_image.v',
 'rtl/management/manager_sd_mmio.v','rtl/management/ultraembedded_manager_sd_mount.v','rtl/management/manager_font_rom.v','rtl/management/manager_osd.v',
 'rtl/core/coco3_fdc.v','rtl/core/coco3_gime_timer.v','rtl/core/coco3_gime_interrupt.v','rtl/core/coco3_boot_machine.v',
 'rtl/wukong/uart_tx.v','rtl/wukong/uart_rx.v','rtl/wukong/coco3_uart_debug.v','rtl/wukong/ntsc_artifact_filter.v',
 'rtl/wukong/crt_filter.v','rtl/wukong/video_frame_capture.v',
 'rtl/wukong/coco3_boot_system.v') | ForEach-Object {Join-Path $repoRoot $_})
$systemVerilogSources=@((Join-Path $repoRoot 'rtl/wukong/wukong_top.v'),
 (Join-Path $repoRoot 'tb/hdmi_window_tb.sv'))
$systemVerilogSources+=@(Get-ChildItem "$repoRoot\rtl\third-party\hdl-util-hdmi\src\*.sv" |
 Where-Object Name -ne 'serializer.sv' | ForEach-Object FullName)
Push-Location $runDir
try {
 & "$VivadoBin\xvlog.bat" "$repoRoot\rtl\third-party\MC6809\mc6809i.v" "$repoRoot\rtl\core\cpu09.v"
 if($LASTEXITCODE){throw 'xvhdl failed'}
 $defines=@('-d','NEW_SRAM','-d','HDMI_TEST_PATTERN','-d','HDMI_LIBRARY_COCO','-d','HDMI_LIBRARY_AUDIO','-d','HDMI_RASTER_800X525',
  '-i',"$repoRoot\rtl\third-party\ultraembedded-riscv\core\riscv",'-i',$runDir)
 & "$VivadoBin\xvlog.bat" @defines @verilogSources
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xvlog.bat" -sv @defines @systemVerilogSources
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" -L xpm hdmi_window_tb -s hdmi_window_sim --timescale 1ns/1ps
 if($LASTEXITCODE){throw 'xelab failed'}
 & "$VivadoBin\xsim.bat" hdmi_window_sim -runall
 if($LASTEXITCODE){throw 'xsim failed'}
 if(-not(Select-String -Path xsim.log -SimpleMatch 'PASS: full HDMI content window')){throw 'HDMI window regression failed'}

 # Convert the simulator's binary PPM captures to PNG without requiring an
 # external image utility. System.Drawing is available with Windows Vivado.
 Add-Type -AssemblyName System.Drawing
 foreach($name in @('width32','width40','width80')) {
  $ppm=Join-Path $runDir "$name.ppm"
  $png=Join-Path $runDir "$name.png"
  $bytes=[System.IO.File]::ReadAllBytes($ppm)
  $header=[System.Text.Encoding]::ASCII.GetBytes("P6`n640 480`n255`n")
  $expected=$header.Length+(640*480*3)
  if($bytes.Length -ne $expected){throw "$name capture has $($bytes.Length) bytes; expected $expected"}
  $bitmap=[System.Drawing.Bitmap]::new(640,480,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $rect=[System.Drawing.Rectangle]::new(0,0,640,480)
  $data=$bitmap.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::WriteOnly,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  try {
   $bgr=[byte[]]::new($data.Stride*480)
   $source=$header.Length
   for($y=0;$y -lt 480;$y++) {
    $row=$y*$data.Stride
    for($x=0;$x -lt 640;$x++) {
     $pixel=$row+$x*3
     $bgr[$pixel]=$bytes[$source+2]
     $bgr[$pixel+1]=$bytes[$source+1]
     $bgr[$pixel+2]=$bytes[$source]
     $source+=3
    }
   }
   [Runtime.InteropServices.Marshal]::Copy($bgr,0,$data.Scan0,$bgr.Length)
  } finally {$bitmap.UnlockBits($data)}
  try {$bitmap.Save($png,[System.Drawing.Imaging.ImageFormat]::Png)} finally {$bitmap.Dispose()}
  Write-Host "Wrote simulated screen capture: $png"
 }
} finally {Pop-Location}
