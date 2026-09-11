# Builds ModDownloadFix.dll and drops it in an r2modman profile.
#
#   powershell -ExecutionPolicy Bypass -File .\build.ps1
#
# Drives csc directly rather than 'dotnet build' so no targeting pack is needed - the references below are the
# game's own assemblies plus BepInEx, which is what the mod runs against anyway.

param(
    # Which r2modman profile to deploy into.
    [string]$ProfileName = 'Dev',

    # Skip the deploy. package.ps1 uses this so a running game cannot block a build.
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'

$GameDir    = 'C:\Program Files (x86)\Steam\steamapps\common\Holdfast Nations At War'
$ManagedDir = Join-Path $GameDir 'Holdfast NaW_Data\Managed'
$ProfileDir = Join-Path $env:APPDATA "r2modmanPlus-local\HoldfastNationsAtWar\profiles\$ProfileName"
$BepInExDir = Join-Path $ProfileDir 'BepInEx\core'
$PluginsDir = Join-Path $ProfileDir 'BepInEx\plugins\ModDownloadFix'
$OutFile    = Join-Path $PSScriptRoot 'ModDownloadFix.dll'

if (-not (Test-Path $ManagedDir)) { throw "Missing directory: $ManagedDir" }
if (-not (Test-Path $BepInExDir)) {
    throw "No BepInEx in profile '$ProfileName'. Install BepInExPack through r2modman first. Looked in: $BepInExDir"
}

$csc = Get-ChildItem -Path 'C:\Program Files\dotnet\sdk' -Recurse -Filter 'csc.dll' -ErrorAction SilentlyContinue |
       Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $csc) { throw 'Could not find the Roslyn compiler under the dotnet SDK.' }

$refs = @(
    (Join-Path $ManagedDir 'mscorlib.dll'),
    (Join-Path $ManagedDir 'System.dll'),
    (Join-Path $ManagedDir 'System.Core.dll'),
    (Join-Path $ManagedDir 'netstandard.dll'),
    (Join-Path $ManagedDir 'UnityEngine.dll'),
    (Join-Path $ManagedDir 'UnityEngine.CoreModule.dll'),
    (Join-Path $ManagedDir 'Assembly-CSharp.dll'),
    (Join-Path $ManagedDir 'HoldfastEnums.Runtime.dll'),
    (Join-Path $ManagedDir 'HoldfastUtils.Runtime.dll'),
    (Join-Path $BepInExDir 'BepInEx.dll'),
    (Join-Path $BepInExDir '0Harmony.dll')
)

$cscArgs = @('-nologo', '-noconfig', '-nostdlib+', '-target:library', "-out:$OutFile")
foreach ($r in $refs) {
    if (-not (Test-Path $r)) { throw "Missing reference assembly: $r" }
    $cscArgs += "-r:$r"
}

$sources = Get-ChildItem -Path $PSScriptRoot -Filter '*.cs' -File
if ($sources.Count -eq 0) { throw "No .cs files found in $PSScriptRoot" }
foreach ($s in $sources) { $cscArgs += $s.FullName }

Write-Host "Compiling $($sources.Count) file(s) -> $OutFile"
& dotnet exec $csc.FullName @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Compile failed (exit $LASTEXITCODE)" }

if ($NoDeploy) {
    Write-Host "Built $OutFile (not deployed)."
    return
}

try {
    if (-not (Test-Path $PluginsDir)) { New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null }
    Copy-Item $OutFile (Join-Path $PluginsDir 'ModDownloadFix.dll') -Force
    Write-Host "Copied to $PluginsDir. Restart the game to load it."
}
catch [System.IO.IOException] {
    throw "Built fine, but could not copy into $PluginsDir - the game is probably running and has the DLL loaded. Close Holdfast and run this again."
}
