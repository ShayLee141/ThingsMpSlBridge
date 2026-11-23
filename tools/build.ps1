param(
    [string]$Configuration = "Debug",
    # Game install dir (the folder containing SlayTheSpire2.exe).
    # Resolution order: -GameDir -> env STS2_GAME_DIR -> local.props -> auto-detect from Steam libraries
    [string]$GameDir
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot

function Get-SteamLibraryRoots {
    $roots = @()
    $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamPath) { return $roots }
    $roots += $steamPath
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $roots += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }
    return $roots | Select-Object -Unique
}

function Find-Sts2GameDir {
    foreach ($root in Get-SteamLibraryRoots) {
        $candidate = Join-Path $root 'steamapps\common\Slay the Spire 2'
        if (Test-Path (Join-Path $candidate 'SlayTheSpire2.exe')) { return $candidate }
    }
    return $null
}

if (-not $GameDir) { $GameDir = $env:STS2_GAME_DIR }
if (-not $GameDir) {
    $localProps = Join-Path $ProjectDir 'local.props'
    if (Test-Path $localProps) {
        [xml]$props = Get-Content $localProps -Raw
        $GameDir = $props.Project.PropertyGroup.Sts2GameDir
        if ($GameDir -and -not (Test-Path (Join-Path $GameDir 'SlayTheSpire2.exe'))) { $GameDir = $null }
    }
}
if (-not $GameDir) { $GameDir = Find-Sts2GameDir }
if (-not $GameDir -or -not (Test-Path (Join-Path $GameDir 'SlayTheSpire2.exe'))) {
    throw 'Game dir not found. Pass -GameDir "D:\...\Slay the Spire 2", or copy local.props.example to local.props and set Sts2GameDir.'
}

$GameModsDir = Join-Path $GameDir 'mods\ThingsMpSlBridge'

Write-Host "=== ThingsMpSlBridge Build ===" -ForegroundColor Cyan
Write-Host "Game dir: $GameDir" -ForegroundColor DarkGray

Write-Host "Building ($Configuration)..." -ForegroundColor Yellow
dotnet build "$ProjectDir\ThingsMpSlBridge.csproj" -c $Configuration -p:Sts2GameDir="$GameDir"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$candidates = @(
    "$ProjectDir\.godot\mono\temp\bin\$Configuration\ThingsMpSlBridge.dll",
    "$ProjectDir\bin\$Configuration\net9.0\ThingsMpSlBridge.dll"
)
$DllSource = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $DllSource) { throw "Built DLL not found. Looked in: $($candidates -join ', ')" }

Write-Host "Installing to $GameModsDir" -ForegroundColor Yellow
$null = New-Item -ItemType Directory -Force -Path $GameModsDir
Copy-Item -Force $DllSource (Join-Path $GameModsDir 'ThingsMpSlBridge.dll')
Copy-Item -Force (Join-Path $ProjectDir 'ThingsMpSlBridge.json') $GameModsDir

# Keep dist/ (workshop upload source) in sync with the build
$DistDir = Join-Path $ProjectDir 'dist'
$null = New-Item -ItemType Directory -Force -Path $DistDir
Copy-Item -Force $DllSource (Join-Path $DistDir 'ThingsMpSlBridge.dll')
Copy-Item -Force (Join-Path $ProjectDir 'ThingsMpSlBridge.json') $DistDir

Write-Host "Done! Restart the game to reload." -ForegroundColor Green
