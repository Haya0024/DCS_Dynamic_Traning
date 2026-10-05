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
    $autoexec = Join-Path $fixtureRoot 'Config/autoexec.cfg'
    $original = "-- 既存の設定`r`nDLSS_Preset = 'K'`r`nHUD_MFD_after_DLSS = true`r`nnet = { allow_unsafe_api = { 'gui' }, allow_dostring_in = { 'export' } }`r`n"
    [System.IO.File]::WriteAllText($autoexec, $original, [System.Text.UTF8Encoding]::new($true))
    $originalHash = (Get-FileHash -LiteralPath $autoexec).Hash
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost
    if (-not ([System.IO.File]::ReadAllText($autoexec).StartsWith($original))) { throw 'Existing host settings changed' }
    $configBackups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $autoexec) -Filter 'autoexec.cfg.*.bak')
    if ($configBackups.Count -ne 1 -or (Get-FileHash -LiteralPath $configBackups[0].FullName).Hash -ne $originalHash) {
        throw 'Exact host configuration backup missing'
    }
    $hostHash = (Get-FileHash -LiteralPath $autoexec).Hash
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost
    if ((Get-FileHash -LiteralPath $autoexec).Hash -ne $hostHash -or
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $autoexec) -Filter 'autoexec.cfg.*.bak').Count -ne 1) {
        throw 'Repeated host configuration changed content or added a backup'
    }
    $hostChecks = @'
local path = assert(os.getenv("DCS_TRAINING_TEST_ROOT")) .. "/Config/autoexec.cfg"
for attempt = 1, 2 do
    assert(loadfile(path))()
    assert(DLSS_Preset == "K" and HUD_MFD_after_DLSS == true)
    assert(#net.allow_unsafe_api == 2 and net.allow_unsafe_api[1] == "gui" and net.allow_unsafe_api[2] == "userhooks")
    assert(#net.allow_dostring_in == 2 and net.allow_dostring_in[1] == "export" and net.allow_dostring_in[2] == "server")
end
'@
    # luae/loadfile may treat a UTF-8 BOM as code; DCS's config loader accepts it.
    # Strip only the fixture BOM before executing its content in Lua 5.1.
    $configuredText = [System.IO.File]::ReadAllText($autoexec)
    [System.IO.File]::WriteAllText($autoexec, $configuredText, [System.Text.UTF8Encoding]::new($false))
    $hostChecks | & $luaPath -
    if ($LASTEXITCODE -ne 0) { throw 'Configured host permission semantics failed' }
    [System.IO.File]::WriteAllText($autoexec, $original, [System.Text.UTF8Encoding]::new($false))
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost
    if (-not ([System.IO.File]::ReadAllText($autoexec).StartsWith($original, [StringComparison]::Ordinal))) {
        throw 'BOM-free existing host settings changed'
    }
    $hostHash = (Get-FileHash -LiteralPath $autoexec).Hash
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost
    if ((Get-FileHash -LiteralPath $autoexec).Hash -ne $hostHash) { throw 'BOM-free config is not idempotent' }
    [System.IO.File]::WriteAllText($autoexec, '')
    & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost
    if (-not ([System.IO.File]::ReadAllText($autoexec).StartsWith('-- BEGIN DYNAMIC TRAINING'))) {
        throw 'Empty host config could not be configured'
    }
    Write-Host 'PASS: host config preservation, exact backup, idempotence and limited permission merge'
    foreach ($badConfig in @(
        '-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST',
        "-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST`n-- END DYNAMIC TRAINING PERSISTENCE HOST`n-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST`n-- END DYNAMIC TRAINING PERSISTENCE HOST`n",
        "-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST broken`n-- END DYNAMIC TRAINING PERSISTENCE HOST`n"
    )) {
        [System.IO.File]::WriteAllText($autoexec, $badConfig)
        $badHash = (Get-FileHash -LiteralPath $autoexec).Hash
        $hookHash = (Get-FileHash -LiteralPath $target).Hash
        $refused = $false
        try { & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost }
        catch { $refused = $true }
        if (-not $refused -or (Get-FileHash -LiteralPath $autoexec).Hash -ne $badHash -or
            (Get-FileHash -LiteralPath $target).Hash -ne $hookHash) { throw "Bad host block was modified or accepted: $badConfig" }
    }
    [System.IO.File]::WriteAllBytes($autoexec, [byte[]]@(0xFF, 0xFE, 0x00, 0xD8))
    $badHash = (Get-FileHash -LiteralPath $autoexec).Hash
    $refused = $false
    try { & (Join-Path $PSScriptRoot 'Install-PersistenceHook.ps1') -SavedGamesPath $fixtureRoot -ConfigureHost }
    catch { $refused = $true }
    if (-not $refused -or (Get-FileHash -LiteralPath $autoexec).Hash -ne $badHash) { throw 'Invalid encoding was modified or accepted' }
    Write-Host 'PASS: malformed, duplicate or invalid-encoding host configuration rejected without changes'
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
