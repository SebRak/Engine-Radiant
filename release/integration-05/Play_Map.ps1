param([Parameter(Mandatory)][string]$Map)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$checkout = Join-Path $root 'rawfront-workspace'
$tools = Join-Path $root 'modding\tools.exe'
$phase = 'Validation'

function Get-ExportHash([string]$path) {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($path)
        try {
            [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha256.Dispose()
    }
}

function Convert-GameplayMaterials([string]$source) {
    $flags = @{
        ladder = 16
        no_mantle = 32
        passes_players = 1
        passes_shots = 2
        passes_projectiles = 4
    }
    $names = $flags.Keys -join '|'
    $asset = '(?:(?:textures/)?tools/(?<tool>' + $names + '))'
    $face = '(?m)^(?<plane>[ \t]*\([^\r\n]*?\)[ \t]+)(?:"' + $asset + '"|' + $asset + ')[ \t]+(?<contents>\d+)(?<tail>[ \t]+-?\d+[ \t]+-?\d+[ \t]*)(?=\r?$|//)'
    $brush = '(?m)^(?<open>[ \t]*\{\s*brushDef\s*\{)(?<body>[^{}]*)(?<close>\}\s*\})'
    $converted = [regex]::Replace($source, $brush, {
        param($b)
        $body = $b.Groups['body'].Value
        $toolFaces = [regex]::Matches($body, $face)
        if ($toolFaces.Count -eq 0) { return $b.Value }

        $tool = $toolFaces[0].Groups['tool'].Value
        $faceLines = [regex]::Matches($body, '(?m)^[ \t]*\(')
        if ($toolFaces.Count -ne $faceLines.Count -or
            ($toolFaces | Where-Object { $_.Groups['tool'].Value -cne $tool })) {
            throw "Apply tools/$tool to all faces of a separate technical brush."
        }

        $body = [regex]::Replace($body, $face, {
            param($m)
            $contents = [uint32]::Parse($m.Groups['contents'].Value) -bor $flags[$tool]
            $m.Groups['plane'].Value + 'tools/clip ' + $contents + $m.Groups['tail'].Value
        })
        $b.Groups['open'].Value + $body + $b.Groups['close'].Value
    })
    $withoutComments = $converted -replace '(?m)^[ \t]*//[^\r\n]*', ''
    if ($withoutComments -cmatch ('(?:textures/)?tools/(?:' + $names + ')(?![\w/])')) {
        throw 'Gameplay materials require a complete Brush Primitive brush. An unsupported use remains in the map.'
    }
    $converted
}

function Convert-EditorMap([string]$source) {
    $tokens = [regex]::Matches($source, '//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]')
    $result = [Text.StringBuilder]::new()
    $depth = 0
    $cursor = 0
    $properties = @{}
    foreach ($token in $tokens) {
        if ($token.Value -eq '{') {
            if ($depth -eq 0) {
                $start = $token.Index
                $properties.Clear()
                $key = $null
            }
            $depth++
        } elseif ($token.Value -eq '}') {
            $depth--
            if ($depth -eq 0 -and $properties.ContainsKey('classname')) {
                $class = $properties['classname']
                if ($class.Value -match '^"(Actor_|actor_reference(?:"|_))') {
                    [void]$result.Append($source, $cursor, $start - $cursor)
                    $cursor = $token.Index + 1
                } elseif ($class.Value -ieq '"Spawn"') {
                    $entity = $source.Substring($start, $token.Index + 1 - $start)
                    $entity = $entity.Remove($class.Index - $start, $class.Length).Insert($class.Index - $start, '"marker"')
                    if ($properties.ContainsKey('name')) { throw 'Spawn helper has an unexpected name property. Recreate it or use marker with name spawn.' }
                    $entity = $entity.Insert(1, [Environment]::NewLine + '"name" "spawn"' + [Environment]::NewLine)
                    [void]$result.Append($source, $cursor, $start - $cursor)
                    [void]$result.Append($entity)
                    $cursor = $token.Index + 1
                }
            }
            if ($depth -lt 0) { throw 'Invalid MAP entity braces.' }
        } elseif ($depth -eq 1 -and $token.Value.StartsWith('"')) {
            if ($null -eq $key) {
                $key = $token.Value.Trim('"')
            } else {
                $properties[$key] = $token
                $key = $null
            }
        }
    }
    if ($depth -ne 0) { throw 'Invalid MAP entity braces.' }
    [void]$result.Append($source, $cursor, $source.Length - $cursor)
    $result.ToString()
}

try {
    $lock = [IO.File]::Open((Join-Path $root 'myroom-play-in-editor.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (!(Test-Path -LiteralPath $tools -PathType Leaf)) { throw 'tools.exe is missing.' }
    $build = Join-Path $checkout '.rawfront-build'
    if (!(Test-Path -LiteralPath $build -PathType Leaf)) { throw 'The rawfront-workspace checkout is missing.' }
    if ((Get-Content -LiteralPath $build -Raw).Trim() -cne '0.10-preview.1') { throw 'Play requires RawFront 0.10-preview.1.' }

    $file = Get-Item -LiteralPath $Map
    $name = $file.BaseName
    $expected = Join-Path $checkout "content\maps\$name\$name.map"
    if ($file.PSIsContainer -or $file.Extension -ine '.map' -or $name -cnotmatch '^[a-z0-9_]{1,64}$') {
        throw 'Use a .map file with a name containing lowercase letters, digits or underscores.'
    }
    $export = $file.FullName -ine $expected
    $editorMaps = (Join-Path $checkout 'editor\rawfront\maps') + [IO.Path]::DirectorySeparatorChar
    if ($export -and !$file.FullName.StartsWith($editorMaps, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Save the map under editor/rawfront/maps or content/maps/<name>/<name>.map.'
    }
    $source = [IO.File]::ReadAllText($file.FullName)
    $gameMap = Convert-GameplayMaterials (Convert-EditorMap $source)
    if (!$export -and $gameMap -cne $source) {
        throw 'Save maps with editor-only actors, spawn helpers or gameplay materials under editor/rawfront/maps. Play exports the game copy automatically.'
    }

    if ($export) {
        $receipt = Join-Path $root "play-map-exports\$name.json"
        $exists = Test-Path -LiteralPath $expected
        if ($exists) {
            $previous = if (Test-Path -LiteralPath $receipt -PathType Leaf) {
                Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
            }
            if ($previous.source -ine $file.FullName -or
                (Get-ExportHash $expected) -cne $previous.hash) {
                throw "A different or independently edited map already exists at $expected. Rename the editor map to play it."
            }
        }
        $null = New-Item -ItemType Directory -Force (Split-Path $expected), (Split-Path $receipt)
        $temporary = Join-Path (Split-Path $expected) ([guid]::NewGuid().ToString('N') + '.tmp')
        try {
            if ($gameMap -ceq $source) {
                [IO.File]::Copy($file.FullName, $temporary)
            } else {
                [IO.File]::WriteAllText($temporary, $gameMap)
            }
            $hash = Get-ExportHash $temporary
            if ($exists) {
                $backup = $temporary + '.bak'
                [IO.File]::Replace($temporary, $expected, $backup)
                Remove-Item -LiteralPath $backup
            } else {
                [IO.File]::Move($temporary, $expected)
            }
            @{ source = $file.FullName; hash = $hash } | ConvertTo-Json |
                Set-Content -LiteralPath $receipt -Encoding utf8
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
    }

    $metadata = Join-Path $checkout "stock\maps\$name\$name.jsonc"
    if (!(Test-Path -LiteralPath $metadata)) {
        $null = New-Item -ItemType Directory -Force (Split-Path $metadata)
        $json = @{ title = $name; gametypes = @('tdm') } | ConvertTo-Json
        $stream = [IO.File]::Open($metadata, 'CreateNew', 'Write', 'None')
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
    $config = Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
    if ($config.gametypes -cnotcontains 'tdm') { throw 'This map does not declare TDM in its JSONC.' }

    $logs = (New-Item -ItemType Directory (Join-Path $root ('play_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')))).FullName
    foreach ($step in @('import', 'play')) {
        $phase = $step
        $argsForTools = if ($step -eq 'import') { "import content/maps/$name/$name.map" } else { "play --map $name --gametype tdm" }
        if ($step -eq 'play') {
            $env:APPDATA = (New-Item -ItemType Directory -Force (Join-Path $checkout 'play-appdata')).FullName
        }
        $process = Start-Process -FilePath $tools -ArgumentList $argsForTools -WorkingDirectory $checkout -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$logs\$step.stdout.txt" -RedirectStandardError "$logs\$step.stderr.txt"
        $process.ExitCode | Set-Content "$logs\$step.exit.txt"
        if ($process.ExitCode -ne 0) { throw "$step failed ($($process.ExitCode)). Logs: $logs" }
    }
} catch {
    $message = "$phase - $($_.Exception.Message)"
    if ($lock) {
        $lock.Dispose()
        $lock = $null
    }
    Write-Host $message
    if (!$env:ENGINE_RADIANT_PLAY_TEST) {
        $shell = New-Object -ComObject WScript.Shell
        $null = $shell.Popup($message, 0, 'RawFront Radiant Play', 16)
    }
    exit 1
} finally {
    if ($lock) { $lock.Dispose() }
}
