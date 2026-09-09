$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$work=Join-Path $repo 'build\sim\fdc_sd_buffer'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
  & 'C:\AMD\2025.2\Vivado\bin\xvlog.bat' (Join-Path $repo 'rtl\core\coco3_fdc.v') (Join-Path $repo 'tb\fdc_sd_buffer_tb.v'); if($LASTEXITCODE){throw 'xvlog failed'}
  & 'C:\AMD\2025.2\Vivado\bin\xelab.bat' fdc_sd_buffer_tb -s fdc_sd_buffer_tb_sim; if($LASTEXITCODE){throw 'xelab failed'}
  & 'C:\AMD\2025.2\Vivado\bin\xsim.bat' fdc_sd_buffer_tb_sim -runall; if($LASTEXITCODE){throw 'xsim failed'}
} finally { Pop-Location }
