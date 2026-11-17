param([switch]$SetupOnly)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$buildVersion = '0.10-preview.1'
$checkout = Join-Path $root 'rawfront-workspace'
$toolsDir = Join-Path $root 'modding'
$tools = Join-Path $toolsDir 'tools.exe'
$officialProfile = Join-Path $root 'gamepacks\games\rawfront.game'
$profile = Join-Path $root 'gamepacks\games\engine.game'
$gamepack = Join-Path $root 'gamepacks\engine.game'
$editorPath = Join-Path $checkout 'editor'
$assetPath = Join-Path $editorPath 'rawfront'
$settings = Join-Path $root 'settings\1.6.0'
$ready = Join-Path $checkout '.radiant-preview-configured'
$buildMarker = Join-Path $checkout '.rawfront-build'
$utf8 = New-Object Text.UTF8Encoding($false)
$temporary = $null
$setupLock = $null

function Install-Tools {
    $zip = Join-Path $temporary ([IO.Path]::GetRandomFileName() + '.zip')
    $expanded = Join-Path $temporary ([IO.Path]::GetRandomFileName())
    $download = @{
        UseBasicParsing = $true
        Uri = 'https://get.rawfront.com/get/tools-windows-x64.zip'
        OutFile = $zip
        TimeoutSec = 900
    }
    if ($env:HTTPS_PROXY) { $download.Proxy = $env:HTTPS_PROXY }
    Invoke-WebRequest @download
    Expand-Archive -LiteralPath $zip -DestinationPath $expanded
    if (!(Test-Path -LiteralPath (Join-Path $expanded 'tools.exe') -PathType Leaf)) {
        throw 'The official RawFront Tools archive did not contain tools.exe.'
    }
    Move-Item -LiteralPath $expanded -Destination $toolsDir
}

function Update-EnginePath($file, $profileFile) {
    [xml]$xml = [IO.File]::ReadAllText($file)
    $enginePath = $editorPath.Replace('\', '/') + '/'
    if ($profileFile) {
        if ($xml.game.GetAttribute('enginepath_win32') -ceq $enginePath) { return }
        foreach ($platform in 'win32','linux','macos') {
            $xml.game.SetAttribute("enginepath_$platform", $enginePath)
        }
    } else {
        $pathNode = $xml.SelectSingleNode('/qpref/epair[@name="EnginePath"]')
        if (!$pathNode -or $pathNode.InnerText -ceq $enginePath) { return }
        $pathNode.InnerText = $enginePath
    }
    $xml.Save($file)
}

try {
    if ($root -cmatch '[^\x20-\x7e]') {
        throw 'This Radiant build requires an ASCII installation path. Move the extracted folder to a writable path with basic Latin characters.'
    }
    if (!(Test-Path -LiteralPath (Join-Path $root 'radiant.exe') -PathType Leaf)) {
        throw 'radiant.exe is missing. Extract the entire package.'
    }
    $setupLock = [IO.File]::Open((Join-Path $root '.setup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $temporary = Join-Path $root ('.setup-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temporary
    if (!(Test-Path -LiteralPath $checkout)) {
        $workspace = Join-Path $temporary 'workspace'
        $null = New-Item -ItemType Directory -Force (Join-Path $workspace 'content'), (Join-Path $workspace 'stock')
        [IO.File]::WriteAllText((Join-Path $workspace '.rawfront-build'), $buildVersion, $utf8)
        Move-Item -LiteralPath $workspace -Destination $checkout
    }
    if (!(Test-Path -LiteralPath $toolsDir)) {
        Write-Host 'Downloading official RawFront Tools...'
        Install-Tools
    }
    if (!(Test-Path -LiteralPath $tools -PathType Leaf)) { throw 'The local modding folder is missing tools.exe.' }
    if ((Get-Content -LiteralPath $buildMarker -Raw).Trim() -cne $buildVersion) {
        throw "This preview requires official content for RawFront $buildVersion."
    }
    if (!(Test-Path -LiteralPath $ready) -or !(Test-Path -LiteralPath $profile) -or
        !(Test-Path -LiteralPath (Join-Path $assetPath 'rawfront.ent'))) {
        Write-Host 'Preparing the RawFront profile and editor assets. Tools may download the matching game build...'
        Push-Location -LiteralPath $checkout
        try {
            & $tools radiant $root
            if ($LASTEXITCODE -ne 0) { throw "RawFront Tools radiant exited with code $LASTEXITCODE." }
        } finally { Pop-Location }
        if (!(Test-Path -LiteralPath $officialProfile -PathType Leaf)) { throw 'RawFront Tools did not create the game profile.' }
        $null = New-Item -ItemType Directory -Force (Join-Path $assetPath 'maps')
        $entityDirectory = Join-Path $gamepack 'rawfront'
        $null = New-Item -ItemType Directory -Force $entityDirectory, (Join-Path $gamepack 'install')
        Move-Item -LiteralPath $officialProfile -Destination $profile -Force
        Copy-Item -LiteralPath (Join-Path $root 'gamepacks\rawfront.game\rawfront\rawfront.ent') -Destination $entityDirectory
        Copy-Item -LiteralPath (Join-Path $root 'Support\radiant_extensions.ent') -Destination $entityDirectory
        Copy-Item -LiteralPath (Join-Path $root 'Support\default_build_menu.xml') -Destination $gamepack
        & (Join-Path $root 'Support\Prepare_Gameplay_Textures.ps1') -AssetPath $assetPath
        [IO.File]::WriteAllText($ready, $buildVersion, $utf8)
    }

    Update-EnginePath $profile $true
    $gameSettings = Join-Path $settings 'engine.game'
    $null = New-Item -ItemType Directory -Force $gameSettings
    $global = Join-Path $settings 'global.pref'
    if (!(Test-Path -LiteralPath $global)) {
        [IO.File]::WriteAllText($global, '<qpref version="1.0"><epair name="gamePrompt">false</epair><epair name="gamefile">engine.game</epair></qpref>', $utf8)
    }
    $local = Join-Path $gameSettings 'local.pref'
    if (!(Test-Path -LiteralPath $local)) {
        $engine = [Security.SecurityElement]::Escape($editorPath.Replace('\', '/') + '/')
        [IO.File]::WriteAllText($local, "<qpref version=`"1.0`"><epair name=`"EnginePath`">$engine</epair><epair name=`"ModelBrowserFolders`">*props/99*maps/99*</epair></qpref>", $utf8)
    } else { Update-EnginePath $local $false }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) {
        $resolved = (Resolve-Path -LiteralPath $temporary).ProviderPath
        if ($resolved.StartsWith($root + '\.setup-', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    if ($setupLock) { $setupLock.Dispose() }
}

if (!$SetupOnly) { Start-Process -FilePath (Join-Path $root 'radiant.exe') -WorkingDirectory $root }
