param(
    [string]$port,
    [string]$pluginUUID,
    [string]$registerEvent,
    [string]$info
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$script:LogPath = Join-Path $PSScriptRoot 'logs\plugin.log'
$script:Contexts = @{}
$script:ContextActions = @{}
$script:ContextSettings = @{}
$script:LastImages = @{}
$script:GridGap = 30
$script:GridGapInitialized = $false
$script:WebSocket = $null
$script:SessionManager = $null
$script:CurrentSession = $null
$script:LastFingerprint = ''
$script:LastRefresh = [DateTime]::MinValue
$script:LastManagerAttempt = [DateTime]::MinValue

function Write-PluginLog {
    param([string]$Message)
    try {
        $folder = Split-Path -Parent $script:LogPath
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $line = '{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f [DateTime]::Now, $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
        if ((Get-Item -LiteralPath $script:LogPath).Length -gt 1048576) {
            $tail = Get-Content -LiteralPath $script:LogPath -Tail 1000
            Set-Content -LiteralPath $script:LogPath -Value $tail -Encoding UTF8
        }
    }
    catch { }
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name, $DefaultValue)
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $DefaultValue
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Limit-Integer {
    param($Value, [int]$Minimum, [int]$Maximum, [int]$DefaultValue)
    try { $number = [int]$Value } catch { return $DefaultValue }
    return [Math]::Max($Minimum, [Math]::Min($Maximum, $number))
}

function Normalize-HexColor {
    param($Value, [string]$DefaultValue)
    $text = [string]$Value
    if ($text -match '^#[0-9a-fA-F]{6}$') { return $text.ToUpperInvariant() }
    return $DefaultValue
}

function Get-BooleanSetting {
    param($Value, [bool]$DefaultValue)
    if ($Value -is [bool]) { return $Value }
    if ($null -eq $Value) { return $DefaultValue }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'on')) { return $true }
    if ($text -in @('false', '0', 'no', 'off')) { return $false }
    return $DefaultValue
}

function Get-DefaultButtonFunctionForAction {
    param([string]$Action)
    switch ($Action) {
        'com.marehori.nowplaying.grid.topleft' { return 'previous' }
        'com.marehori.nowplaying.grid.topright' { return 'next' }
        'com.marehori.nowplaying.grid.bottomleft' { return 'title' }
        'com.marehori.nowplaying.grid.bottomright' { return 'playPause' }
        'com.marehori.nowplaying.playpause' { return 'playPause' }
        default { return 'artwork' }
    }
}

function Get-NormalizedSettings {
    param($Settings, [string]$Action = '')
    $fillMode = [string](Get-ObjectPropertyValue $Settings 'fillMode' 'solid')
    if ($fillMode -ne 'gradient') { $fillMode = 'solid' }
    $defaultButtonFunction = Get-DefaultButtonFunctionForAction $Action
    $buttonFunction = [string](Get-ObjectPropertyValue $Settings 'buttonFunction' $defaultButtonFunction)
    if ($buttonFunction -notin @('artwork', 'playPause', 'previous', 'next', 'title')) {
        $buttonFunction = 'artwork'
    }
    $textContent = [string](Get-ObjectPropertyValue $Settings 'textContent' 'titleArtist')
    if ($textContent -notin @('titleArtist', 'title', 'artist')) { $textContent = 'titleArtist' }
    $textAlignment = [string](Get-ObjectPropertyValue $Settings 'textAlignment' 'center')
    if ($textAlignment -notin @('left', 'center', 'right')) { $textAlignment = 'center' }
    $textVerticalAlignment = [string](Get-ObjectPropertyValue $Settings 'textVerticalAlignment' 'center')
    if ($textVerticalAlignment -notin @('top', 'center', 'bottom')) { $textVerticalAlignment = 'center' }
    $textFillMode = [string](Get-ObjectPropertyValue $Settings 'textFillMode' 'solid')
    if ($textFillMode -ne 'gradient') { $textFillMode = 'solid' }
    $allowedFonts = @(
        'Segoe UI', 'Arial', 'Calibri', 'Consolas', 'Georgia', 'Impact',
        'Trebuchet MS', 'Verdana', 'Times New Roman'
    )
    $textFontFamily = [string](Get-ObjectPropertyValue $Settings 'textFontFamily' 'Segoe UI')
    if ($textFontFamily -notin $allowedFonts) { $textFontFamily = 'Segoe UI' }
    $customIconData = [string](Get-ObjectPropertyValue $Settings 'customIconData' '')
    if ($customIconData.Length -gt 1500000 -or $customIconData -notmatch '^data:image/png;base64,') {
        $customIconData = ''
    }
    $customIconName = [string](Get-ObjectPropertyValue $Settings 'customIconName' '')
    if ($customIconName.Length -gt 120) { $customIconName = $customIconName.Substring(0, 120) }
    return @{
        buttonFunction = $buttonFunction
        gridGap = Limit-Integer (Get-ObjectPropertyValue $Settings 'gridGap' 30) 0 60 30
        iconSize = Limit-Integer (Get-ObjectPropertyValue $Settings 'iconSize' 56) 24 82 56
        fillMode = $fillMode
        solidColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'solidColor' '#FFFFFF') '#FFFFFF'
        gradientStart = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'gradientStart' '#FFFFFF') '#FFFFFF'
        gradientEnd = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'gradientEnd' '#7C5CFF') '#7C5CFF'
        gradientAngle = Limit-Integer (Get-ObjectPropertyValue $Settings 'gradientAngle' 45) 0 360 45
        iconTransparency = Limit-Integer (Get-ObjectPropertyValue $Settings 'iconTransparency' 5) 0 95 5
        customIconData = $customIconData
        customIconName = $customIconName
        shadowEnabled = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'shadowEnabled' $true) $true
        shadowColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'shadowColor' '#000000') '#000000'
        shadowOpacity = Limit-Integer (Get-ObjectPropertyValue $Settings 'shadowOpacity' 32) 0 100 32
        shadowBlur = Limit-Integer (Get-ObjectPropertyValue $Settings 'shadowBlur' 4) 0 12 4
        shadowSpread = Limit-Integer (Get-ObjectPropertyValue $Settings 'shadowSpread' 1) 0 12 1
        shadowOffsetX = Limit-Integer (Get-ObjectPropertyValue $Settings 'shadowOffsetX' 2) -20 20 2
        shadowOffsetY = Limit-Integer (Get-ObjectPropertyValue $Settings 'shadowOffsetY' 3) -20 20 3
        backdropEnabled = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'backdropEnabled' $false) $false
        backdropColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'backdropColor' '#000000') '#000000'
        backdropTransparency = Limit-Integer (Get-ObjectPropertyValue $Settings 'backdropTransparency' 25) 0 100 25
        backdropSize = Limit-Integer (Get-ObjectPropertyValue $Settings 'backdropSize' 76) 45 100 76
        backdropBlur = Limit-Integer (Get-ObjectPropertyValue $Settings 'backdropBlur' 0) 0 20 0
        textContent = $textContent
        textFontFamily = $textFontFamily
        textSize = Limit-Integer (Get-ObjectPropertyValue $Settings 'textSize' 18) 10 36 18
        textAutoFit = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'textAutoFit' $true) $true
        textFillMode = $textFillMode
        textColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'textColor' '#FFFFFF') '#FFFFFF'
        textGradientStart = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'textGradientStart' '#FFFFFF') '#FFFFFF'
        textGradientEnd = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'textGradientEnd' '#7C5CFF') '#7C5CFF'
        textGradientAngle = Limit-Integer (Get-ObjectPropertyValue $Settings 'textGradientAngle' 45) 0 360 45
        textTransparency = Limit-Integer (Get-ObjectPropertyValue $Settings 'textTransparency' 0) 0 95 0
        textAlignment = $textAlignment
        textVerticalAlignment = $textVerticalAlignment
        textBold = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'textBold' $true) $true
        textOutlineEnabled = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'textOutlineEnabled' $true) $true
        textOutlineColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'textOutlineColor' '#000000') '#000000'
        textOutlineOpacity = Limit-Integer (Get-ObjectPropertyValue $Settings 'textOutlineOpacity' 80) 0 100 80
        textOutlineWidth = Limit-Integer (Get-ObjectPropertyValue $Settings 'textOutlineWidth' 1) 1 5 1
        textShadowEnabled = Get-BooleanSetting (Get-ObjectPropertyValue $Settings 'textShadowEnabled' $true) $true
        textShadowColor = Normalize-HexColor (Get-ObjectPropertyValue $Settings 'textShadowColor' '#000000') '#000000'
        textShadowOpacity = Limit-Integer (Get-ObjectPropertyValue $Settings 'textShadowOpacity' 72) 0 100 72
        textShadowBlur = Limit-Integer (Get-ObjectPropertyValue $Settings 'textShadowBlur' 2) 0 8 2
        textShadowOffsetX = Limit-Integer (Get-ObjectPropertyValue $Settings 'textShadowOffsetX' 1) -12 12 1
        textShadowOffsetY = Limit-Integer (Get-ObjectPropertyValue $Settings 'textShadowOffsetY' 2) -12 12 2
    }
}

