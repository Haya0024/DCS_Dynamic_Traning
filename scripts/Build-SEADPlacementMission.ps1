[CmdletBinding()]
param([string]$ZoneNames)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $projectRoot 'build/sead-placement-project'
foreach ($directory in @('src', 'scripts', 'vendor/MOOSE', 'mission')) {
    New-Item -ItemType Directory -Path (Join-Path $testRoot $directory) -Force | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.lua' -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $testRoot 'src') }
foreach ($script in @('Build-Mission.ps1', 'Sync-Mission.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $testRoot "scripts/$script")
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'vendor/MOOSE/Moose.lua') -Destination (Join-Path $testRoot 'vendor/MOOSE/Moose.lua')
Copy-Item -LiteralPath (Join-Path $projectRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz') -Destination (Join-Path $testRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz')
$controller = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SEAD-PlacementCheck.lua'))
$selection = ''
if ($ZoneNames) {
    $names = @($ZoneNames.Split(',') | ForEach-Object { $_.Trim() })
    if ($names.Count -eq 0 -or @($names | Select-Object -Unique).Count -ne $names.Count) { throw 'Select distinct SEAD zone names.' }
    foreach ($name in $names) { if ($name -notmatch '^SEAD_ZONE_[A-Z0-9_]+$') { throw "Invalid diagnostic zone name: $name" } }
    $literal = ($names | ForEach-Object { "'$_'" }) -join ', '
    $selection = "local selected = { $literal }`nlocal known = {}`nfor _, name in ipairs(Config.sead.zones) do known[name] = true end`nfor _, name in ipairs(selected) do assert(known[name], 'Unknown diagnostic zone: ' .. name) end`nConfig.sead.zones = selected`n"
}
$entry = "-- Placement diagnostic only. Normal runtime and persistence are not initialized.`n" + $selection + "local PlacementCheck = (function()`n" + $controller + "`nend)()`n" + @'
SEADPlacementCheckResults = PlacementCheck.Start(Config, SEAD, TrainingZones, timer, function(text)
    env.info("[SEADPlacementCheck] " .. text)
end)
'@
[System.IO.File]::WriteAllText((Join-Path $testRoot 'src/main.lua'), $entry, [System.Text.UTF8Encoding]::new($false))
& (Join-Path $testRoot 'scripts/Sync-Mission.ps1')
& (Join-Path $testRoot 'scripts/Sync-Mission.ps1') -Check
$output = Join-Path $projectRoot 'build/SEAD_Placement_Check.miz'
Copy-Item -LiteralPath (Join-Path $testRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz') -Destination $output
Write-Output "Built placement-only mission: $output"
