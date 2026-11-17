param([Parameter(Mandatory)][string]$AssetPath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$scripts = Join-Path $AssetPath 'scripts'
$images = Join-Path $scripts 'radiant_gameplay'
$null = New-Item -ItemType Directory -Path $images -Force
$tools = @{
    ladder = @{ text = 'LADDER'; color = '#327BA4' }
    no_mantle = @{ text = 'NO MANTLE'; color = '#A34F37' }
}

$font = [Drawing.Font]::new('Arial', 17, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$center = New-Object Drawing.StringFormat
$center.Alignment = [Drawing.StringAlignment]::Center
$center.LineAlignment = [Drawing.StringAlignment]::Center
try {
    foreach ($name in $tools.Keys) {
        $bitmap = [Drawing.Bitmap]::new(128, 128)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.ColorTranslator]::FromHtml($tools[$name].color))
            $graphics.DrawString($tools[$name].text, $font, [Drawing.Brushes]::White, [Drawing.RectangleF]::new(0, 0, 128, 128), $center)
            $bitmap.Save((Join-Path $images "$name.png"), [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
} finally {
    $font.Dispose()
    $center.Dispose()
}

$shaders = @'
textures/tools/ladder
{
    qer_editorimage scripts/radiant_gameplay/ladder.png
    qer_trans 0.4
}
textures/tools/no_mantle
{
    qer_editorimage scripts/radiant_gameplay/no_mantle.png
    qer_trans 0.4
}
textures/tools/passes_players
{
    qer_editorimage textures/tools/clip.png
    qer_trans 0.4
}
textures/tools/passes_shots
{
    qer_editorimage textures/tools/clip.png
    qer_trans 0.4
}
textures/tools/passes_projectiles
{
    qer_editorimage textures/tools/clip.png
    qer_trans 0.4
}
'@
[IO.File]::WriteAllText((Join-Path $scripts 'gameplay_tools_02.shader'), $shaders + [Environment]::NewLine)
