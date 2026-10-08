[CmdletBinding()]
param([string]$LuaPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuaPath) { $LuaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe' }
$archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot 'mission/Persistent_and_Dynamic_FA-18C_Training.miz'))
try {
    $reader = [System.IO.StreamReader]::new($archive.GetEntry('mission').Open())
    try { $missionSource = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$checks = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Test-ZoneCoverage.lua'))
Push-Location -LiteralPath $projectRoot
try {
    ($missionSource + "`n" + $checks) | & $LuaPath -
    if ($LASTEXITCODE -ne 0) { throw 'Actual mission zone coverage validation failed.' }
} finally { Pop-Location }
