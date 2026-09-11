# Builds ModDownloadFix and stages a Thunderstore package in Package\ ready to upload.
#
#   powershell -ExecutionPolicy Bypass -File .\package.ps1
#
# Does not tag, commit or upload - it only produces the zip and prints the steps.

param(
    # Which r2modman profile to take the BepInEx reference assemblies from.
    [string]$ProfileName = 'Dev'
)

$ErrorActionPreference = 'Stop'

$ModName    = 'ModDownloadFix'
$PackageDir = Join-Path $PSScriptRoot 'Package'
$StageDir   = Join-Path $PackageDir $ModName
$Dll        = Join-Path $PSScriptRoot "$ModName.dll"
$Icon       = Join-Path $PSScriptRoot 'icon.png'
$Manifest   = Join-Path $PSScriptRoot 'manifest.json'

# -NoDeploy so a running game holding the installed copy cannot block a package build.
& (Join-Path $PSScriptRoot 'build.ps1') -NoDeploy -ProfileName $ProfileName
if (-not (Test-Path $Dll)) { throw "Build produced no $ModName.dll" }

foreach ($f in @($Icon, $Manifest, (Join-Path $PSScriptRoot 'README.md'), (Join-Path $PSScriptRoot 'LICENSE'))) {
    if (-not (Test-Path $f)) { throw "Missing packaging file: $f" }
}

# Thunderstore rejects anything but exactly 256x256, and finds out only after the upload.
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($Icon)
$w = $image.Width; $h = $image.Height
$image.Dispose()
if ($w -ne 256 -or $h -ne 256) { throw "icon.png must be exactly 256x256, this one is ${w}x${h}." }

# Thunderstore caps the description at 250 characters and only says so after the upload.
$manifestJson = Get-Content $Manifest -Raw | ConvertFrom-Json
if ($manifestJson.description.Length -gt 250) {
    throw "manifest description is $($manifestJson.description.Length) characters, Thunderstore allows 250."
}

# Version comes off the built DLL so there is only one place to bump it.
$fileVersion = (Get-Item $Dll).VersionInfo.FileVersion
if ([string]::IsNullOrWhiteSpace($fileVersion)) { throw 'Could not read a version off the built DLL.' }
$parts = $fileVersion.Split('.')
if ($parts.Count -lt 3) { throw "Unexpected assembly version '$fileVersion'." }
$version = "$($parts[0]).$($parts[1]).$($parts[2])"

if (Test-Path $PackageDir) { Remove-Item $PackageDir -Recurse -Force }
$pluginDir = Join-Path $StageDir "BepInEx\plugins\$ModName"
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null

Copy-Item $Dll $pluginDir -Force
Copy-Item $Icon $StageDir -Force
Copy-Item (Join-Path $PSScriptRoot 'README.md') $StageDir -Force
Copy-Item (Join-Path $PSScriptRoot 'LICENSE') $StageDir -Force
if (Test-Path (Join-Path $PSScriptRoot 'CHANGELOG.md')) {
    Copy-Item (Join-Path $PSScriptRoot 'CHANGELOG.md') $StageDir -Force
}

# Edited as text: ConvertTo-Json in PowerShell 5.1 flattens the one-element dependencies array to a string.
$raw = Get-Content $Manifest -Raw
$patched = [regex]::Replace($raw, '("version_number"\s*:\s*")[^"]*(")', "`${1}$version`${2}")
if ($patched -eq $raw -and $raw -notmatch "`"version_number`"\s*:\s*`"$([regex]::Escape($version))`"") {
    throw 'Could not set version_number in manifest.json - check the field is present.'
}

# No BOM: Thunderstore parses the manifest as plain UTF-8 and a byte order mark can break it.
[System.IO.File]::WriteAllText((Join-Path $StageDir 'manifest.json'), $patched, (New-Object System.Text.UTF8Encoding($false)))

$zip = Join-Path $PackageDir "$ModName-$version.zip"

# Not Compress-Archive: PowerShell 5.1 writes backslash entry names that r2modman cannot unpack correctly.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($file in Get-ChildItem -Path $StageDir -Recurse -File) {
        $entry = $file.FullName.Substring($StageDir.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

Write-Host "`nStaged $ModName v$version at $zip" -ForegroundColor Green

Write-Host @'

To publish:

  1. Install this exact zip into the Live profile: r2modman -> Settings -> Import local mod. Play a round.
  2. thunderstore.io/c/holdfast-nations-at-war/ -> Upload, team Ryanlt, pick the Package\ zip.
  3. Categories: Mods, Client-side.
  4. Commit, push, and tag the release to match.

Step 1 is not optional. A version can never be reused, and an author cannot delete a package or any version of
it, only deprecate it. A bad upload is permanent.
'@
