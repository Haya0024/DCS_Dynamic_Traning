# Isolated installer and real-file hook integration; never edits Saved Games.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dcs-persistence-install-' + [guid]::NewGuid().ToString('N'))
$oldTestRoot = $env:DCS_TRAINING_TEST_ROOT
$oldTestPhase = $env:DCS_TRAINING_TEST_PHASE
try {
    foreach ($directory in @('Config', 'Scripts/Hooks', 'DynamicTraining')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    $otherHook = Join-Path $fixtureRoot 'Scripts/Hooks/OtherHook.lua'
    [System.IO.File]::WriteAllText($otherHook, '-- unrelated hook')
    $target = Join-Path $fixtureRoot 'Scripts/Hooks/DynamicTrainingPersistenceHook.lua'
    [System.IO.File]::WriteAllText($target, '-- previous version')
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot
    if ((Get-Content -LiteralPath $otherHook -Raw) -cne '-- unrelated hook') { throw 'Other hook changed' }
    $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Filter '*.bak')
    if ($backups.Count -ne 1 -or (Get-Content -LiteralPath $backups[0].FullName -Raw) -cne '-- previous version') {
        throw 'Previous hook backup missing'
    }
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Filter '*.bak').Count -ne 1) {
        throw 'Idempotent install unexpectedly wrote another backup'
    }
    Write-Host 'PASS: verified hook installation, backup, unrelated hook preservation, idempotence'
    $refused = $false
    try { & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath (Join-Path $fixtureRoot 'DynamicTraining') }
    catch { $refused = $true }
    if (-not $refused) { throw 'Invalid DCS directory was accepted' }
    Write-Host 'PASS: invalid installation directory rejected'
    & (Join-Path $PSScriptRoot 'Build-Mission.ps1')
    $luaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe'
    if (-not (Test-Path -LiteralPath $luaPath)) { throw 'Set luaPath to your Lua 5.1/DCS luae.exe installation' }
    $env:DCS_TRAINING_TEST_ROOT = $fixtureRoot
    foreach ($phase in @('write', 'restore', 'recover')) {
        $env:DCS_TRAINING_TEST_PHASE = $phase
        Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Test-PersistenceDisk.lua') | & $luaPath -
        if ($LASTEXITCODE -ne 0) { throw "Disk persistence test failed: $phase" }
    }
    Write-Host 'PASS: real filesystem save, fresh-process restoration, corrupt-primary backup recovery'
} finally {
    $env:DCS_TRAINING_TEST_ROOT = $oldTestRoot
    $env:DCS_TRAINING_TEST_PHASE = $oldTestPhase
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedFixture) -notmatch '^dcs-persistence-install-[0-9a-f]{32}$') {
        throw 'Refusing cleanup outside the verified fixture directory'
    }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