function Get-ActionDescriptor {
    param([string]$Action)
    switch ($Action) {
        'com.marehori.nowplaying.grid.topleft' {
            return @{ isGrid = $true; column = 0; row = 0 }
        }
        'com.marehori.nowplaying.grid.topright' {
            return @{ isGrid = $true; column = 1; row = 0 }
        }
        'com.marehori.nowplaying.grid.bottomleft' {
            return @{ isGrid = $true; column = 0; row = 1 }
        }
        'com.marehori.nowplaying.grid.bottomright' {
            return @{ isGrid = $true; column = 1; row = 1 }
        }
        default {
            return @{ isGrid = $false; column = 0; row = 0 }
        }
    }
}

function Get-SettingsForContext {
    param([string]$Context)
    if (-not $script:ContextSettings.ContainsKey($Context)) {
        $action = if ($script:ContextActions.ContainsKey($Context)) {
            [string]$script:ContextActions[$Context]
        }
        else { '' }
        $script:ContextSettings[$Context] = Get-NormalizedSettings $null $action
    }
    return $script:ContextSettings[$Context]
}

function Convert-HexToColor {
    param([string]$Hex, [int]$Alpha)
    $value = $Hex.TrimStart('#')
    $red = [Convert]::ToInt32($value.Substring(0, 2), 16)
    $green = [Convert]::ToInt32($value.Substring(2, 2), 16)
    $blue = [Convert]::ToInt32($value.Substring(4, 2), 16)
    return [System.Drawing.Color]::FromArgb($Alpha, $red, $green, $blue)
}

$script:AsTaskOperation = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.IsGenericMethodDefinition -and
        $_.GetGenericArguments().Count -eq 1 -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } |
    Select-Object -First 1

$script:RandomAccessStreamType = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$script:GetInputStreamAtMethod = $script:RandomAccessStreamType.GetMethod('GetInputStreamAt')
$script:AsStreamForReadMethod = [System.IO.WindowsRuntimeStreamExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsStreamForRead' -and
        $_.GetParameters().Count -eq 2
    } |
    Select-Object -First 1

function Wait-WinRtOperation {
    param(
        [Parameter(Mandatory = $true)]$Operation,
        [Parameter(Mandatory = $true)][Type]$ResultType
    )
    $method = $script:AsTaskOperation.MakeGenericMethod($ResultType)
    $task = $method.Invoke($null, [object[]]@($Operation))
    return $task.GetAwaiter().GetResult()
}

function Send-WebSocketObject {
    param([hashtable]$Value)
    if ($null -eq $script:WebSocket -or
        $script:WebSocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        return
    }

    $json = ConvertTo-Json -InputObject $Value -Compress -Depth 12
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $bytes)
    $task = $script:WebSocket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None)
    $task.GetAwaiter().GetResult()
}

function Send-SettingsToContext {
    param([string]$Context, [hashtable]$Settings)
    if ([string]::IsNullOrEmpty($Context)) { return }
    Send-WebSocketObject @{
        event = 'setSettings'
        context = $Context
        payload = $Settings
    }
}

