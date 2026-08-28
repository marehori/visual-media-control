param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$brandColor = [System.Drawing.Color]::FromArgb(255, 181, 136, 158) # #B5889E

function New-BrandIcon {
    param([int]$Size, [string]$Path)

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $brush = [System.Drawing.SolidBrush]::new($brandColor)
        $slash = [System.Drawing.Pen]::new($brandColor, [single][Math]::Max(1.5, $Size * 0.065))
        $slash.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $slash.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        try {
            $playLeft = [int][Math]::Round($Size * 0.08)
            $playTop = [int][Math]::Round($Size * 0.25)
            $playBottom = [int][Math]::Round($Size * 0.75)
            $playRight = [int][Math]::Round($Size * 0.38)
            $playPoints = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new($playLeft, $playTop),
                [System.Drawing.Point]::new($playLeft, $playBottom),
                [System.Drawing.Point]::new($playRight, [int][Math]::Round($Size * 0.50))
            )
            $graphics.FillPolygon($brush, $playPoints)

            $graphics.DrawLine(
                $slash,
                [int][Math]::Round($Size * 0.46), [int][Math]::Round($Size * 0.78),
                [int][Math]::Round($Size * 0.57), [int][Math]::Round($Size * 0.22))

            $barTop = [int][Math]::Round($Size * 0.26)
            $barHeight = [int][Math]::Round($Size * 0.48)
            $barWidth = [Math]::Max(2, [int][Math]::Round($Size * 0.075))
            $graphics.FillRectangle($brush, [int][Math]::Round($Size * 0.67), $barTop, $barWidth, $barHeight)
            $graphics.FillRectangle($brush, [int][Math]::Round($Size * 0.82), $barTop, $barWidth, $barHeight)
        }
        finally {
            $slash.Dispose()
            $brush.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-GridIcon {
    param([int]$Size, [string]$Path, [int]$SelectedColumn, [int]$SelectedRow)

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $accent = [System.Drawing.SolidBrush]::new($brandColor)
        $inactive = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(90, 181, 136, 158))
        $line = [System.Drawing.Pen]::new($brandColor, [single][Math]::Max(1, $Size * 0.025))
        try {
            $margin = [int][Math]::Round($Size * 0.17)
            $gap = [Math]::Max(2, [int][Math]::Round($Size * 0.07))
            $cell = [int](($Size - 2 * $margin - $gap) / 2)
            for ($row = 0; $row -lt 2; $row++) {
                for ($column = 0; $column -lt 2; $column++) {
                    $x = $margin + $column * ($cell + $gap)
                    $y = $margin + $row * ($cell + $gap)
                    $brush = if ($column -eq $SelectedColumn -and $row -eq $SelectedRow) { $accent } else { $inactive }
                    $graphics.FillRectangle($brush, $x, $y, $cell, $cell)
                    $graphics.DrawRectangle($line, $x, $y, $cell, $cell)
                }
            }
        }
        finally {
            $accent.Dispose()
            $inactive.Dispose()
            $line.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

New-BrandIcon -Size 144 -Path (Join-Path $OutputDirectory 'action.png')
New-BrandIcon -Size 288 -Path (Join-Path $OutputDirectory 'action@2x.png')
New-BrandIcon -Size 28 -Path (Join-Path $OutputDirectory 'category.png')
New-BrandIcon -Size 56 -Path (Join-Path $OutputDirectory 'category@2x.png')
New-BrandIcon -Size 256 -Path (Join-Path $OutputDirectory 'plugin.png')
New-BrandIcon -Size 512 -Path (Join-Path $OutputDirectory 'plugin@2x.png')
New-GridIcon -Size 144 -Path (Join-Path $OutputDirectory 'top-left.png') -SelectedColumn 0 -SelectedRow 0
New-GridIcon -Size 288 -Path (Join-Path $OutputDirectory 'top-left@2x.png') -SelectedColumn 0 -SelectedRow 0
New-GridIcon -Size 144 -Path (Join-Path $OutputDirectory 'top-right.png') -SelectedColumn 1 -SelectedRow 0
New-GridIcon -Size 288 -Path (Join-Path $OutputDirectory 'top-right@2x.png') -SelectedColumn 1 -SelectedRow 0
New-GridIcon -Size 144 -Path (Join-Path $OutputDirectory 'bottom-left.png') -SelectedColumn 0 -SelectedRow 1
New-GridIcon -Size 288 -Path (Join-Path $OutputDirectory 'bottom-left@2x.png') -SelectedColumn 0 -SelectedRow 1
New-GridIcon -Size 144 -Path (Join-Path $OutputDirectory 'bottom-right.png') -SelectedColumn 1 -SelectedRow 1
New-GridIcon -Size 288 -Path (Join-Path $OutputDirectory 'bottom-right@2x.png') -SelectedColumn 1 -SelectedRow 1
