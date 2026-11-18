param(
    [Parameter(Mandatory)][string]$Map,
    [string]$Report,
    [switch]$Notify
)
$ErrorActionPreference = 'Stop'
$workspace = Join-Path $PSScriptRoot 'rawfront-workspace'
$editor = Join-Path $workspace 'editor\rawfront'
$stock = Join-Path $workspace 'stock'
$file = Get-Item -LiteralPath $Map
$name = $file.BaseName
$mapSources = Join-Path $workspace "content\maps\$name"
$runtimeMap = Join-Path $stock "maps\$name"
$references = [ordered]@{}
$missing = [ordered]@{}
$reportLines = [Collections.Generic.List[string]]::new()
function Add-Reference([string]$type, [string]$path) {
    if (!$path -or $path -in 'none','-','$null') { return }
    $key = "[$type] $path"
    if ($references.Contains($key)) { $references[$key].Count++; return }
    $references[$key] = [pscustomobject]@{ Type=$type; Path=$path; Count=1 }
}
function Test-Asset([string]$relative, [string[]]$roots) {
    if ($relative -notmatch '^[\w.-]+(?:/[\w.-]+)*$' -or $relative -match '(^|/)\.{1,2}(/|$)') { return $false }
    foreach ($directory in $roots) {
        if (Test-Path -LiteralPath (Join-Path $directory $relative) -PathType Leaf) { return $true }
    }
    return $false
}
function Add-Missing($reference) {
    $key = "[$($reference.Type)] $($reference.Path)"
    $missing[$key] = $reference
}
$source = [IO.File]::ReadAllText($file.FullName)
$mapText = [regex]::Replace($source,'(?m)^\s*//[^\r\n]*','')
$face = '(?m)^[ \t]*\(\s*-?[\d.]+[^\r\n]*?\)[ \t]+(?:"(?<shader>[^"\r\n]+)"|(?<shader>[\w./-]+))[ \t]+-?[\d.]'
foreach ($match in [regex]::Matches($mapText,$face)) {
    $asset = $match.Groups['shader'].Value -replace '^textures/',''
    $kind = if ($asset.StartsWith('tools/')) { 'Tool' } else { 'Material' }
    Add-Reference $kind $asset
}
foreach ($match in [regex]::Matches($mapText,'(?m)^\s*patchDef[23]\s*\{\s*"?(?<shader>[\w./-]+)"?\s*(?=\()')) {
    $asset = $match.Groups['shader'].Value -replace '^textures/',''
    $kind = if ($asset.StartsWith('tools/')) { 'Tool' } else { 'Material' }
    Add-Reference $kind $asset
}
foreach ($match in [regex]::Matches($mapText,'(?m)^\s*"(?<key>model|prefab|script|client_script|server_script)"\s+"(?<path>[^"\r\n]+)"')) {
    $asset = $match.Groups['path'].Value.Replace('\','/')
    $kind = switch -Regex ($match.Groups['key'].Value) {
        '^model$' { if ($asset.EndsWith('.map')) { 'Prefab' } else { 'Model' } }
        '^prefab$' { 'Prefab' }
        default { 'Script' }
    }
    Add-Reference $kind $asset
}
# The map header can declare its adjacent game scripts in comments.
foreach ($match in [regex]::Matches($source,'(?m)^\s*//[^\r\n]*?\b([\w.-]+\.(?:server|client)\.luau)\b')) {
    Add-Reference 'Script' $match.Groups[1].Value
}
$library = Join-Path $workspace 'content'
foreach ($reference in @($references.Values)) {
    $asset = $reference.Path
    $known = $false
    switch ($reference.Type) {
        'Script' { $known = Test-Asset $asset @($runtimeMap,$mapSources,$stock,$library) }
        'Prefab' { $known = Test-Asset $asset @($editor,$workspace,$library,$mapSources) }
        'Model' {
            $known = Test-Asset $asset @($editor,$library)
            # A brush-built prop still needs generation by Tools. Report absent editor preview.
            if (!$known -and $asset.EndsWith('.gltf')) {
                $brushSource = $asset.Substring(0,$asset.Length-5) + '.map'
                if (Test-Asset $brushSource @($library)) {
                    $reportLines.Add("Source present, preview not generated: $brushSource")
                }
            }
        }
        default {
            foreach ($ext in 'png','jpg','tga','dds') {
                if (Test-Asset "textures/$asset.$ext" @($editor)) { $known=$true; break }
            }
            if (!$known -and $reference.Type -eq 'Material') {
                $leaf = $asset.Split('/')[-1]
                $relative = if ($asset.StartsWith("$name/")) { "materials/$leaf/$leaf.material.json" } else { "$asset/$leaf.material.json" }
                $materialRoot = if ($asset.StartsWith("$name/")) { $mapSources } else { $library }
                if (Test-Asset $relative @($materialRoot)) {
                    $known=$true
                    $definitionPath = Join-Path $materialRoot $relative
                    try { $definition = Get-Content -LiteralPath $definitionPath -Raw | ConvertFrom-Json }
                    catch {
                        Add-Missing $reference
                        $reportLines.Add("Unreadable material definition: $relative")
                        continue
                    }
                    foreach ($field in 'color','normal','height','orm','roughness','metallic','emissive') {
                        $value=$definition.$field
                        if ($value -is [string] -and $value -match '\.(png|jpe?g|tga|dds|ktx2)$') {
                            Add-Reference 'Texture' "$($relative.Substring(0,$relative.LastIndexOf('/')))/$value"
                            if (!(Test-Asset $value @((Split-Path $definitionPath)))) {
                                Add-Missing $references["[Texture] $($relative.Substring(0,$relative.LastIndexOf('/')))/$value"]
                            }
                        }
                    }
                    $reportLines.Add("Material source present, preview not generated: $asset")
                }
            }
        }
    }
    if (!$known) { Add-Missing $reference }
}
$lines = @("Missing Assets: $($missing.Count)", "Map: $($file.Name)") + @(
    $missing.Values | Sort-Object Type,Path | ForEach-Object { "[$($_.Type)] $($_.Path) (x$($_.Count))" }
) + @($reportLines.ToArray())
if ($Report) { [IO.File]::WriteAllLines($Report, [string[]]$lines) }
$lines | Write-Output
if ($Notify -and !$env:ENGINE_RADIANT_PLAY_TEST -and ($missing.Count -or $reportLines.Count)) {
    $shell = New-Object -ComObject WScript.Shell
    $summary = ($lines | Select-Object -First 12) -join [Environment]::NewLine
    $null = $shell.Popup("$summary`n`nFull copyable report: $Report`n`nOK continues to Tools.", 0, 'RawFront Radiant - Missing Assets', 48)
}

