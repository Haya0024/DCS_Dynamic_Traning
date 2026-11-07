[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $projectRoot 'build/cas-autolase-project'
foreach ($directory in @('src','scripts','vendor/MOOSE','mission')) {
    New-Item -ItemType Directory -Path (Join-Path $testRoot $directory) -Force | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.lua' -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $testRoot 'src') }
foreach ($script in @('Build-Mission.ps1','Sync-Mission.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $testRoot "scripts/$script")
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'vendor/MOOSE/Moose.lua') -Destination (Join-Path $testRoot 'vendor/MOOSE/Moose.lua')
Copy-Item -LiteralPath (Join-Path $projectRoot 'mission/persistant_and_dynamic_traning.miz') -Destination (Join-Path $testRoot 'mission/persistant_and_dynamic_traning.miz')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CAS-AutolaseCheck.lua') -Destination (Join-Path $testRoot 'src/main.lua')
& (Join-Path $testRoot 'scripts/Sync-Mission.ps1')
& (Join-Path $testRoot 'scripts/Sync-Mission.ps1') -Check
$output = Join-Path $projectRoot 'build/CAS_Autolase_Check.miz'
Copy-Item -LiteralPath (Join-Path $testRoot 'mission/persistant_and_dynamic_traning.miz') -Destination $output
Write-Output "Built isolated CAS AUTOLASE diagnostic: $output"