function Sync-GridGap {
    param([int]$Gap, [bool]$Persist = $true)
    $script:GridGap = Limit-Integer $Gap 0 60 30
    $script:GridGapInitialized = $true
    foreach ($gridContext in @($script:Contexts.Keys)) {
        $gridAction = if ($script:ContextActions.ContainsKey($gridContext)) {
            [string]$script:ContextActions[$gridContext]
        }
        else { '' }
        if (-not (Get-ActionDescriptor $gridAction).isGrid) { continue }
        $gridSettings = Get-SettingsForContext $gridContext
        if ([int]$gridSettings.gridGap -ne $script:GridGap) {
            $gridSettings.gridGap = $script:GridGap
            $script:ContextSettings[$gridContext] = $gridSettings
            if ($Persist) {
                Send-SettingsToContext -Context $gridContext -Settings $gridSettings
            }
        }
    }
}

function Initialize-GridGapForContext {
    param([string]$Context)
    if (-not $script:ContextActions.ContainsKey($Context)) { return }
    $action = [string]$script:ContextActions[$Context]
    if (-not (Get-ActionDescriptor $action).isGrid) { return }
    $settings = Get-SettingsForContext $Context
    if (-not $script:GridGapInitialized) {
        Sync-GridGap -Gap ([int]$settings.gridGap) -Persist $false
        return
    }
    if ([int]$settings.gridGap -ne $script:GridGap) {
        $settings.gridGap = $script:GridGap
        $script:ContextSettings[$Context] = $settings
        Send-SettingsToContext -Context $Context -Settings $settings
    }
}

function Send-ImageToContext {
    param([string]$Context, [string]$DataUrl)
    if ([string]::IsNullOrEmpty($Context)) { return }
    Write-PluginLog ("Sending image: context=$Context; characters=$($DataUrl.Length)")
    Send-WebSocketObject @{
        event = 'setImage'
        context = $Context
        payload = @{
            image = $DataUrl
            target = 0
        }
    }
}

function Send-Alert {
    param([string]$Context)
    if ([string]::IsNullOrEmpty($Context)) { return }
    Send-WebSocketObject @{
        event = 'showAlert'
        context = $Context
    }
}

function Get-ActiveMediaSession {
    if ($null -eq $script:SessionManager) { return $null }

    $session = $script:SessionManager.GetCurrentSession()
    if ($null -ne $session) { return $session }

    $fallback = $null
    foreach ($candidate in $script:SessionManager.GetSessions()) {
        if ($null -eq $fallback) { $fallback = $candidate }
        try {
            if ($candidate.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing') {
                return $candidate
            }
        }
        catch { }
    }
    return $fallback
}

function Initialize-MediaManager {
    $script:LastManagerAttempt = [DateTime]::UtcNow
    try {
        $managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
        $script:SessionManager = Wait-WinRtOperation -Operation $managerType::RequestAsync() -ResultType $managerType
        Write-PluginLog 'Windows media session manager is ready.'
        return $true
    }
    catch {
        $script:SessionManager = $null
        Write-PluginLog ('Media session manager is not ready; will retry: ' + $_.Exception.Message)
        return $false
    }
}

function Copy-ThumbnailImage {
    param($Thumbnail)
    if ($null -eq $Thumbnail) { return $null }

    $randomStream = $null
    $inputStream = $null
    $netStream = $null
    $sourceImage = $null
    try {
        $operation = $Thumbnail.OpenReadAsync()
        $streamType = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
        $randomStream = Wait-WinRtOperation -Operation $operation -ResultType $streamType
        # An async WinRT result is exposed by Windows PowerShell 5 as a bare
        # System.__ComObject. Invoke the declared WinRT interfaces through
        # MethodInfo so PowerShell's dynamic COM adapter is bypassed.
        $inputStream = $script:GetInputStreamAtMethod.Invoke(
            $randomStream,
            [object[]]@([UInt64]0))
        $netStream = $script:AsStreamForReadMethod.Invoke(
            $null,
            [object[]]@($inputStream, [int]8192))
        $sourceImage = [System.Drawing.Image]::FromStream($netStream)
        return New-Object System.Drawing.Bitmap($sourceImage)
    }
    catch {
        Write-PluginLog ('Thumbnail read failed: ' + $_.Exception.Message)
        return $null
    }
    finally {
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
        if ($null -ne $netStream) { $netStream.Dispose() }
        # inputStream/randomStream are WinRT COM projections on PowerShell 5;
        # they do not expose Dispose(). Their RCWs are released by the runtime.
        $inputStream = $null
        $randomStream = $null
    }
}

