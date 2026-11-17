param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Source,
    [Parameter(Mandatory = $true, Position = 1)][string]$Destination,
    [switch]$ConvertOnly,
    [string]$PrefabRoot
)

$ErrorActionPreference = 'Stop'
$python = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
    Where-Object Source -NotLike '*\Microsoft\WindowsApps\python.exe' | Select-Object -First 1
$arguments = @()
if (!$python) {
    $python = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $arguments = @('-3')
}
if (!$python) { throw 'Install Python 3 before importing a CoD2 map.' }
$converter = Join-Path $PSScriptRoot 'import_cod2_map.py'
$converterArguments = @($converter, $Source, $Destination)
if ($PrefabRoot) { $converterArguments += @('--prefab-root', $PrefabRoot) }
& $python.Source @arguments @converterArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($ConvertOnly) { exit 0 }

$launcher = Join-Path $PSScriptRoot 'Start_RawFront_Radiant.ps1'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw 'Conversion completed. Open the generated map in RawFront Radiant. Use the launcher from the 0.5 installation to open automatically.'
}
& $launcher -SetupOnly
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$map = (Resolve-Path -LiteralPath $Destination).ProviderPath
Start-Process -FilePath (Join-Path $PSScriptRoot 'radiant.exe') -ArgumentList ('"' + $map + '"') -WorkingDirectory $PSScriptRoot
