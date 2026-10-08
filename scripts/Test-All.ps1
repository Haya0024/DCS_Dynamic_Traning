[CmdletBinding()]
param([string]$LuaPath)

# One repeatable entry point; integration tests use disposable fixtures only.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuaPath) {
    $luaCommand = Get-Command lua -ErrorAction SilentlyContinue
    if ($luaCommand) { $LuaPath = $luaCommand.Source }
    else { $LuaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe' }
}
if (-not (Test-Path -LiteralPath $LuaPath -PathType Leaf)) {
    throw 'Lua 5.1 executable not found. Pass -LuaPath with the installed lua/luae.exe path.'
}
$LuaPath = (Resolve-Path -LiteralPath $LuaPath).Path
$suites = @(
    'Test-Intercept.lua', 'Test-CAP.lua', 'Test-Scoring.lua',
    'Test-Wing.lua', 'Test-ParallelWings.lua', 'Test-SEAD.lua',
    'Test-DEAD.lua', 'Test-Persistence.lua', 'Test-MapOverlay.lua'
)
Push-Location -LiteralPath $projectRoot
try {
    & (Join-Path $PSScriptRoot 'Build-Mission.ps1')
    & (Join-Path $PSScriptRoot 'Build-PersistenceHook.ps1')
    foreach ($suite in $suites) {
        $result = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot $suite) | & $LuaPath -
        if ($LASTEXITCODE -ne 0) {
            $result | Write-Output
            throw "Lua test failed: $suite"
        }
        $result | Select-Object -Last 1 | Write-Output
    }
    foreach ($test in @('Test-MissionBuild.ps1', 'Test-MissionSync.ps1')) {
        & (Join-Path $PSScriptRoot $test)
    }
    & (Join-Path $PSScriptRoot 'Test-PersistenceInstall.ps1') -LuaPath $LuaPath
    & (Join-Path $PSScriptRoot 'Test-ZoneCoverage.ps1') -LuaPath $LuaPath
    Write-Output 'All Lua and integration tests passed. Actual mission sync is a separate step.'
} finally {
    Pop-Location
}
