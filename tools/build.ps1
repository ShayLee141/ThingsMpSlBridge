param(
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$GameModsDir = "F:\SteamLibrary\steamapps\common\Slay the Spire 2\mods\ThingsMpSlBridge"

Write-Host "=== ThingsMpSlBridge Build ===" -ForegroundColor Cyan

Write-Host "Building ($Configuration)..." -ForegroundColor Yellow
dotnet build "$ProjectDir\ThingsMpSlBridge.csproj" -c $Configuration
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$candidates = @(
    "$ProjectDir\.godot\mono\temp\bin\$Configuration\ThingsMpSlBridge.dll",
    "$ProjectDir\bin\$Configuration\net9.0\ThingsMpSlBridge.dll"
)
$DllSource = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $DllSource) { throw "Built DLL not found. Looked in: $($candidates -join ', ')" }

Write-Host "Installing to $GameModsDir" -ForegroundColor Yellow
$null = New-Item -ItemType Directory -Force -Path $GameModsDir
Copy-Item -Force $DllSource "$GameModsDir\ThingsMpSlBridge.dll"
Copy-Item -Force "$ProjectDir\ThingsMpSlBridge.json" $GameModsDir

Write-Host "Done! Restart the game to reload." -ForegroundColor Green
