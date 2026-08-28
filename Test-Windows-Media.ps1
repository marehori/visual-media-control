$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
        $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1

function Wait-WinRtOperation {
    param($Operation, [Type]$ResultType)
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, [object[]]@($Operation))
    $task.GetAwaiter().GetResult()
}

try {
    $managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $manager = Wait-WinRtOperation ($managerType::RequestAsync()) $managerType
    $session = $manager.GetCurrentSession()
    if ($null -eq $session) {
        Write-Host 'GSMTC_OK: Windows responded, but no media session is currently active.' -ForegroundColor Yellow
        exit 0
    }

    $propertiesType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
    $properties = Wait-WinRtOperation ($session.TryGetMediaPropertiesAsync()) $propertiesType
    Write-Host 'GSMTC_OK' -ForegroundColor Green
    Write-Host "Application: $($session.SourceAppUserModelId)"
    Write-Host "Status:      $($session.GetPlaybackInfo().PlaybackStatus)"
    Write-Host "Title:       $($properties.Title)"
    Write-Host "Artist:      $($properties.Artist)"
    Write-Host "Has artwork: $($null -ne $properties.Thumbnail)"
}
catch {
    Write-Host 'GSMTC_ERROR: Windows did not provide a system media session.' -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