function Draw-MediaGlyph {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Brush]$Brush,
        [string]$GlyphType,
        [int]$IconPixels,
        [int]$OffsetX = 0,
        [int]$OffsetY = 0
    )

    $center = 72
    if ($GlyphType -eq 'pause') {
        $height = $IconPixels
        $totalWidth = [int][Math]::Round($IconPixels * 0.62)
        $barWidth = [Math]::Max(5, [int][Math]::Round($totalWidth * 0.31))
        $gap = $totalWidth - 2 * $barWidth
        $left = [int][Math]::Round($center - $totalWidth / 2.0) + $OffsetX
        $top = [int][Math]::Round($center - $height / 2.0) + $OffsetY
        $Graphics.FillRectangle($Brush, $left, $top, $barWidth, $height)
        $Graphics.FillRectangle($Brush, $left + $barWidth + $gap, $top, $barWidth, $height)
    }
    elseif ($GlyphType -eq 'play') {
        $height = $IconPixels
        $width = [int][Math]::Round($IconPixels * 0.82)
        # Center the triangle by its filled-area centroid, not its bounding box.
        $left = [int][Math]::Round($center - $width / 3.0) + $OffsetX
        $top = [int][Math]::Round($center - $height / 2.0) + $OffsetY
        $points = [System.Drawing.Point[]]@(
            [System.Drawing.Point]::new($left, $top),
            [System.Drawing.Point]::new($left, ($top + $height)),
            [System.Drawing.Point]::new(($left + $width), ($center + $OffsetY))
        )
        $Graphics.FillPolygon($Brush, $points)
    }
    elseif ($GlyphType -in @('next', 'previous')) {
        $height = [int][Math]::Round($IconPixels * 0.82)
        $triangleWidth = [int][Math]::Round($IconPixels * 0.30)
        $barWidth = [Math]::Max(4, [int][Math]::Round($IconPixels * 0.09))
        $gap = [Math]::Max(2, [int][Math]::Round($IconPixels * 0.045))
        $totalWidth = 2 * $triangleWidth + 2 * $gap + $barWidth
        $left = [int][Math]::Round($center - $totalWidth / 2.0) + $OffsetX
        $top = [int][Math]::Round($center - $height / 2.0) + $OffsetY
        $bottom = $top + $height
        $middle = $center + $OffsetY

        if ($GlyphType -eq 'next') {
            $first = $left
            $second = $first + $triangleWidth + $gap
            $firstPoints = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new($first, $top),
                [System.Drawing.Point]::new($first, $bottom),
                [System.Drawing.Point]::new(($first + $triangleWidth), $middle)
            )
            $secondPoints = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new($second, $top),
                [System.Drawing.Point]::new($second, $bottom),
                [System.Drawing.Point]::new(($second + $triangleWidth), $middle)
            )
            $Graphics.FillPolygon($Brush, $firstPoints)
            $Graphics.FillPolygon($Brush, $secondPoints)
            $Graphics.FillRectangle(
                $Brush,
                ($left + 2 * $triangleWidth + 2 * $gap),
                $top,
                $barWidth,
                $height)
        }
        else {
            $first = $left + $barWidth + $gap
            $second = $first + $triangleWidth + $gap
            $firstPoints = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(($first + $triangleWidth), $top),
                [System.Drawing.Point]::new(($first + $triangleWidth), $bottom),
                [System.Drawing.Point]::new($first, $middle)
            )
            $secondPoints = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(($second + $triangleWidth), $top),
                [System.Drawing.Point]::new(($second + $triangleWidth), $bottom),
                [System.Drawing.Point]::new($second, $middle)
            )
            $Graphics.FillRectangle($Brush, $left, $top, $barWidth, $height)
            $Graphics.FillPolygon($Brush, $firstPoints)
            $Graphics.FillPolygon($Brush, $secondPoints)
        }
    }
}

