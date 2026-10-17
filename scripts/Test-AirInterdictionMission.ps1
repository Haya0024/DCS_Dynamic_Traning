[CmdletBinding()]
param([string]$LuaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path -Parent $PSScriptRoot
$archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz'))
try {
    $reader = [System.IO.StreamReader]::new($archive.GetEntry('mission').Open())
    try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$checks = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Test-AirInterdictionMission.lua'))
Push-Location -LiteralPath $projectRoot
try {
    ($source + "`n" + $checks) | & $LuaPath -
    if ($LASTEXITCODE -ne 0) { throw 'Actual mission Air Interdiction validation failed.' }
} finally { Pop-Location }
