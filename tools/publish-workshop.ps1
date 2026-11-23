param(
    # steamcmd.exe path. Fallback: env STEAMCMD -> steamcmd on PATH -> C:\steamcmd\steamcmd.exe
    [string]$SteamCmd,
    # Steam account used for publishing. Fallback: env STEAM_USER
    [string]$SteamUser,
    # Render item.vdf and print paths without uploading
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$Template = Join-Path $ProjectDir 'workshop\item.vdf.template'
$Output = Join-Path $ProjectDir 'workshop\item.vdf'
$ContentDir = Join-Path $ProjectDir 'dist'
$PreviewFile = Join-Path $ProjectDir 'workshop\preview.png'

if (-not (Test-Path $Template)) { throw "Template not found: $Template" }
if (-not (Test-Path (Join-Path $ContentDir 'ThingsMpSlBridge.dll'))) {
    throw "dist is missing or empty. Run tools/build.ps1 first, then copy the built files into dist."
}
if (-not (Test-Path $PreviewFile)) { throw "Preview image not found: $PreviewFile" }

$vdf = Get-Content $Template -Raw
$vdf = $vdf.Replace('{{CONTENT_FOLDER}}', ($ContentDir -replace '\\', '/'))
$vdf = $vdf.Replace('{{PREVIEW_FILE}}', ($PreviewFile -replace '\\', '/'))

# UTF8 without BOM: steamcmd parses the first key strictly
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Output, $vdf, $utf8)

Write-Host "Rendered: $Output" -ForegroundColor Cyan
Write-Host "  contentfolder = $ContentDir"
Write-Host "  previewfile   = $PreviewFile"

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