function Get-CustomIconImage {
    param([hashtable]$Settings)

    if ([string]::IsNullOrWhiteSpace($Settings.customIconData)) { return $null }
    $stream = $null
    $sourceImage = $null
    try {
        $comma = $Settings.customIconData.IndexOf(',')
        if ($comma -lt 0) { return $null }
        $bytes = [Convert]::FromBase64String($Settings.customIconData.Substring($comma + 1))
        $stream = [System.IO.MemoryStream]::new($bytes, $false)
        $sourceImage = [System.Drawing.Image]::FromStream($stream)
        return [System.Drawing.Bitmap]::new($sourceImage)
    }
    catch {
        Write-PluginLog ('Custom icon read failed: ' + $_.Exception.Message)
        return $null
    }
    finally {
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CustomIconRectangle {
    param(
        [System.Drawing.Image]$Image,
        [int]$IconPixels,
        [int]$OffsetX = 0,
        [int]$OffsetY = 0,
        [int]$Spread = 0
    )

    $box = [Math]::Min(140, [Math]::Max(4, $IconPixels + 2 * $Spread))
    $scale = [Math]::Min($box / [double]$Image.Width, $box / [double]$Image.Height)
    $width = [Math]::Max(1, [int][Math]::Round($Image.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($Image.Height * $scale))
    $left = [int][Math]::Round(72 - $width / 2.0) + $OffsetX
    $top = [int][Math]::Round(72 - $height / 2.0) + $OffsetY
    return [System.Drawing.Rectangle]::new($left, $top, $width, $height)
}

function New-ImageAttributes {
    param(
        [double]$AlphaMultiplier,
        [string]$TintColor = ''
    )

    $matrix = [System.Drawing.Imaging.ColorMatrix]::new()
    $matrix.Matrix33 = [single]$AlphaMultiplier
    if (-not [string]::IsNullOrWhiteSpace($TintColor)) {
        $color = Convert-HexToColor $TintColor 255
        $matrix.Matrix00 = 0
        $matrix.Matrix11 = 0
        $matrix.Matrix22 = 0
        $matrix.Matrix40 = [single]($color.R / 255.0)
        $matrix.Matrix41 = [single]($color.G / 255.0)
        $matrix.Matrix42 = [single]($color.B / 255.0)
    }
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    $attributes.SetColorMatrix(
        $matrix,
        [System.Drawing.Imaging.ColorMatrixFlag]::Default,
        [System.Drawing.Imaging.ColorAdjustType]::Bitmap)
    return $attributes
}

function Draw-CustomIcon {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Image]$Image,
        [int]$IconPixels,
        [hashtable]$Settings
    )

    $alpha = (100 - [int]$Settings.iconTransparency) / 100.0
    if ($alpha -le 0) { return }
    $rectangle = Get-CustomIconRectangle $Image $IconPixels
    $attributes = New-ImageAttributes $alpha
    try {
        $Graphics.DrawImage(
            $Image, $rectangle, 0, 0, $Image.Width, $Image.Height,
            [System.Drawing.GraphicsUnit]::Pixel, $attributes)
    }
    finally {
        $attributes.Dispose()
    }
}

function Draw-CustomIconShadow {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Image]$Image,
        [int]$IconPixels,
        [hashtable]$Settings
    )

    if (-not $Settings.shadowEnabled -or $Settings.shadowOpacity -le 0) { return }
    $blur = [int]$Settings.shadowBlur
    $offsets = New-Object System.Collections.ArrayList
    if ($blur -eq 0) {
        [void]$offsets.Add(@(0, 0))
    }
    else {
        $step = [Math]::Max(1, [int][Math]::Ceiling($blur / 3.0))
        for ($x = -$blur; $x -le $blur; $x += $step) {
            for ($y = -$blur; $y -le $blur; $y += $step) {
                if (($x * $x + $y * $y) -le ($blur * $blur)) {
                    [void]$offsets.Add(@($x, $y))
                }
            }
        }
        [void]$offsets.Add(@(0, 0))
    }
    $baseAlpha = $Settings.shadowOpacity / 100.0
    $passAlpha = if ($blur -eq 0) {
        $baseAlpha
    }
    else {
        [Math]::Max(0.004, $baseAlpha * 1.8 / $offsets.Count)
    }
    $attributes = New-ImageAttributes $passAlpha $Settings.shadowColor
    try {
        foreach ($point in $offsets) {
            $rectangle = Get-CustomIconRectangle `
                $Image $IconPixels `
                ([int]$Settings.shadowOffsetX + [int]$point[0]) `
                ([int]$Settings.shadowOffsetY + [int]$point[1]) `
                ([int]$Settings.shadowSpread)
            $Graphics.DrawImage(
                $Image, $rectangle, 0, 0, $Image.Width, $Image.Height,
                [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        }
    }
    finally {
        $attributes.Dispose()
    }
}

function Draw-MediaGlyphShadow {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$GlyphType,
        [int]$IconPixels,
        [hashtable]$Settings
    )

    if (-not $Settings.shadowEnabled -or $Settings.shadowOpacity -le 0) { return }

    $blur = [int]$Settings.shadowBlur
    $spreadPixels = [int]$Settings.shadowSpread
    $shadowPixels = [Math]::Min(140, $IconPixels + 2 * $spreadPixels)
    $offsetX = [int]$Settings.shadowOffsetX
    $offsetY = [int]$Settings.shadowOffsetY
    $baseAlpha = [int][Math]::Round(255 * $Settings.shadowOpacity / 100.0)

    $offsets = New-Object System.Collections.ArrayList
    if ($blur -eq 0) {
        [void]$offsets.Add(@(0, 0))
    }
    else {
        $step = [Math]::Max(1, [int][Math]::Ceiling($blur / 3.0))
        for ($x = -$blur; $x -le $blur; $x += $step) {
            for ($y = -$blur; $y -le $blur; $y += $step) {
                if (($x * $x + $y * $y) -le ($blur * $blur)) {
                    [void]$offsets.Add(@($x, $y))
                }
            }
        }
        [void]$offsets.Add(@(0, 0))
    }

    $passAlpha = if ($blur -eq 0) {
        $baseAlpha
    }
    else {
        [Math]::Max(1, [int][Math]::Round($baseAlpha * 1.8 / $offsets.Count))
    }
    $shadowColor = Convert-HexToColor $Settings.shadowColor $passAlpha
    $shadowBrush = [System.Drawing.SolidBrush]::new($shadowColor)
    try {
        foreach ($point in $offsets) {
            Draw-MediaGlyph $Graphics $shadowBrush $GlyphType $shadowPixels `
                ($offsetX + [int]$point[0]) ($offsetY + [int]$point[1])
        }
    }
    finally {
        $shadowBrush.Dispose()
    }
}

function Draw-Backdrop {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$CanvasSize,
        [hashtable]$Settings
    )

    if (-not $Settings.backdropEnabled -or $Settings.backdropTransparency -ge 100) { return }

    $diameter = [int][Math]::Round($CanvasSize * $Settings.backdropSize / 100.0)
    $targetAlpha = [int][Math]::Round(255 * (100 - $Settings.backdropTransparency) / 100.0)
    $blur = [Math]::Min([int]$Settings.backdropBlur, [int][Math]::Floor(($diameter - 4) / 2.0))

    if ($blur -le 0) {
        $position = [int][Math]::Round(($CanvasSize - $diameter) / 2.0)
        $brush = [System.Drawing.SolidBrush]::new(
            (Convert-HexToColor $Settings.backdropColor $targetAlpha))
        try {
            $Graphics.FillEllipse($brush, $position, $position, $diameter, $diameter)
        }
        finally {
            $brush.Dispose()
        }
        return
    }

    # Layer concentric translucent circles from outside to inside. Their
    # accumulated opacity reaches the selected value in the center while the
    # outer edge fades smoothly to transparent.
    $passes = [Math]::Min(32, [Math]::Max(5, 2 * $blur + 1))
    $targetOpacity = $targetAlpha / 255.0
    $passOpacity = 1.0 - [Math]::Pow(1.0 - $targetOpacity, 1.0 / $passes)
    $passAlpha = [Math]::Max(1, [int][Math]::Round(255 * $passOpacity))
    $brush = [System.Drawing.SolidBrush]::new(
        (Convert-HexToColor $Settings.backdropColor $passAlpha))
    try {
        for ($index = 0; $index -lt $passes; $index++) {
            $edgeOffset = $blur - (2.0 * $blur * $index / ($passes - 1))
            $layerDiameter = [int][Math]::Round($diameter + 2.0 * $edgeOffset)
            $layerPosition = [int][Math]::Round(($CanvasSize - $layerDiameter) / 2.0)
            $Graphics.FillEllipse(
                $brush,
                $layerPosition,
                $layerPosition,
                $layerDiameter,
                $layerDiameter)
        }
    }
    finally {
        $brush.Dispose()
    }
}

function Get-MediaText {
    param([string]$Title, [string]$Artist, [hashtable]$Settings)

    $safeTitle = if ([string]::IsNullOrWhiteSpace($Title)) { 'No media' } else { $Title.Trim() }
    $safeArtist = if ([string]::IsNullOrWhiteSpace($Artist)) { '' } else { $Artist.Trim() }
    switch ($Settings.textContent) {
        'title' { return $safeTitle }
        'artist' {
            if ([string]::IsNullOrWhiteSpace($safeArtist)) { return $safeTitle }
            return $safeArtist
        }
        default {
            if ([string]::IsNullOrWhiteSpace($safeArtist) -or $safeArtist -eq $safeTitle) {
                return $safeTitle
            }
            return "$safeTitle`n$safeArtist"
        }
    }
}

