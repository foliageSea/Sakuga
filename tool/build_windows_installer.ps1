<#
.SYNOPSIS
Creates a Sakuga x64 installer from an existing Flutter Windows Release build.
.PARAMETER BuildName
The X.Y.Z version passed to flutter build windows --build-name.
.PARAMETER BuildNumber
The positive build number passed to flutter build windows --build-number.
.PARAMETER IsccPath
Optional path to ISCC.exe from Inno Setup 6.3 or later in the 6.x series.
If omitted, searches PATH and standard install directories.
.EXAMPLE
.\tool\build_windows_installer.ps1 -BuildName 1.2.3 -BuildNumber 45
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z')]
    [string]$BuildName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[1-9][0-9]*\z')]
    [string]$BuildNumber,

    [ValidateNotNullOrEmpty()]
    [string]$IsccPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$requiredFiles = @(
    'Sakuga.exe'
    'flutter_windows.dll'
    'libmpv-2.dll'
    'media_kit_event_loop.dll'
    'media_kit_video_plugin.dll'
    'data/icudtl.dat'
    'data/app.so'
    'data/flutter_assets/AssetManifest.bin'
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $file) -PathType Leaf)) {
        throw "Missing Windows Release file '$file' in '$releaseDir'. Build Sakuga with flutter build windows --release first."
    }
}

$exeVersion = (Get-Item -LiteralPath (Join-Path $releaseDir 'Sakuga.exe')).VersionInfo
$actualVersion = "$($exeVersion.FileMajorPart).$($exeVersion.FileMinorPart).$($exeVersion.FileBuildPart).$($exeVersion.FilePrivatePart)"
$expectedVersion = "$BuildName.$BuildNumber"
if ($actualVersion -ne $expectedVersion) {
    throw "Sakuga.exe has file version $actualVersion, not $expectedVersion. Use matching build arguments or rebuild Windows Release."
}

if ($PSBoundParameters.ContainsKey('IsccPath')) {
    if (-not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
        throw "ISCC executable not found at '$IsccPath'."
    }
    $compiler = (Get-Item -LiteralPath $IsccPath).FullName
} else {
    $isccCommand = Get-Command -Name 'ISCC.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $isccCommand) {
        $compiler = $isccCommand.Source
    } else {
        $compiler = $null
        $installRoots = @(
            ${env:ProgramFiles(x86)}
            $env:ProgramFiles
            if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' }
        )
        foreach ($root in $installRoots) {
            if (-not $root) { continue }
            $candidate = Join-Path $root 'Inno Setup 6/ISCC.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $compiler = $candidate
                break
            }
        }
    }
    if (-not $compiler) {
        throw 'Inno Setup 6 ISCC.exe was not found. Install Inno Setup 6 or pass -IsccPath.'
    }
}

$installerScript = Join-Path $PSScriptRoot 'windows-installer.iss'
& $compiler "/DBuildName=$BuildName" "/DBuildNumber=$BuildNumber" $installerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed (exit code $LASTEXITCODE)."
}

$installer = Join-Path $repoRoot "dist/Sakuga-$BuildName-$BuildNumber-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Inno Setup did not produce '$installer'."
}
Write-Output $installer
