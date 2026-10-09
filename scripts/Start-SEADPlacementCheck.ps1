[CmdletBinding()]
param([string]$DCSPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/DCS.exe',
    [switch]$ThroughSteam, [switch]$Status, [switch]$Stop, [switch]$SinglePlayer,
    [switch]$RestartSteam)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Status -or $Stop) {
    $runPath = Join-Path $projectRoot 'build/sead-placement-run.json'
    Write-Output "Run metadata present: $(Test-Path -LiteralPath $runPath)"
    Get-Process DCS,DCS_server,steam -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path | ConvertTo-Json -Compress | Write-Output
    $run = if (Test-Path -LiteralPath $runPath) { Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json } else { $null }
    foreach ($process in Get-CimInstance Win32_Process -Filter "Name = 'DCS.exe' OR Name = 'DCS_server.exe'") {
        $profile = if ($process.CommandLine -match '(?:-w|--writedir)\s+([^\s]+)') { $Matches[1].Trim('"') } else { 'DCS' }
        if ($Stop -and $run -and $profile -eq [System.IO.Path]::GetFileName($run.profilePath) -and $process.ExecutablePath -eq $run.executablePath) {
            Stop-Process -Id $process.ProcessId
            Write-Output "Stopped only diagnostic DCS process $($process.ProcessId)."
        }
        [pscustomobject]@{ processId = $process.ProcessId; profile = $profile;
            diagnostic = [bool]($run -and $profile -eq [System.IO.Path]::GetFileName($run.profilePath)) } | ConvertTo-Json -Compress | Write-Output
    }
    if ($run) {
        Write-Output "Diagnostic log present: $(Test-Path -LiteralPath $run.logPath)"
        if (Test-Path -LiteralPath $run.logPath) { Get-Content -LiteralPath $run.logPath -Tail 28 }
    }
    exit
}
$missionPath = Join-Path $projectRoot 'build/SEAD_Placement_Check.miz'
if (-not (Test-Path -LiteralPath $missionPath -PathType Leaf)) { throw 'Build the placement-only mission first.' }
if (-not (Test-Path -LiteralPath $DCSPath -PathType Leaf)) { throw 'DCS executable not found.' }
$runningDCS = @(Get-Process DCS,DCS_server -ErrorAction SilentlyContinue | Where-Object { $_.Id -and $_.ProcessName -in @('DCS', 'DCS_server') })
if ($runningDCS.Count -gt 0) { throw ('DCS is already running; refusing to interrupt it. IDs: ' + (($runningDCS | ForEach-Object Id) -join ', ')) }
$profileName = 'DCS.SEADPlacementCheck-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$profilePath = Join-Path (Join-Path $env:USERPROFILE 'Saved Games') $profileName
if (Test-Path -LiteralPath $profilePath) { throw 'Refusing to reuse an existing DCS profile.' }
foreach ($directory in @('Config', 'Logs', 'Tracks', 'Missions')) {
    New-Item -ItemType Directory -Path (Join-Path $profilePath $directory) -Force | Out-Null
}
$luaMission = $missionPath.Replace('\', '/')
$settings = @"
cfg = {
    name = 'SEAD placement diagnostic', description = 'Private placement-only check',
    isPublic = false, bind_address = '127.0.0.1', port = '10329', maxPlayers = 1,
    password = '', listStartIndex = 1, listLoop = false, listShuffle = false,
    missionList = { [1] = '$luaMission' }, lastSelectedMission = '$luaMission',
    advanced = { pause_on_load = false, pause_without_clients = false,
        voice_chat_server = false, allow_ownship_export = false, allow_object_export = false }
}
"@
[System.IO.File]::WriteAllText((Join-Path $profilePath 'Config/serverSettings.lua'), $settings, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $profilePath 'SEADPlacementCheck-profile.txt'), 'Isolated profile created for a placement diagnostic; no persistence hook installed.')
$dcsRoot = Split-Path -Parent (Split-Path -Parent $DCSPath)
$arguments = @('--server', '--norender', '--nopause', '-w', $profileName)
if ($SinglePlayer) { $arguments = @('--norender', '--nopause', '-w', $profileName, '--mission-file', ('"' + $missionPath + '"')) }
if ($ThroughSteam) {
    $steamRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dcsRoot))
    $steamPath = Join-Path $steamRoot 'steam.exe'
    if (-not (Test-Path -LiteralPath $steamPath)) { throw 'Steam launcher not found for this DCS installation.' }
    if ($RestartSteam) {
        # Use Steam's normal shutdown request; do not dismiss confirmation dialogs.
        Start-Process -FilePath $steamPath -WorkingDirectory $steamRoot -ArgumentList '-shutdown' -WindowStyle Hidden -Wait
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while ((Get-Process steam -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 1 }
        if (Get-Process steam -ErrorAction SilentlyContinue) { throw 'Steam did not exit normally; no forced termination or confirmation bypass.' }
    }
    $process = Start-Process -FilePath $steamPath -WorkingDirectory $steamRoot -ArgumentList (@('-silent', '-applaunch', '223750') + $arguments) -WindowStyle Hidden -PassThru
} else {
    $process = Start-Process -FilePath $DCSPath -WorkingDirectory $dcsRoot -ArgumentList $arguments -WindowStyle Hidden -PassThru
}
$run = [ordered]@{ processId = $process.Id; profilePath = $profilePath;
    logPath = (Join-Path $profilePath 'Logs/dcs.log'); missionPath = $missionPath;
    executablePath = [System.IO.Path]::GetFullPath($DCSPath); throughSteam = [bool]$ThroughSteam;
    startedAtUtc = [DateTime]::UtcNow.ToString('o') }
$run | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'build/sead-placement-run.json') -Encoding UTF8
$run | ConvertTo-Json