function Draw-MediaText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [hashtable]$Settings
    )

    $fontStyle = if ($Settings.textBold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $format = [System.Drawing.StringFormat]::new()
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit
    switch ($Settings.textAlignment) {
        'left' { $format.Alignment = [System.Drawing.StringAlignment]::Near }
        'right' { $format.Alignment = [System.Drawing.StringAlignment]::Far }
        default { $format.Alignment = [System.Drawing.StringAlignment]::Center }
    }
    switch ($Settings.textVerticalAlignment) {
        'top' { $format.LineAlignment = [System.Drawing.StringAlignment]::Near }
        'bottom' { $format.LineAlignment = [System.Drawing.StringAlignment]::Far }
        default { $format.LineAlignment = [System.Drawing.StringAlignment]::Center }
    }

    $rectangle = [System.Drawing.RectangleF]::new(8, 8, 128, 128)
    $font = $null
    $candidateSize = [int]$Settings.textSize
    while ($candidateSize -ge 8) {
        if ($null -ne $font) { $font.Dispose() }
        $font = [System.Drawing.Font]::new(
            [string]$Settings.textFontFamily,
            [single]$candidateSize,
            $fontStyle,
            [System.Drawing.GraphicsUnit]::Pixel)
        if (-not $Settings.textAutoFit) { break }
        $measured = $Graphics.MeasureString($Text, $font, [System.Drawing.SizeF]::new(128, 128), $format)
        if ($measured.Width -le 128.5 -and $measured.Height -le 128.5) { break }
        $candidateSize--
    }

    $textAlpha = [int][Math]::Round(255 * (100 - $Settings.textTransparency) / 100.0)
    $textBrush = $null
    if ($Settings.textFillMode -eq 'gradient') {
        $textBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $rectangle,
            (Convert-HexToColor $Settings.textGradientStart $textAlpha),
            (Convert-HexToColor $Settings.textGradientEnd $textAlpha),
            [single]$Settings.textGradientAngle)
    }
    else {
        $textBrush = [System.Drawing.SolidBrush]::new(
            (Convert-HexToColor $Settings.textColor $textAlpha))
    }
    try {
        if ($Settings.textShadowEnabled -and $Settings.textShadowOpacity -gt 0) {
            $blur = [int]$Settings.textShadowBlur
            $offsets = New-Object System.Collections.ArrayList
            if ($blur -eq 0) {
                [void]$offsets.Add(@(0, 0))
            }
            else {
                $step = [Math]::Max(1, [int][Math]::Ceiling($blur / 2.0))
                for ($x = -$blur; $x -le $blur; $x += $step) {
                    for ($y = -$blur; $y -le $blur; $y += $step) {
                        if (($x * $x + $y * $y) -le ($blur * $blur)) {
                            [void]$offsets.Add(@($x, $y))
                        }
                    }
                }
                [void]$offsets.Add(@(0, 0))
            }
            $baseAlpha = [int][Math]::Round(255 * $Settings.textShadowOpacity / 100.0)
            $passAlpha = if ($blur -eq 0) {
                $baseAlpha
            }
            else {
                [Math]::Max(1, [int][Math]::Round($baseAlpha * 1.8 / $offsets.Count))
            }
            $shadowBrush = [System.Drawing.SolidBrush]::new(
                (Convert-HexToColor $Settings.textShadowColor $passAlpha))
            try {
                foreach ($point in $offsets) {
                    $shadowRectangle = [System.Drawing.RectangleF]::new(
                        [single](8 + $Settings.textShadowOffsetX + [int]$point[0]),
                        [single](8 + $Settings.textShadowOffsetY + [int]$point[1]),
                        [single]128,
                        [single]128)
                    $Graphics.DrawString($Text, $font, $shadowBrush, $shadowRectangle, $format)
                }
            }
            finally {
                $shadowBrush.Dispose()
            }
        }

        if ($Settings.textOutlineEnabled -and $Settings.textOutlineOpacity -gt 0) {
            $outlineAlpha = [int][Math]::Round(255 * $Settings.textOutlineOpacity / 100.0)
            $outlineBrush = [System.Drawing.SolidBrush]::new(
                (Convert-HexToColor $Settings.textOutlineColor $outlineAlpha))
            try {
                $outlineWidth = [int]$Settings.textOutlineWidth
                for ($x = -$outlineWidth; $x -le $outlineWidth; $x++) {
                    for ($y = -$outlineWidth; $y -le $outlineWidth; $y++) {
                        if (($x -eq 0 -and $y -eq 0) -or ($x * $x + $y * $y) -gt ($outlineWidth * $outlineWidth + 1)) {
                            continue
                        }
                        $outlineRectangle = [System.Drawing.RectangleF]::new(
                            [single](8 + $x), [single](8 + $y), [single]128, [single]128)
                        $Graphics.DrawString($Text, $font, $outlineBrush, $outlineRectangle, $format)
                    }
                }
            }
            finally {
                $outlineBrush.Dispose()
            }
        }
        $Graphics.DrawString($Text, $font, $textBrush, $rectangle, $format)
    }
    finally {
        $textBrush.Dispose()
        $format.Dispose()
        $font.Dispose()
    }
}

