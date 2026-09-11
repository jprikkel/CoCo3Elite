param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\sam_rate'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    $sources = @(
        'rtl\third-party\MC6809\mc6809i.v', 'rtl\core\cpu09.v',
        'rtl\core\coco3_128k_ram.v', 'rtl\core\coco3_system_rom.v',
        'rtl\core\coco3_disk_rom.v', 'rtl\core\coco3_diagnostic_cartridge.v',
        'rtl\core\coco3_disk_image.v', 'rtl\core\coco3_fdc.v',
        'rtl\core\coco3_keyboard_matrix.v', 'rtl\core\coco3_gime_timer.v',
        'rtl\core\coco3_gime_interrupt.v', 'rtl\core\coco3_boot_machine.v',
        'tb\sam_rate_tb.v'
    ) | ForEach-Object { Join-Path $repoRoot $_ }
    & (Join-Path $VivadoBin 'xvlog.bat') @sources
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $VivadoBin 'xelab.bat') sam_rate_tb -s sam_rate_tb_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    & (Join-Path $VivadoBin 'xsim.bat') sam_rate_tb_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
} finally { Pop-Location }
