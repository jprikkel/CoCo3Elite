param([string]$VivadoBin='C:\AMD\2025.2\Vivado\bin')
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build_video_probe.ps1') -Simulation
$runDir=Join-Path $repoRoot 'build\sim\video_probe'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$bytes=[IO.File]::ReadAllBytes((Join-Path $repoRoot 'build\tests\vidhelp_sim.bin'))
$lines=[Collections.Generic.List[string]]::new()
$p=0
while($p -lt $bytes.Length){
 $tag=$bytes[$p]; $len=256*[int]$bytes[$p+1]+$bytes[$p+2]
 $addr=256*[int]$bytes[$p+3]+$bytes[$p+4]; $p+=5
 if($tag -eq 255){break}
 if($tag -ne 0 -or $p+$len -gt $bytes.Length){throw 'Invalid DECB segment'}
 if($addr -lt 0x6000 -or $addr+$len -ge 0x6F00){throw 'Helper exceeds reserved code area'}
 $lines.Add(('@{0:X4}' -f $addr))
 for($j=0;$j -lt $len;$j++){$lines.Add(('{0:X2}' -f $bytes[$p+$j]))}
 $p+=$len
}
[IO.File]::WriteAllLines((Join-Path $runDir 'vidhelp.mem'),$lines)
Push-Location $runDir
try {
 & "$VivadoBin\xvlog.bat" "$repoRoot\rtl\third-party\MC6809\mc6809i.v" "$repoRoot\rtl\core\cpu09.v"
 if($LASTEXITCODE){throw 'xvhdl failed'}
 & "$VivadoBin\xvlog.bat" "$repoRoot\tb\video_probe_helper_tb.v"
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$VivadoBin\xelab.bat" video_probe_helper_tb -s video_probe_sim
 if($LASTEXITCODE){throw 'xelab failed'}
 & "$VivadoBin\xsim.bat" video_probe_sim -runall
 if($LASTEXITCODE){throw 'xsim failed'}
 if(-not (Select-String -Path xsim.log -SimpleMatch 'PASS: all video helper software cases')){throw 'Helper regression did not pass'}
} finally {Pop-Location}
