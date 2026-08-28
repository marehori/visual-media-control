$ErrorActionPreference = 'Stop'
$pluginName = 'com.marehori.nowplaying.sdPlugin'
$destination = Join-Path (Join-Path $env:APPDATA 'HotSpot\StreamDock\plugins') $pluginName

if (Get-Process -Name 'fifine Control Deck' -ErrorAction SilentlyContinue) {
    throw 'Close FIFINE Control Deck completely, including its notification-area icon, and try again.'
}
if (-not (Test-Path -LiteralPath $destination)) {
    Write-Host 'The plugin is not installed.'
    exit 0
}

Remove-Item -LiteralPath $destination -Recurse -Force
Write-Host "Only this plugin was removed: $destination" -ForegroundColor Green
