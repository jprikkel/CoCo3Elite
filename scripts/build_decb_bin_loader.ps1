param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
function Build-LoaderImage {
    param(
        [string]$SourceName,
        [string]$BaseName,
        [string]$ArrayName,
        [string]$SizeName,
        [string]$GuardName
    )
    $binary = Join-Path $OutputDirectory "$BaseName.bin"
    $listing = Join-Path $OutputDirectory "$BaseName.lst"
    $header = Join-Path $OutputDirectory "$BaseName`_image.h"
    & (Join-Path $repoRoot 'tools\asm6809\asm6809.exe') '-B' '-o' $binary `
        '-l' $listing (Join-Path $repoRoot "firmware\management\$SourceName")
    if ($LASTEXITCODE) { throw "$BaseName assembly failed: $LASTEXITCODE" }

    $bytes = [System.IO.File]::ReadAllBytes($binary)
    $body = New-Object System.Text.StringBuilder
    [void]$body.AppendLine("#ifndef $GuardName")
    [void]$body.AppendLine("#define $GuardName")
    [void]$body.AppendLine('#include <stdint.h>')
    [void]$body.AppendLine("static const uint8_t $ArrayName`[] = {")
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
    [void]$body.AppendLine("#define $SizeName $($bytes.Length)u")
    [void]$body.AppendLine('#endif')
    [System.IO.File]::WriteAllText($header, $body.ToString(),
        [System.Text.UTF8Encoding]::new($false))
    Write-Host "Built $binary and $header"
}

Build-LoaderImage -SourceName 'decb_bin_loader.asm' -BaseName 'decb_bin_loader' `
    -ArrayName 'decb_bin_loader_image' -SizeName 'DECB_BIN_LOADER_SIZE' `
    -GuardName 'COCO3ELITE_DECB_BIN_LOADER_IMAGE_H'
Build-LoaderImage -SourceName 'coco3_banked_bin_loader.asm' -BaseName 'coco3_banked_bin_loader' `
    -ArrayName 'coco3_banked_bin_loader_image' -SizeName 'COCO3_BANKED_BIN_LOADER_SIZE' `
    -GuardName 'COCO3ELITE_COCO3_BANKED_BIN_LOADER_IMAGE_H'
