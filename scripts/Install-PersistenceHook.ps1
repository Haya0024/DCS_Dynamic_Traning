[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$SavedGamesPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedRoot = (Resolve-Path -LiteralPath $SavedGamesPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot 'Config') -PathType Container)) {
    throw 'Specify the DCS user directory containing Config (for example Saved Games/DCS).'
}
& (Join-Path $PSScriptRoot 'Build-PersistenceHook.ps1')
$hookDirectory = Join-Path $resolvedRoot 'Scripts/Hooks'
New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null
$destination = Join-Path $hookDirectory 'DynamicTrainingPersistenceHook.lua'
$source = Join-Path $projectRoot 'build/DynamicTrainingPersistenceHook.lua'
if ((Test-Path -LiteralPath $destination) -and
    (Get-FileHash -LiteralPath $destination).Hash -eq (Get-FileHash -LiteralPath $source).Hash) {
    Write-Host 'Persistence hook already current.'
    return
}
if (Test-Path -LiteralPath $destination) {
    $backup = $destination + '.' + [guid]::NewGuid().ToString('N') + '.bak'
    Copy-Item -LiteralPath $destination -Destination $backup
}
Copy-Item -LiteralPath $source -Destination $destination
if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
    throw 'Installed hook verification failed.'
}
Write-Host "Installed: $destination"
Write-Host 'Restart DCS to load the hook. MissionScripting.lua is unchanged.'
