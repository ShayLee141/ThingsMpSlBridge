param(
    # Build configuration whose output gets packed into dist/
    [string]$Configuration = "Debug",
    # steamcmd.exe path. Fallback: env STEAMCMD -> steamcmd on PATH -> C:\steamcmd\steamcmd.exe
    [string]$SteamCmd,
    # Steam account used for publishing. Fallback: env STEAM_USER
    [string]$SteamUser,
    # Render item.vdf and stage dist/ without uploading
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$Template = Join-Path $ProjectDir 'workshop\item.vdf.template'
$Output = Join-Path $ProjectDir 'workshop\item.vdf'
$ContentDir = Join-Path $ProjectDir 'dist'
$PreviewFile = Join-Path $ProjectDir 'workshop\preview.png'
$Manifest = Join-Path $ProjectDir 'ThingsMpSlBridge.json'

if (-not (Test-Path $Template)) { throw "Template not found: $Template" }
if (-not (Test-Path $PreviewFile)) { throw "Preview image not found: $PreviewFile" }

# Build output -> dist/ (Steam uploads whatever sits in the content folder)
$dllCandidates = @(
    "$ProjectDir\.godot\mono\temp\bin\$Configuration\ThingsMpSlBridge.dll",
    "$ProjectDir\bin\$Configuration\net9.0\ThingsMpSlBridge.dll"
)
$Dll = $dllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Dll) { throw "Build output not found. Run 'dotnet build' first. Looked in: $($dllCandidates -join ', ')" }

$null = New-Item -ItemType Directory -Force -Path $ContentDir
Copy-Item -Force $Dll (Join-Path $ContentDir 'ThingsMpSlBridge.dll')
Copy-Item -Force $Manifest $ContentDir

$vdf = Get-Content $Template -Raw
$vdf = $vdf.Replace('{{CONTENT_FOLDER}}', ($ContentDir -replace '\\', '/'))
$vdf = $vdf.Replace('{{PREVIEW_FILE}}', ($PreviewFile -replace '\\', '/'))

# UTF8 without BOM: steamcmd parses the first key strictly
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Output, $vdf, $utf8)

Write-Host "Staged content: $ContentDir"
Write-Host "Rendered vdf  : $Output"

if ($DryRun) {
    Write-Host "DryRun: skipping steamcmd upload." -ForegroundColor Yellow
    exit 0
}

if (-not $SteamCmd) { $SteamCmd = $env:STEAMCMD }
if (-not $SteamCmd) {
    $cmd = Get-Command steamcmd -ErrorAction SilentlyContinue
    if ($cmd) { $SteamCmd = $cmd.Source }
}
if (-not $SteamCmd -and (Test-Path 'C:\steamcmd\steamcmd.exe')) { $SteamCmd = 'C:\steamcmd\steamcmd.exe' }
if (-not $SteamCmd -or -not (Test-Path $SteamCmd)) {
    throw 'steamcmd not found. Pass -SteamCmd "C:\path\to\steamcmd.exe", or set env STEAMCMD.'
}

if (-not $SteamUser) { $SteamUser = $env:STEAM_USER }
if (-not $SteamUser) {
    throw 'Steam account not set. Pass -SteamUser <account>, or set env STEAM_USER.'
}

Write-Host "Uploading via $SteamCmd as $SteamUser" -ForegroundColor Yellow
& $SteamCmd +login $SteamUser +workshop_build_item $Output +quit
if ($LASTEXITCODE -ne 0) { throw "steamcmd exited with code $LASTEXITCODE" }
