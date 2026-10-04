# Integration checks using disposable ZIP fixtures, without changing Lua sources.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$syncScript = Join-Path $PSScriptRoot 'Sync-Mission.ps1'
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('dcs-mission-sync-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$job = $null

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-Fixture {
    param([string]$Path, [switch]$Missing, [switch]$Duplicate)
    $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $names = @('mission', 'warehouses', 'options', 'l10n/DEFAULT/mapResource', 'l10n/DEFAULT/DynamicTraining.lua')
        if (-not $Missing) { $names += 'l10n/DEFAULT/Moose.lua' }
        if ($Duplicate) { $names += 'mission' }
        foreach ($name in $names) {
            $entry = $archive.CreateEntry($name)
            $entry.LastWriteTime = [DateTimeOffset]::new(2020, 6, 1, 8, 0, 0, [TimeSpan]::Zero)
            $stream = $entry.Open()
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("fixture content: $name")
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function Assert-Rejected {
    param([string]$Path, [string]$ExpectedMessage)
    $before = (Get-FileHash -LiteralPath $Path).Hash
    $rejected = $false
    try { & $syncScript -MissionPath $Path } catch {
        Assert ($_.Exception.Message -like "*$ExpectedMessage*") $_.Exception.Message
        $rejected = $true
    }
    Assert $rejected 'Invalid fixture was accepted.'
    Assert ((Get-FileHash -LiteralPath $Path).Hash -eq $before) 'Rejected mission was modified.'
    Assert (-not (Test-Path -LiteralPath ($Path + '.bak'))) 'Rejected mission created a backup.'
}

try {
    $path = Join-Path $testDirectory 'valid.miz'
    New-Fixture $path
    $originalHash = (Get-FileHash -LiteralPath $path).Hash
    $rejected = $false
    try { & $syncScript -MissionPath $path -Check } catch { $rejected = $true }
    Assert $rejected '-Check did not detect stale scripts.'
    Assert ((Get-FileHash -LiteralPath $path).Hash -eq $originalHash) '-Check modified the mission.'

    & $syncScript -MissionPath $path
    & $syncScript -MissionPath $path -Check
    Assert ((Get-FileHash -LiteralPath ($path + '.bak')).Hash -eq $originalHash) 'Backup does not match original ZIP.'
    $before = [System.IO.Compression.ZipFile]::OpenRead($path + '.bak')
    $after = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        Assert ($before.Entries.Count -eq $after.Entries.Count) 'Entry count changed.'
        foreach ($entry in $before.Entries) {
            $updated = $after.GetEntry($entry.FullName)
            Assert ($null -ne $updated) 'Entry disappeared.'
            Assert ($entry.LastWriteTime -eq $updated.LastWriteTime) 'Entry timestamp changed.'
            if ($entry.FullName -notlike '*.lua') {
                $oldReader = [System.IO.StreamReader]::new($entry.Open())
                $newReader = [System.IO.StreamReader]::new($updated.Open())
                try { Assert ($oldReader.ReadToEnd() -ceq $newReader.ReadToEnd()) 'Non-Lua content changed.' }
                finally { $oldReader.Dispose(); $newReader.Dispose() }
            }
        }
    } finally { $before.Dispose(); $after.Dispose() }
    $syncedHash = (Get-FileHash -LiteralPath $path).Hash
    & $syncScript -MissionPath $path
    Assert ((Get-FileHash -LiteralPath $path).Hash -eq $syncedHash) 'Repeated sync rewrote ZIP.'
    Assert ((Get-FileHash -LiteralPath ($path + '.bak')).Hash -eq $originalHash) 'Repeated sync overwrote backup.'
    Write-Host 'PASS: check, replacement, content preservation, timestamps, backup, idempotence'

    $missingPath = Join-Path $testDirectory 'missing.miz'
    New-Fixture $missingPath -Missing
    Assert-Rejected $missingPath 'Missing embedded script'
    $duplicatePath = Join-Path $testDirectory 'duplicate.miz'
    New-Fixture $duplicatePath -Duplicate
    Assert-Rejected $duplicatePath 'Duplicate ZIP entry'
    $corruptPath = Join-Path $testDirectory 'corrupt.miz'
    [System.IO.File]::WriteAllText($corruptPath, 'not a ZIP')
    Assert-Rejected $corruptPath 'central directory'
    Write-Host 'PASS: missing script, duplicate entry, corrupt ZIP leave originals intact'

    # Watch must also restore scripts after ME-like saves of an older mission.
    $job = Start-Job -ScriptBlock {
        param($Script, $Mission)
        & $Script -MissionPath $Mission -Watch -IntervalSeconds 1
    } -ArgumentList $syncScript, $path
    $ready = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $output = Receive-Job -Job $job -Keep 6>&1
        if (($output | Out-String) -like '*Watching Lua sources*') { $ready = $true; break }
        if ($job.State -eq 'Failed') { throw 'Watcher failed to start.' }
    }
    Assert $ready 'Watcher did not become ready.'
    Copy-Item -LiteralPath ($path + '.bak') -Destination $path -Force
    $restored = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        try { & $syncScript -MissionPath $path -Check; $restored = $true; break } catch { }
    }
    Assert $restored 'Watcher did not resync an externally saved mission.'
    Write-Host 'PASS: watch detects and resyncs an external mission save'
} finally {
    if ($null -ne $job) { Stop-Job -Job $job; Remove-Job -Job $job }
    # Only individual files in our newly created fixture directory are removed.
    Get-ChildItem -LiteralPath $testDirectory -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    Remove-Item -LiteralPath $testDirectory
}
