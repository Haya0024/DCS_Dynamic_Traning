[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$builder = [System.Text.StringBuilder]::new()
[void]$builder.Append("-- Generated persistence hook. Edit src/score_data.lua and server/*.lua.`n")
foreach ($entry in @(@('src/score_data.lua', 'ScoreData'), @('server/score_store.lua', 'ScoreStore'),
    @('server/persistence_fs.lua', 'PersistenceFS'), @('server/mission_bridge.lua', 'MissionBridge'),
    @('server/persistence_service.lua', 'PersistenceService'))) {
    [void]$builder.Append("local $($entry[1]) = (function()`n")
    [void]$builder.Append([System.IO.File]::ReadAllText((Join-Path $projectRoot $entry[0])).Replace("`r`n", "`n"))
    [void]$builder.Append("`nend)()`n`n")
}
[void]$builder.Append([System.IO.File]::ReadAllText((Join-Path $projectRoot 'server/DynamicTrainingPersistenceHook.lua')).Replace("`r`n", "`n"))
$destination = Join-Path $projectRoot 'build/DynamicTrainingPersistenceHook.lua'
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
[System.IO.File]::WriteAllText($destination, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
