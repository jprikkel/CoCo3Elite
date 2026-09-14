param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\decb_bin_loader'
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null

foreach ($rom in @('coco3.mem','disk11.mem')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "build\roms\$rom") `
        -Destination (Join-Path $runDir "build\roms\$rom") -Force
}
& (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $runDir
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $runDir 'decb_bin_loader.bin'))
$memory = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join [Environment]::NewLine
[System.IO.File]::WriteAllText((Join-Path $runDir 'decb_bin_loader.mem'),
    $memory + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $runDir 'decb_bin_loader_size.vh'),
    "``define DECB_BIN_LOADER_SIZE $($bytes.Length)`n", [System.Text.UTF8Encoding]::new($false))

function Invoke-VivadoTool {
    param([string]$Tool, [string[]]$Arguments)
    & (Join-Path $VivadoBin "$Tool.bat") @Arguments
    if ($LASTEXITCODE) { throw "$Tool failed with exit code $LASTEXITCODE" }
}

Push-Location $runDir
try {
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\third-party\MC6809\mc6809i.v'),
        (Join-Path $repoRoot 'rtl\core\cpu09.v'))
    Invoke-VivadoTool xvlog @(
        (Join-Path $repoRoot 'rtl\core\coco3_128k_ram.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_system_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_disk_rom.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_sd_cartridge.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_fdc.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_keyboard_matrix.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_gime_timer.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_gime_interrupt.v'),
        (Join-Path $repoRoot 'rtl\core\coco3_boot_machine.v'),
        (Join-Path $repoRoot 'tb\decb_bin_loader_tb.v'))
    Invoke-VivadoTool xelab @('decb_bin_loader_tb','-s','decb_bin_loader_tb_sim')
    $xsimOutput = & (Join-Path $VivadoBin 'xsim.bat') 'decb_bin_loader_tb_sim' '-runall' 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | ForEach-Object { Write-Host $_ }
    $xsimText = $xsimOutput -join "`n"
    if ($xsimExitCode -ne 0 -or $xsimText -match 'Fatal:' -or
        $xsimText -notmatch 'PASS: DECB BIN loader') {
        throw "xsim DECB BIN loader test failed with exit code $xsimExitCode"
    }
} finally {
    Pop-Location
}
