param(
    [string]$InputPath = 'disks/INTRUDERS.DSK',
    [string]$OutputPath = 'build/disks/intruders.mem'
)

$ErrorActionPreference = 'Stop'
$supportedSizes = @{
    (35 * 18 * 256) = 35
    (80 * 18 * 256) = 80
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Disk image was not found at '$InputPath'."
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$image = [System.IO.File]::ReadAllBytes($resolvedInput)
if (-not $supportedSizes.ContainsKey($image.Length)) {
    $sizes = ($supportedSizes.Keys | Sort-Object) -join ' or '
    throw "The disk image must be a raw 35- or 80-track, 18-sector, 256-byte image ($sizes bytes); '$resolvedInput' is $($image.Length) bytes."
}
$trackCount = $supportedSizes[$image.Length]

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$hexLines = [string[]]::new($image.Length)
for ($index = 0; $index -lt $image.Length; $index++) {
    $hexLines[$index] = $image[$index].ToString('X2')
}
[System.IO.File]::WriteAllLines($OutputPath, $hexLines, [System.Text.Encoding]::ASCII)

$digest = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash
Write-Host 'Prepared read-only CoCo disk image:'
Write-Host "  Input:        $resolvedInput"
Write-Host "  Geometry:     $trackCount tracks, 18 sectors/track, 256 bytes/sector"
Write-Host "  SHA-256:      $digest"
Write-Host "  Vivado image: $OutputPath"
