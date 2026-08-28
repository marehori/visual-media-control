param(
    [string]$PluginPath = (Join-Path $PSScriptRoot '..\com.marehori.nowplaying.sdPlugin\plugin.ps1')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $PluginPath).Path,
    [ref]$tokens,
    [ref]$errors)
if ($errors.Count -gt 0) {
    throw ($errors | ForEach-Object Message | Out-String)
}

$functionDefinitions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true)
foreach ($definition in $functionDefinitions) {
    Invoke-Expression $definition.Extent.Text
}

function Convert-DataUrlToBitmap {
    param([string]$DataUrl)
    $bytes = [Convert]::FromBase64String(($DataUrl -split ',', 2)[1])
    $stream = [System.IO.MemoryStream]::new($bytes)
    try {
        $image = [System.Drawing.Image]::FromStream($stream)
        try { return [System.Drawing.Bitmap]::new($image) }
        finally { $image.Dispose() }
    }
    finally { $stream.Dispose() }
}

$artwork = [System.Drawing.Bitmap]::new(318, 318)
$graphics = [System.Drawing.Graphics]::FromImage($artwork)
$red = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Red)
$green = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Lime)
$blue = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Blue)
$yellow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Yellow)
try {
    $graphics.Clear([System.Drawing.Color]::Magenta)
    $graphics.FillRectangle($red, 0, 0, 144, 144)
    $graphics.FillRectangle($green, 174, 0, 144, 144)
    $graphics.FillRectangle($blue, 0, 174, 144, 144)
    $graphics.FillRectangle($yellow, 174, 174, 144, 144)
}
finally {
    $red.Dispose()
    $green.Dispose()
    $blue.Dispose()
    $yellow.Dispose()
    $graphics.Dispose()
}

$settings = Get-NormalizedSettings @{ buttonFunction = 'artwork'; gridGap = 30 }
$tests = @(
    @{ action = 'com.marehori.nowplaying.grid.topleft'; color = [System.Drawing.Color]::Red },
    @{ action = 'com.marehori.nowplaying.grid.topright'; color = [System.Drawing.Color]::Lime },
    @{ action = 'com.marehori.nowplaying.grid.bottomleft'; color = [System.Drawing.Color]::Blue },
    @{ action = 'com.marehori.nowplaying.grid.bottomright'; color = [System.Drawing.Color]::Yellow }
)

try {
    foreach ($test in $tests) {
        $dataUrl = New-ButtonImage `
            -Artwork $artwork `
            -IsPlaying $true `
            -Settings $settings `
            -Action $test.action `
            -Title 'Synthetic title' `
            -Artist 'Synthetic artist'
        $button = Convert-DataUrlToBitmap $dataUrl
        try {
            foreach ($point in @(@(8, 8), @(72, 72), @(135, 135))) {
                $actual = $button.GetPixel($point[0], $point[1]).ToArgb()
                if ($actual -ne $test.color.ToArgb()) {
                    throw "Quarter mismatch: action=$($test.action); x=$($point[0]); y=$($point[1])"
                }
            }
        }
        finally { $button.Dispose() }
    }

    foreach ($function in @('playPause', 'previous', 'next', 'title')) {
        $modeSettings = Get-NormalizedSettings @{ buttonFunction = $function }
        [void](New-ButtonImage `
            -Artwork $artwork `
            -IsPlaying $true `
            -Settings $modeSettings `
            -Action 'com.marehori.nowplaying.grid.topleft' `
            -Title 'Synthetic title' `
            -Artist 'Synthetic artist')
    }

    $customIcon = [System.Drawing.Bitmap]::new(96, 96)
    $iconGraphics = [System.Drawing.Graphics]::FromImage($customIcon)
    $iconBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(220, 255, 80, 20))
    $iconMemory = [System.IO.MemoryStream]::new()
    try {
        $iconGraphics.Clear([System.Drawing.Color]::Transparent)
        $iconGraphics.FillEllipse($iconBrush, 8, 8, 80, 80)
        $customIcon.Save($iconMemory, [System.Drawing.Imaging.ImageFormat]::Png)
        $customData = 'data:image/png;base64,' + [Convert]::ToBase64String($iconMemory.ToArray())
    }
    finally {
        $iconMemory.Dispose()
        $iconBrush.Dispose()
        $iconGraphics.Dispose()
        $customIcon.Dispose()
    }
    $customSettings = Get-NormalizedSettings @{
        buttonFunction = 'next'; customIconData = $customData; customIconName = 'test.png'
        iconSize = 70; iconTransparency = 20; shadowEnabled = $true
        shadowColor = '#001133'; shadowOpacity = 65; shadowBlur = 5; shadowSpread = 2
        backdropEnabled = $true; backdropColor = '#FFFFFF'; backdropTransparency = 50
    }
    $customRendered = New-ButtonImage `
        -Artwork $artwork -IsPlaying $true -Settings $customSettings `
        -Action 'com.marehori.nowplaying.grid.topright' `
        -Title 'Synthetic title' -Artist 'Synthetic artist'

    $textSettings = Get-NormalizedSettings @{
        buttonFunction = 'title'; textFontFamily = 'Georgia'; textSize = 34
        textAutoFit = $true; textFillMode = 'gradient'; textGradientStart = '#FFFFFF'
        textGradientEnd = '#FF55AA'; textGradientAngle = 90; textVerticalAlignment = 'bottom'
        textOutlineEnabled = $true; textOutlineColor = '#000000'; textOutlineOpacity = 90
        textOutlineWidth = 2
    }
    $textRendered = New-ButtonImage `
        -Artwork $artwork -IsPlaying $true -Settings $textSettings `
        -Action 'com.marehori.nowplaying.grid.bottomleft' `
        -Title 'A deliberately long synthetic title for auto-fit' -Artist 'Synthetic artist'

    $outputFolder = Join-Path $PSScriptRoot '..\test-output'
    if (-not (Test-Path -LiteralPath $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder | Out-Null
    }
    foreach ($render in @(
        @{ data = $customRendered; name = 'custom-render-direct.png' },
        @{ data = $textRendered; name = 'text-render-direct.png' }
    )) {
        $renderedBitmap = Convert-DataUrlToBitmap $render.data
        try { $renderedBitmap.Save((Join-Path $outputFolder $render.name), [System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $renderedBitmap.Dispose() }
    }
}
finally {
    $artwork.Dispose()
}

Write-Host 'PASS: grid composition, bezel area, standard/custom icons, and advanced text rendering.' -ForegroundColor Green
