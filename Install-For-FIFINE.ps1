$ErrorActionPreference = 'Stop'
$pluginName = 'com.marehori.nowplaying.sdPlugin'
$source = Join-Path $PSScriptRoot $pluginName
$streamDockRoot = Join-Path $env:APPDATA 'HotSpot\StreamDock'
$pluginsRoot = Join-Path $streamDockRoot 'plugins'
$destination = Join-Path $pluginsRoot $pluginName

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Plugin folder was not found: $source"
}
if (-not (Test-Path -LiteralPath $streamDockRoot -PathType Container)) {
    throw "FIFINE Control Deck installation was not found: $streamDockRoot"
}
if (Get-Process -Name 'fifine Control Deck' -ErrorAction SilentlyContinue) {
    throw 'Close FIFINE Control Deck completely, including its notification-area icon, and try again.'
}

New-Item -ItemType Directory -Path $pluginsRoot -Force | Out-Null
if (Test-Path -LiteralPath $destination) {
    $backup = "$destination.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item -LiteralPath $destination -Destination $backup
    Write-Host "Previous version backed up to: $backup"
}
Copy-Item -LiteralPath $source -Destination $destination -Recurse

Write-Host ''
Write-Host 'Done. Start FIFINE Control Deck, find Visual Media Control, and drag Artwork Play / Pause onto a key.' -ForegroundColor Green
