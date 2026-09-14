param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$binary = Join-Path $OutputDirectory 'decb_bin_loader.bin'
$listing = Join-Path $OutputDirectory 'decb_bin_loader.lst'
$header = Join-Path $OutputDirectory 'decb_bin_loader_image.h'

& (Join-Path $repoRoot 'tools\asm6809\asm6809.exe') '-B' '-o' $binary `
    '-l' $listing (Join-Path $repoRoot 'firmware\management\decb_bin_loader.asm')
if ($LASTEXITCODE) { throw "DECB BIN loader assembly failed: $LASTEXITCODE" }

$bytes = [System.IO.File]::ReadAllBytes($binary)
$body = New-Object System.Text.StringBuilder
[void]$body.AppendLine('#ifndef COCO3ELITE_DECB_BIN_LOADER_IMAGE_H')
[void]$body.AppendLine('#define COCO3ELITE_DECB_BIN_LOADER_IMAGE_H')
[void]$body.AppendLine('#include <stdint.h>')
[void]$body.AppendLine('static const uint8_t decb_bin_loader_image[] = {')
for ($offset = 0; $offset -lt $bytes.Length; $offset += 12) {
    $last = [Math]::Min($offset + 12, $bytes.Length)
    $values = for ($index = $offset; $index -lt $last; ++$index) {
        '0x{0:x2}' -f $bytes[$index]
    }
    [void]$body.Append('    ')
    [void]$body.Append(($values -join ','))
    [void]$body.AppendLine(',')
}
[void]$body.AppendLine('};')
[void]$body.AppendLine(('#define DECB_BIN_LOADER_SIZE {0}u' -f $bytes.Length))
[void]$body.AppendLine('#endif')
[System.IO.File]::WriteAllText($header, $body.ToString(),
    [System.Text.UTF8Encoding]::new($false))
Write-Host "Built $binary and $header"
