[CmdletBinding()]
param([string]$LuaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path -Parent $PSScriptRoot
$archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot 'mission/persistant_and_dynamic_traning.miz'))
try {
    $source = ''
    foreach ($entryName in @('mission', 'warehouses')) {
        $reader = [System.IO.StreamReader]::new($archive.GetEntry($entryName).Open())
        try { $source += $reader.ReadToEnd() + "`n" } finally { $reader.Dispose() }
    }
} finally { $archive.Dispose() }
$checks = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Test-CASMission.lua'))
Push-Location -LiteralPath $projectRoot
try {
    ($source + "`n" + $checks) | & $LuaPath -
    if ($LASTEXITCODE -ne 0) { throw 'Saved mission CAS validation failed.' }
} finally { Pop-Location }
