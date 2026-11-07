[CmdletBinding()]
param([ValidatePattern('^[a-z0-9_]*$')][string]$Suffix='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$projectRoot=Split-Path -Parent $PSScriptRoot
$verification=Get-Content -LiteralPath (Join-Path $projectRoot 'build/cas-autolase-verification.json') -Raw | ConvertFrom-Json
& (Join-Path $PSScriptRoot 'Sync-Mission.ps1') -Check
$mission=Join-Path $projectRoot 'mission/persistant_and_dynamic_traning.miz'
$bundle=Join-Path $projectRoot 'build/DynamicTraining.lua'
if ($verification.runtime -ne 'training-18.1' -or $verification.luaCases -ne 624 -or
    $verification.nativeStandbyChecks -ne 3 -or $verification.nativePauseChecks -ne 3 -or
    $verification.nativeSpotChecks -ne 3 -or $verification.nativeCleanupChecks -ne 3 -or
    (Get-FileHash -LiteralPath $mission).Hash -ne $verification.missionSHA256 -or
    (Get-FileHash -LiteralPath $bundle).Hash -ne $verification.bundleSHA256) {
    throw 'Verification does not match the current training-18.1 mission/bundle. Revalidate before packaging.'
}
$edition = if ($Suffix) { '_' + $Suffix } else { '' }
$stage=Join-Path $projectRoot ('build/CAS_AUTOLASE_training18_1' + $edition)
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files=@(
    @{source=$mission;name='persistant_and_dynamic_traning.miz'},
    @{source=(Join-Path $projectRoot 'docs/CAS_AUTOLASE_INSTALL_JA.txt');name='INSTALL_AUTOLASE_JA.txt'},
    @{source=(Join-Path $projectRoot 'build/CAS_Autolase_Check_training18_1_20261107.log');name='DCS_CHECK.log'}
)
$manifest=[ordered]@{runtime=$verification.runtime;edition=$Suffix;hookUpdateRequired=$false;files=@()}
foreach ($file in $files) {
    $destination=Join-Path $stage $file.name
    Copy-Item -LiteralPath $file.source -Destination $destination -Force
    $manifest.files+=@{name=$file.name;sha256=(Get-FileHash -LiteralPath $destination).Hash}
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'MANIFEST.json') -Encoding UTF8
$output=Join-Path $projectRoot ('build/CAS_AUTOLASE_training18_1_20261107' + $edition + '.zip')
# This is a single fixed generated ZIP in build, never a directory deletion.
if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
$archive=[IO.Compression.ZipFile]::Open($output,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @('persistant_and_dynamic_traning.miz','INSTALL_AUTOLASE_JA.txt','DCS_CHECK.log','MANIFEST.json')) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $stage $name),$name) | Out-Null
    }
} finally { $archive.Dispose() }
$archive=[IO.Compression.ZipFile]::OpenRead($output)
try {
    if ($archive.Entries.Count -ne 4) { throw 'Unexpected package entry count.' }
    foreach ($file in $manifest.files) {
        $stream=$archive.GetEntry($file.name).Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try { $actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $sha.Dispose(); $stream.Dispose() }
        if ($actual -ne $file.sha256) { throw "Package verification failed: $($file.name)" }
    }
} finally { $archive.Dispose() }
Write-Output "Verified update package: $output"
