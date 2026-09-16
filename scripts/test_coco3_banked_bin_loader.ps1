param(
    [string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin',
    [string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = if ($RunDirectory) { $RunDirectory } else { Join-Path $repoRoot 'build\sim\coco3_banked_bin_loader' }
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'build\roms') | Out-Null
foreach ($rom in @('coco3.mem','disk11.mem')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "build\roms\$rom") `
        -Destination (Join-Path $runDir "build\roms\$rom") -Force
}
& (Join-Path $PSScriptRoot 'build_decb_bin_loader.ps1') -OutputDirectory $runDir
$bytes = [IO.File]::ReadAllBytes((Join-Path $runDir 'coco3_banked_bin_loader.bin'))
$memory = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $runDir 'coco3_banked_bin_loader.mem'),
    $memory + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $runDir 'coco3_banked_bin_loader_size.vh'),
    "``define COCO3_BANKED_BIN_LOADER_SIZE $($bytes.Length)`n", [Text.UTF8Encoding]::new($false))

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
        (Join-Path $repoRoot 'tb\coco3_banked_bin_loader_tb.v'))
    Invoke-VivadoTool xelab @('coco3_banked_bin_loader_tb','-s','coco3_banked_bin_loader_tb_sim')
    $output = & (Join-Path $VivadoBin 'xsim.bat') 'coco3_banked_bin_loader_tb_sim' '-runall' 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $text = $output -join "`n"
    if ($exitCode -ne 0 -or $text -match 'Fatal:' -or
        $text -notmatch 'PASS: generic banked loader') {
        throw "xsim banked BIN loader test failed with exit code $exitCode"
    }
} finally {
    Pop-Location
}
