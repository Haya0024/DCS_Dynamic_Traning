[CmdletBinding()]
param([string]$LuaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path -Parent $PSScriptRoot
$archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz'))
try {
    $sources = @()
    foreach ($entry in @('mission', 'warehouses')) {
        $reader = [System.IO.StreamReader]::new($archive.GetEntry($entry).Open())
        try { $sources += $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
} finally { $archive.Dispose() }
$checks = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Test-StrikeMission.lua'))
Push-Location -LiteralPath $projectRoot
try {
    ($sources[0] + "`n" + $sources[1] + "`n" + $checks) | & $LuaPath -
    if ($LASTEXITCODE -ne 0) { throw 'Actual mission Strike validation failed.' }
} finally { Pop-Location }
