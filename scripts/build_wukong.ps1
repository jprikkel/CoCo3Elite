param(
    [string]$Vivado = 'C:\AMD\2025.2\Vivado\bin\vivado.bat',
    [string]$Part = 'xc7a100tfgg676-2',
    [ValidateSet('TEST_PATTERN', 'HDMI_LIBRARY_TEST', 'HDMI_COCO_TEST', 'HDMI_COCO_AUDIO', 'COCO_VIDEO', 'CPU_DIAGNOSTIC', 'COCO3_BOOT')]
    [string]$Mode = 'TEST_PATTERN',
    [switch]$EmbeddedTestDisks
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $repoRoot 'build\wukong'
$buildTcl = Join-Path $PSScriptRoot 'build_wukong.tcl'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado was not found at: $Vivado"
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# Vivado resolves $readmemh paths from its process working directory. Mirror
# the small initialization inputs needed by the selectable build modes so the
# process can run entirely inside build/wukong instead of polluting repo root.
$stagedCoreDir = Join-Path $buildDir 'rtl\core'
$stagedRomDir = Join-Path $buildDir 'build\roms'
$stagedDiskDir = Join-Path $buildDir 'build\disks'
New-Item -ItemType Directory -Force -Path $stagedCoreDir, $stagedRomDir, $stagedDiskDir | Out-Null
foreach ($name in @('coco3gen.mem', 'coco3_diagnostic.mem')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "rtl\core\$name") `
        -Destination (Join-Path $stagedCoreDir $name) -Force
}
foreach ($name in @('coco3.mem', 'disk11.mem')) {
    $source = Join-Path $repoRoot "build\roms\$name"
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stagedRomDir $name) -Force
    }
}
if ($EmbeddedTestDisks) {
    foreach ($disk in @(
        @{ Input = 'disks\MUDPIES.DSK'; Output = 'mudpies.mem' }
    )) {
        $inputPath = Join-Path $repoRoot $disk.Input
        $preparedPath = Join-Path $repoRoot "build\disks\$($disk.Output)"
        & (Join-Path $PSScriptRoot 'prepare_disk_image.ps1') `
            -InputPath $inputPath -OutputPath $preparedPath
        Copy-Item -LiteralPath $preparedPath `
            -Destination (Join-Path $stagedDiskDir $disk.Output) -Force
    }
}
# This installation's per-user Tcl Store catalog is corrupt. Use the bundled
# store directly and disable the per-user cache for a reproducible batch run.
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$env:XILINX_TCLAPP_REPO = Join-Path $vivadoRoot 'data\XilinxTclStore'
$env:XILINX_LOCAL_USER_DATA = 'NO'

Push-Location $buildDir
try {
    & $Vivado -mode batch -nojournal -nolog `
        -source $buildTcl -tclargs $Part $Mode ([int]$EmbeddedTestDisks.IsPresent)
    $vivadoExitCode = $LASTEXITCODE
} finally {
    Pop-Location

    # AMD Vivado 2025.2 setupEnv.bat uses the Unix command "mkdir -p" on
    # Windows. Windows mkdir treats -p as a directory name, so every launcher
    # invocation creates an empty directory with that name in its working
    # directory. Remove only that known-empty launcher artifact.
    $dashPArtifact = Join-Path $buildDir '-p'
    if (Test-Path -LiteralPath $dashPArtifact -PathType Container) {
        if ((Get-ChildItem -LiteralPath $dashPArtifact -Force | Measure-Object).Count -eq 0) {
            Remove-Item -LiteralPath $dashPArtifact -Force
        } else {
            Write-Warning "Vivado launcher artifact is not empty; leaving it at $dashPArtifact"
        }
    }
}

if ($vivadoExitCode -ne 0) {
    throw "Vivado failed with exit code $vivadoExitCode"
}
