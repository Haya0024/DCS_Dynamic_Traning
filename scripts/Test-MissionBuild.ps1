# Verify module bundling/watch in an isolated project, never editing real sources.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dcs-module-build-' + [guid]::NewGuid().ToString('N'))
$job = $null
try {
    foreach ($directory in @('scripts', 'src', 'vendor/MOOSE', 'mission')) {
        New-Item -ItemType Directory -Path (Join-Path $testRoot $directory) -Force | Out-Null
    }
    foreach ($script in @('Sync-Mission.ps1', 'Build-Mission.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $testRoot "scripts/$script")
    }
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.lua' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $testRoot 'src') }
    [System.IO.File]::WriteAllText((Join-Path $testRoot 'vendor/MOOSE/Moose.lua'), '-- mock MOOSE')
    $missionPath = Join-Path $testRoot 'mission/Syria.miz'
    $archive = [System.IO.Compression.ZipFile]::Open($missionPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @('mission', 'l10n/DEFAULT/DynamicTraining.lua', 'l10n/DEFAULT/Moose.lua')) {
            $writer = [System.IO.StreamWriter]::new($archive.CreateEntry($name).Open())
            try { $writer.Write('fixture') } finally { $writer.Dispose() }
        }
    } finally { $archive.Dispose() }
    $build = Join-Path $testRoot 'scripts/Build-Mission.ps1'
    $sync = Join-Path $testRoot 'scripts/Sync-Mission.ps1'
    & $build
    $bundlePath = Join-Path $testRoot 'build/DynamicTraining.lua'
    $bundleHash = (Get-FileHash -LiteralPath $bundlePath).Hash
    & $build
    if ((Get-FileHash -LiteralPath $bundlePath).Hash -ne $bundleHash) { throw 'Build is not deterministic.' }
    & $sync
    & $sync -Check
    Write-Host 'PASS: deterministic bundle and initial embedded module sync'

    $job = Start-Job -ScriptBlock { param($Script); & $Script -Watch -IntervalSeconds 1 } -ArgumentList $sync
    $ready = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        if ((Receive-Job -Job $job -Keep 6>&1 | Out-String) -like '*Watching Lua sources*') { $ready = $true; break }
        if ($job.State -eq 'Failed') { throw 'Module watcher failed to start.' }
    }
    if (-not $ready) { throw 'Module watcher did not become ready.' }
    $configPath = Join-Path $testRoot 'src/config.lua'
    $configText = [System.IO.File]::ReadAllText($configPath).Replace('fullReward = 150', 'fullReward = 175')
    [System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
    $updated = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        try {
            & $sync -Check
            $archive = [System.IO.Compression.ZipFile]::OpenRead($missionPath)
            try {
                $reader = [System.IO.StreamReader]::new($archive.GetEntry('l10n/DEFAULT/DynamicTraining.lua').Open())
                try { $updated = $reader.ReadToEnd().Contains('fullReward = 175') } finally { $reader.Dispose() }
            } finally { $archive.Dispose() }
            if ($updated) { break }
        } catch { }
    }
    if (-not $updated) { throw 'Module edit did not update embedded bundle.' }
    Write-Host 'PASS: config module edits rebuild and sync through watch'
} finally {
    if ($null -ne $job) { Stop-Job -Job $job; Remove-Job -Job $job }
    # Resolve and verify the exact disposable directory before recursive cleanup.
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedTestRoot) -notmatch '^dcs-module-build-[0-9a-f]{32}$') {
        throw 'Refusing cleanup outside the expected disposable project directory.'
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