function New-ButtonImage {
    param(
        [System.Drawing.Image]$Artwork,
        [bool]$IsPlaying,
        [hashtable]$Settings,
        [string]$Action,
        [string]$Title,
        [string]$Artist
    )

    $size = 144
    $actionDescriptor = Get-ActionDescriptor $Action
    $buttonFunction = if ($actionDescriptor.isGrid) { $Settings.buttonFunction } else { 'playPause' }
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $graphics.Clear([System.Drawing.Color]::FromArgb(255, 24, 26, 31))
        if ($null -ne $Artwork -and $Artwork.Width -gt 0 -and $Artwork.Height -gt 0) {
            $gridGap = if ($actionDescriptor.isGrid) { [int]$Settings.gridGap } else { 0 }
            $masterSize = if ($actionDescriptor.isGrid) { 2 * $size + $gridGap } else { $size }
            $scale = [Math]::Max($masterSize / [double]$Artwork.Width, $masterSize / [double]$Artwork.Height)
            $width = [int][Math]::Ceiling($Artwork.Width * $scale)
            $height = [int][Math]::Ceiling($Artwork.Height * $scale)
            $masterX = [int](($masterSize - $width) / 2)
            $masterY = [int](($masterSize - $height) / 2)
            $x = $masterX - [int]$actionDescriptor.column * ($size + $gridGap)
            $y = $masterY - [int]$actionDescriptor.row * ($size + $gridGap)
            $graphics.DrawImage($Artwork, $x, $y, $width, $height)
        }

        if ($buttonFunction -eq 'title') {
            $displayText = Get-MediaText $Title $Artist $Settings
            Draw-MediaText $graphics $displayText $Settings
        }
        elseif ($buttonFunction -in @('playPause', 'previous', 'next')) {
            Draw-Backdrop $graphics $size $Settings
            $glyphType = switch ($buttonFunction) {
                'previous' { 'previous' }
                'next' { 'next' }
                default { if ($IsPlaying) { 'pause' } else { 'play' } }
            }
            $iconPixels = [int][Math]::Round($size * $Settings.iconSize / 100.0)
            $customIcon = Get-CustomIconImage $Settings
            $iconBrush = $null
            try {
                if ($null -ne $customIcon) {
                    Draw-CustomIconShadow $graphics $customIcon $iconPixels $Settings
                    Draw-CustomIcon $graphics $customIcon $iconPixels $Settings
                }
                else {
                    Draw-MediaGlyphShadow $graphics $glyphType $iconPixels $Settings
                    $alpha = [int][Math]::Round(255 * (100 - $Settings.iconTransparency) / 100.0)
                    if ($Settings.fillMode -eq 'gradient') {
                        $startColor = Convert-HexToColor $Settings.gradientStart $alpha
                        $endColor = Convert-HexToColor $Settings.gradientEnd $alpha
                        $rectangle = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
                        $iconBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                            $rectangle, $startColor, $endColor, [single]$Settings.gradientAngle)
                    }
                    else {
                        $iconColor = Convert-HexToColor $Settings.solidColor $alpha
                        $iconBrush = [System.Drawing.SolidBrush]::new($iconColor)
                    }
                    Draw-MediaGlyph $graphics $iconBrush $glyphType $iconPixels
                }
            }
            finally {
                if ($null -ne $iconBrush) { $iconBrush.Dispose() }
                if ($null -ne $customIcon) { $customIcon.Dispose() }
            }
        }

        $memory = New-Object System.IO.MemoryStream
        try {
            $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            return 'data:image/png;base64,' + [Convert]::ToBase64String($memory.ToArray())
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Render-And-SendImages {
    param(
        [System.Drawing.Image]$Artwork,
        [bool]$IsPlaying,
        [string]$Title = '',
        [string]$Artist = ''
    )
    foreach ($context in @($script:Contexts.Keys)) {
        try {
            $settings = Get-SettingsForContext $context
            $action = if ($script:ContextActions.ContainsKey($context)) {
                [string]$script:ContextActions[$context]
            }
            else {
                'com.marehori.nowplaying.playpause'
            }
            $image = New-ButtonImage `
                -Artwork $Artwork `
                -IsPlaying $IsPlaying `
                -Settings $settings `
                -Action $action `
                -Title $Title `
                -Artist $Artist
            $script:LastImages[$context] = $image
            Send-ImageToContext -Context $context -DataUrl $image
        }
        catch {
            Write-PluginLog ("Rendering failed: context=$context; error=$($_.Exception.Message)")
        }
    }
}

function Update-MediaImage {
    param([bool]$Force = $false)

    try {
        $session = Get-ActiveMediaSession
        $script:CurrentSession = $session
        if ($null -eq $session) {
            $fingerprint = 'no-session'
            if ($Force -or $script:LastFingerprint -ne $fingerprint) {
                $script:LastFingerprint = $fingerprint
                Render-And-SendImages -Artwork $null -IsPlaying $false -Title 'No media' -Artist ''
            }
            return
        }

        $status = $session.GetPlaybackInfo().PlaybackStatus.ToString()
        $propertiesType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
        $properties = Wait-WinRtOperation -Operation $session.TryGetMediaPropertiesAsync() -ResultType $propertiesType
        $source = $session.SourceAppUserModelId
        $fingerprint = '{0}|{1}|{2}|{3}|{4}|{5}' -f $source, $properties.Title, $properties.Artist, $properties.AlbumTitle, $properties.TrackNumber, $status

        if (-not $Force -and $script:LastFingerprint -eq $fingerprint) { return }

        $artwork = Copy-ThumbnailImage -Thumbnail $properties.Thumbnail
        try {
            Render-And-SendImages `
                -Artwork $artwork `
                -IsPlaying ($status -eq 'Playing') `
                -Title ([string]$properties.Title) `
                -Artist ([string]$properties.Artist)
        }
        finally {
            if ($null -ne $artwork) { $artwork.Dispose() }
        }

        $script:LastFingerprint = $fingerprint
        Write-PluginLog ("Updated: source=$source; status=$status; title=$($properties.Title)")
    }
    catch {
        Write-PluginLog ('Media refresh failed: ' + $_.Exception.ToString())
    }
}

function Invoke-MediaCommand {
    param([string]$Context, [string]$Command)
    try {
        $session = Get-ActiveMediaSession
        if ($null -eq $session) {
            Send-Alert -Context $Context
            return
        }

        $operation = switch ($Command) {
            'previous' { $session.TrySkipPreviousAsync() }
            'next' { $session.TrySkipNextAsync() }
            default { $session.TryTogglePlayPauseAsync() }
        }
        $result = Wait-WinRtOperation -Operation $operation -ResultType ([bool])
        if (-not $result) {
            Send-Alert -Context $Context
            return
        }
        Start-Sleep -Milliseconds 180
        Update-MediaImage -Force $true
    }
    catch {
        Write-PluginLog ("Media command failed: command=$Command; error=$($_.Exception.ToString())")
        Send-Alert -Context $Context
    }
}

function Handle-HostMessage {
    param([string]$Json)
    try {
        $message = ConvertFrom-Json -InputObject $Json
        $eventName = ''
        $context = ''
        $action = ''
        if ($null -ne $message.PSObject.Properties['event']) {
            $eventName = [string]$message.event
        }
        if ($null -ne $message.PSObject.Properties['context']) {
            $context = [string]$message.context
        }
        if ($null -ne $message.PSObject.Properties['action']) {
            $action = [string]$message.action
        }
        $payload = $null
        $rawSettings = $null
        if ($null -ne $message.PSObject.Properties['payload']) {
            $payload = $message.payload
            if ($null -ne $payload -and $null -ne $payload.PSObject.Properties['settings']) {
                $rawSettings = $payload.settings
            }
        }
        Write-PluginLog ("Received: event=$eventName; context=$context; action=$action")

        # Some StreamDock builds may launch a native plugin after the action is
        # already visible and omit willAppear. Any later action event still has
        # the same usable context, so remember it before handling that event.
        if (-not [string]::IsNullOrEmpty($context) -and
            $eventName -ne 'willDisappear' -and
            $eventName -ne 'propertyInspectorDidAppear' -and
            $eventName -ne 'propertyInspectorDidDisappear' -and
            $eventName -ne 'sendToPlugin') {
            $script:Contexts[$context] = $true
            if (-not [string]::IsNullOrEmpty($action)) {
                $script:ContextActions[$context] = $action
            }
            if ($null -ne $rawSettings) {
                $script:ContextSettings[$context] = Get-NormalizedSettings $rawSettings $action
            }
        }

        switch ($eventName) {
            'willAppear' {
                Initialize-GridGapForContext $context
                Update-MediaImage -Force $true
            }
            'willDisappear' {
                $script:Contexts.Remove($context)
                $script:ContextActions.Remove($context)
                $script:ContextSettings.Remove($context)
                $script:LastImages.Remove($context)
            }
            'didReceiveSettings' {
                if ($script:ContextActions.ContainsKey($context) -and
                    (Get-ActionDescriptor ([string]$script:ContextActions[$context])).isGrid) {
                    Sync-GridGap -Gap ([int](Get-SettingsForContext $context).gridGap) -Persist $true
                }
                Update-MediaImage -Force $true
            }
            'sendToPlugin' {
                $targetContext = [string](Get-ObjectPropertyValue $payload 'actionContext' '')
                $sentSettings = Get-ObjectPropertyValue $payload 'settings' $null
                if (-not [string]::IsNullOrEmpty($targetContext) -and $null -ne $sentSettings) {
                    $script:Contexts[$targetContext] = $true
                    if (-not [string]::IsNullOrEmpty($action)) {
                        $script:ContextActions[$targetContext] = $action
                    }
                    $script:ContextSettings[$targetContext] = Get-NormalizedSettings $sentSettings $action
                    if ((Get-ActionDescriptor $action).isGrid) {
                        Sync-GridGap `
                            -Gap ([int]$script:ContextSettings[$targetContext].gridGap) `
                            -Persist $true
                    }
                    Update-MediaImage -Force $true
                }
            }
            'keyDown' {
                Initialize-GridGapForContext $context
                Update-MediaImage -Force $true
            }
            'keyUp' {
                Update-MediaImage -Force $true
                $contextAction = if ($script:ContextActions.ContainsKey($context)) {
                    [string]$script:ContextActions[$context]
                }
                else {
                    'com.marehori.nowplaying.playpause'
                }
                $descriptor = Get-ActionDescriptor $contextAction
                $buttonFunction = if ($descriptor.isGrid) {
                    (Get-SettingsForContext $context).buttonFunction
                }
                else {
                    'playPause'
                }
                if ($buttonFunction -in @('playPause', 'previous', 'next')) {
                    Invoke-MediaCommand -Context $context -Command $buttonFunction
                }
            }
        }
    }
    catch {
        Write-PluginLog ('Message handling failed: ' + $_.Exception.Message)
    }
}

try {
    if ([string]::IsNullOrEmpty($port) -or
        [string]::IsNullOrEmpty($pluginUUID) -or
        [string]::IsNullOrEmpty($registerEvent)) {
        Write-PluginLog 'Missing Stream Deck launch arguments.'
        exit 4
    }

    $script:WebSocket = New-Object System.Net.WebSockets.ClientWebSocket
    $uri = New-Object System.Uri("ws://127.0.0.1:$port")
    $script:WebSocket.ConnectAsync($uri, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    Send-WebSocketObject @{ event = $registerEvent; uuid = $pluginUUID }
    Write-PluginLog 'Connected to StreamDock host.'
    [void](Initialize-MediaManager)

    $buffer = New-Object byte[] 65536
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $buffer)
    $receiveTask = $script:WebSocket.ReceiveAsync($segment, [Threading.CancellationToken]::None)
    $messageText = New-Object System.Text.StringBuilder

    while ($script:WebSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        if ($receiveTask.IsCompleted) {
            $result = $receiveTask.GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
            if ($result.Count -gt 0) {
                [void]$messageText.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
            }
            if ($result.EndOfMessage) {
                Handle-HostMessage -Json $messageText.ToString()
                [void]$messageText.Clear()
            }
            $receiveTask = $script:WebSocket.ReceiveAsync($segment, [Threading.CancellationToken]::None)
        }

        if (([DateTime]::UtcNow - $script:LastRefresh).TotalMilliseconds -ge 700) {
            $script:LastRefresh = [DateTime]::UtcNow
            if ($null -eq $script:SessionManager -and
                ([DateTime]::UtcNow - $script:LastManagerAttempt).TotalSeconds -ge 10) {
                [void](Initialize-MediaManager)
            }
            if ($script:Contexts.Count -gt 0) {
                Update-MediaImage
            }
        }
        Start-Sleep -Milliseconds 50
    }
}
catch {
    Write-PluginLog ('Fatal error: ' + $_.Exception.ToString())
    exit 1
}
finally {
    if ($null -ne $script:WebSocket) {
        try { $script:WebSocket.Dispose() } catch { }
    }
    Write-PluginLog 'Plugin stopped.'
}
