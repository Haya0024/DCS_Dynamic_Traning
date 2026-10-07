[CmdletBinding()]
param(
    [string]$MissionPath,
    [switch]$Check,
    [switch]$Watch,
    [ValidateRange(1, 60)]
    [int]$IntervalSeconds = 2
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MissionPath) {
    $MissionPath = Join-Path $projectRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz'
}
$MissionPath = [System.IO.Path]::GetFullPath($MissionPath)
if ($Check -and $Watch) {
    throw '-Check and -Watch cannot be used together.'
}

# Bundle modules into the already registered entry; no ME triggers are added.
$scripts = @(
    @{ Source = (Join-Path $projectRoot 'build/DynamicTraining.lua'); Entry = 'l10n/DEFAULT/DynamicTraining.lua' },
    @{ Source = (Join-Path $projectRoot 'vendor/MOOSE/Moose.lua'); Entry = 'l10n/DEFAULT/Moose.lua' }
)

function Get-StreamHash {
    param([System.IO.Stream]$Stream)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Get-ArchiveHashes {
    param([System.IO.Compression.ZipArchive]$Archive)
    $hashes = @{}
    foreach ($entry in $Archive.Entries) {
        if ($hashes.ContainsKey($entry.FullName)) {
            throw "Duplicate ZIP entry: $($entry.FullName)"
        }
        $stream = $entry.Open()
        try {
            $hashes[$entry.FullName] = Get-StreamHash $stream
        } finally {
            $stream.Dispose()
        }
    }
    return $hashes
}

function Sync-Mission {
    & (Join-Path $PSScriptRoot 'Build-Mission.ps1')
    $sourceHashes = @{}
    foreach ($script in $scripts) {
        $sourceHashes[$script.Entry] = (Get-FileHash -LiteralPath $script.Source -Algorithm SHA256).Hash
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($MissionPath)
    try {
        $before = Get-ArchiveHashes $archive
        foreach ($script in $scripts) {
            if (-not $before.ContainsKey($script.Entry)) {
                throw "Missing embedded script: $($script.Entry). Register it in Mission Editor first."
            }
        }
    } finally {
        $archive.Dispose()
    }
    $changed = @($scripts | Where-Object { $before[$_.Entry] -ne $sourceHashes[$_.Entry] })
    if ($changed.Count -eq 0) {
        Write-Host 'Mission scripts are in sync.'
        return
    }
    if ($Check) {
        throw ('Mission scripts are out of sync: ' + (($changed | ForEach-Object { $_.Entry }) -join ', '))
    }

    # Work on a sibling copy, verify every entry, then replace atomically.
    # mission, warehouses, options, triggers and resource mappings stay intact.
    $temporaryPath = $MissionPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Copy-Item -LiteralPath $MissionPath -Destination $temporaryPath
        $archive = [System.IO.Compression.ZipFile]::Open($temporaryPath, [System.IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($script in $changed) {
                $entry = $archive.GetEntry($script.Entry)
                $entryTime = $entry.LastWriteTime
                $entry.Delete()
                $newEntry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, $script.Source, $script.Entry, [System.IO.Compression.CompressionLevel]::Optimal
                )
                $newEntry.LastWriteTime = $entryTime
            }
        } finally {
            $archive.Dispose()
        }

        $archive = [System.IO.Compression.ZipFile]::OpenRead($temporaryPath)
        try {
            $after = Get-ArchiveHashes $archive
        } finally {
            $archive.Dispose()
        }
        if ($before.Count -ne $after.Count) {
            throw 'ZIP entry count changed; original mission was not replaced.'
        }
        foreach ($name in $before.Keys) {
            $expected = $before[$name]
            if ($sourceHashes.ContainsKey($name)) {
                $expected = $sourceHashes[$name]
            }
            if (-not $after.ContainsKey($name) -or $after[$name] -ne $expected) {
                throw "Verification failed: $name. Original mission was not replaced."
            }
        }

        # Reject concurrent ME saves or another sync before overwriting the file.
        $archive = [System.IO.Compression.ZipFile]::OpenRead($MissionPath)
        try {
            $current = Get-ArchiveHashes $archive
        } finally {
            $archive.Dispose()
        }
        if ($current.Count -ne $before.Count) {
            throw 'Mission changed during sync. Retry after saving in ME.'
        }
        foreach ($name in $before.Keys) {
            if (-not $current.ContainsKey($name) -or $current[$name] -ne $before[$name]) {
                throw 'Mission changed during sync. Retry after saving in ME.'
            }
        }
        [System.IO.File]::Replace($temporaryPath, $MissionPath, ($MissionPath + '.bak'))
        Write-Host ('Updated: ' + (($changed | ForEach-Object { $_.Entry }) -join ', '))
        Write-Host "Backup: $MissionPath.bak"
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath
        }
    }
}

function Get-WatchStamp {
    $paths = @($MissionPath) + @($scripts | ForEach-Object { $_.Source }) +
        @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.lua' -File | ForEach-Object { $_.FullName }) +
        @(Join-Path $PSScriptRoot 'Build-Mission.ps1')
    return (($paths | ForEach-Object {
        $file = Get-Item -LiteralPath $_
        '{0}:{1}:{2}' -f $file.FullName, $file.LastWriteTimeUtc.Ticks, $file.Length
    }) -join '|')
}

Sync-Mission
if ($Watch) {
    Write-Host 'Watching Lua sources and mission file. Press Ctrl+C to stop.'
    $lastStamp = Get-WatchStamp
    while ($true) {
        Start-Sleep -Seconds $IntervalSeconds
        try {
            $stamp = Get-WatchStamp
            if ($stamp -ne $lastStamp) {
                Sync-Mission
                # Retain the pre-sync stamp so edits made during sync are seen
                # again on the next poll rather than silently skipped.
                $lastStamp = $stamp
            }
        } catch {
            Write-Warning $_.Exception.Message
            # A busy file or an editor's temporary rename is retried next poll.
        }
    }
}
