param([string]$Version = '1.0.0')

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$pluginName = 'com.marehori.nowplaying.sdPlugin'
$pluginRoot = Join-Path $repoRoot $pluginName
$sourceRoot = Join-Path $repoRoot 'source'
$distRoot = Join-Path $repoRoot 'dist'
$archivePath = Join-Path $distRoot "Visual-Media-Control-v$Version.zip"
$manualArchivePath = Join-Path $distRoot "Visual-Media-Control-v$Version-manual.zip"
$checksumsPath = Join-Path $distRoot 'SHA256SUMS.txt'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("visual-media-control-" + [Guid]::NewGuid().ToString('N'))

$manifest = Get-Content (Join-Path $pluginRoot 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.Version -ne $Version) {
    throw "Manifest version is $($manifest.Version), requested release is $Version."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sourceRoot 'GenerateIcons.ps1') `
    -OutputDirectory (Join-Path $pluginRoot 'Images')
if ($LASTEXITCODE -ne 0) { throw 'Icon generation failed.' }

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'C# compiler was not found.' }

& $compiler /nologo /target:winexe /optimize+ `
    "/out:$(Join-Path $pluginRoot 'VisualMediaControl.exe')" `
    (Join-Path $sourceRoot 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    Copy-Item -LiteralPath $pluginRoot -Destination $temporaryRoot -Recurse
    foreach ($item in @(
        'Install-For-FIFINE.ps1', 'Uninstall-From-FIFINE.ps1',
        'Test-Windows-Media.ps1', 'README.txt', 'README.md', 'LICENSE'
    )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $item) -Destination $temporaryRoot
    }
    Copy-Item -LiteralPath $sourceRoot -Destination $temporaryRoot -Recurse

    $stagedLogFolder = Join-Path (Join-Path $temporaryRoot $pluginName) 'logs'
    if (Test-Path -LiteralPath $stagedLogFolder) {
        Remove-Item -LiteralPath $stagedLogFolder -Recurse -Force
    }
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    if (Test-Path -LiteralPath $manualArchivePath) {
        Remove-Item -LiteralPath $manualArchivePath -Force
    }
    Compress-Archive -Path (Join-Path $temporaryRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
    Compress-Archive -Path (Join-Path $temporaryRoot $pluginName) -DestinationPath $manualArchivePath -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$hashes = Get-FileHash -LiteralPath $archivePath, $manualArchivePath -Algorithm SHA256
$checksumLines = $hashes | ForEach-Object {
    '{0} *{1}' -f $_.Hash, [System.IO.Path]::GetFileName($_.Path)
}
Set-Content -LiteralPath $checksumsPath -Value $checksumLines -Encoding ASCII
foreach ($hash in $hashes) {
    Write-Host "Created: $($hash.Path)" -ForegroundColor Green
    Write-Host "SHA-256: $($hash.Hash)"
}
Write-Host "Checksums: $checksumsPath"
