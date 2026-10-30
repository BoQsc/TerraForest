# SPDX-License-Identifier: 0BSD
# Rebuild the boot PNG without resampling Godot's original splash artwork.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$brandingPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\branding'
$sourcePath = Join-Path $brandingPath 'source\godot-default.png'
$outputPath = Join-Path $brandingPath 'boot_splash.png'
$canvas = [System.Drawing.Bitmap]::new(1920, 1080, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$artwork = [System.Drawing.Image]::FromFile($sourcePath)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$font = [System.Drawing.Font]::new('Segoe UI', 26, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(176, 176, 176))
$format = [System.Drawing.StringFormat]::new()
try {
    if ($artwork.Width -ne 800 -or $artwork.Height -ne 600) {
        throw 'Expected the original 800 by 600 Godot splash.'
    }
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $separator = [char]0x2022
    $footer = "TerraForest $separator Open source"
    $bounds = [System.Drawing.RectangleF]::new(0, 999, 1920, 38)
    $graphics.DrawString($footer, $font, $brush, $bounds, $format)
    $graphics.Dispose()
    $graphics = $null
    # Copy straight-alpha pixels directly; DrawImage rounds translucent edges.
    $sourceBits = $artwork.LockBits([System.Drawing.Rectangle]::new(0, 0, 800, 600),
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $targetBits = $canvas.LockBits([System.Drawing.Rectangle]::new(560, 240, 800, 600),
            [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $row = [byte[]]::new(800 * 4)
            for ($y = 0; $y -lt 600; $y++) {
                [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($sourceBits.Scan0, $y * $sourceBits.Stride), $row, 0, $row.Length)
                [System.Runtime.InteropServices.Marshal]::Copy($row, 0, [IntPtr]::Add($targetBits.Scan0, $y * $targetBits.Stride), $row.Length)
            }
        } finally {
            $canvas.UnlockBits($targetBits)
        }
    } finally {
        $artwork.UnlockBits($sourceBits)
    }
    $canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Created $outputPath (1920 x 1080)"
} finally {
    $format.Dispose()
    $brush.Dispose()
    $font.Dispose()
    if ($null -ne $graphics) { $graphics.Dispose() }
    $artwork.Dispose()
    $canvas.Dispose()
}
