param([string]$VivadoBin = 'C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repoRoot 'build\sim\cpu_reset'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Push-Location $runDir
try {
    & "$VivadoBin\xvlog.bat" "$repoRoot\rtl\third-party\MC6809\mc6809i.v" "$repoRoot\rtl\core\cpu09.v" "$repoRoot\tb\cpu_reset_tb.v"
    if ($LASTEXITCODE -ne 0) { throw 'Reset test compilation failed' }
    & "$VivadoBin\xelab.bat" cpu_reset_tb -s cpu_reset_tb_sim
    if ($LASTEXITCODE -ne 0) { throw 'Reset test elaboration failed' }
    & "$VivadoBin\xsim.bat" cpu_reset_tb_sim -runall
    if ($LASTEXITCODE -ne 0) { throw 'Reset simulation failed' }
    if (-not (Select-String -Path xsim.log -SimpleMatch 'PASS: running CPU restarts')) { throw 'Reset regression did not pass' }
} finally { Pop-Location }
