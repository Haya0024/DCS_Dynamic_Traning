[CmdletBinding()]
param([string]$DCSPath='C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/DCS.exe',
    [switch]$Status,[switch]$Stop)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$runPath=Join-Path $projectRoot 'build/cas-autolase-run.json'
if ($Status -or $Stop) {
    $run=Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json
    $expectedProfile=Join-Path (Join-Path $env:USERPROFILE 'Saved Games') $run.profileName
    if ($run.profileName -notmatch '^DCS\.CASAutolaseCheck-[0-9a-f]{12}$' -or
        $run.profilePath -ne $expectedProfile -or
        $run.logPath -ne (Join-Path $expectedProfile 'Logs/dcs.log') -or
        $run.executablePath -ne [IO.Path]::GetFullPath($DCSPath)) {
        throw 'Diagnostic run metadata is outside the expected profile/executable scope.'
    }
    if ($Stop) {
        foreach ($process in Get-CimInstance Win32_Process -Filter "Name = 'DCS.exe' OR Name = 'DCS_server.exe'") {
            if ($process.ExecutablePath -eq $run.executablePath -and
                $process.CommandLine -match ('(?:-w|--writedir)\s+"?'+[regex]::Escape($run.profileName)+'(?:"|\s|$)')) {
                Stop-Process -Id $process.ProcessId
                Write-Output "Stopped diagnostic DCS only: $($process.ProcessId)"
            }
        }
    }
    if (Test-Path -LiteralPath $run.logPath) {
        Select-String -LiteralPath $run.logPath -Pattern 'CASAutolaseCheck|CAS AUTOLASE|Mission script error|ERROR.*SCRIPTING' | Select-Object -Last 20
    } else { Write-Output 'Diagnostic log not created yet.' }
    exit
}
$missionPath=Join-Path $projectRoot 'build/CAS_Autolase_Check.miz'
if (-not (Test-Path -LiteralPath $missionPath -PathType Leaf)) { throw 'Build the diagnostic mission first.' }
if (Get-Process -Name DCS,DCS_server -ErrorAction SilentlyContinue) { throw 'DCS already running; refusing to interrupt it.' }
if (-not (Test-Path -LiteralPath $DCSPath -PathType Leaf)) { throw 'DCS executable not found.' }
$profileName='DCS.CASAutolaseCheck-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$profilePath=Join-Path (Join-Path $env:USERPROFILE 'Saved Games') $profileName
if (Test-Path -LiteralPath $profilePath) { throw 'Refusing to reuse an existing profile.' }
foreach ($directory in @('Config','Logs','Tracks','Missions')) {
    New-Item -ItemType Directory -Path (Join-Path $profilePath $directory) -Force | Out-Null
}
[IO.File]::WriteAllText((Join-Path $profilePath 'CASAutolaseCheck-profile.txt'),
    'Isolated CAS diagnostic. No normal Config, Hook, or scores copied.')
$dcsRoot=Split-Path -Parent (Split-Path -Parent $DCSPath)
$steamRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dcsRoot))
$arguments=@('-silent','-applaunch','223750','--norender','--nopause','-w',$profileName,
    '--mission-file',('"'+$missionPath+'"'))
$run=[ordered]@{profileName=$profileName;profilePath=$profilePath;logPath=(Join-Path $profilePath 'Logs/dcs.log');
    missionPath=$missionPath;executablePath=[IO.Path]::GetFullPath($DCSPath);startedAtUtc=[DateTime]::UtcNow.ToString('o')}
$run | ConvertTo-Json | Set-Content -LiteralPath $runPath -Encoding UTF8
Start-Process -FilePath (Join-Path $steamRoot 'steam.exe') -ArgumentList $arguments -WorkingDirectory $steamRoot -WindowStyle Hidden
$run | ConvertTo-Json
