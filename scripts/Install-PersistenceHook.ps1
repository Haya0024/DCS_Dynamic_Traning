[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$SavedGamesPath, [switch]$ConfigureHost)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedRoot = (Resolve-Path -LiteralPath $SavedGamesPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot 'Config') -PathType Container)) {
    throw 'Specify the DCS user directory containing Config (for example Saved Games/DCS).'
}
# Prepare and validate the host change before writing either configuration or hook.
$hostConfig = Join-Path $resolvedRoot 'Config/autoexec.cfg'
$oldHostText = ''
$hostEncoding = [System.Text.UTF8Encoding]::new($false, $true)
if ($ConfigureHost) {
    if (Test-Path -LiteralPath $hostConfig) {
        $hostBytes = [System.IO.File]::ReadAllBytes($hostConfig)
        $oldHostText = $hostEncoding.GetString($hostBytes)
        if ($oldHostText.Length -gt 0 -and $oldHostText[0] -eq [char]0xFEFF) {
            $oldHostText = $oldHostText.Substring(1)
            $hostEncoding = [System.Text.UTF8Encoding]::new($true, $true)
        }
    }
    $beginMarker = '-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST'
    $endMarker = '-- END DYNAMIC TRAINING PERSISTENCE HOST'
    $beginCount = [regex]::Matches($oldHostText, [regex]::Escape($beginMarker)).Count
    $endCount = [regex]::Matches($oldHostText, [regex]::Escape($endMarker)).Count
    if ($beginCount -gt 1 -or $endCount -gt 1 -or $beginCount -ne $endCount) {
        throw 'Incomplete or duplicate persistence host block; autoexec.cfg and hook are unchanged.'
    }
    $newline = if ($oldHostText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = @'
-- BEGIN DYNAMIC TRAINING PERSISTENCE HOST
-- Host hook -> mission manager -> SSE; no mission filesystem unsanitize.
do
    if not net then net = {} end
    local function allow(key, name)
        if net[key] == nil then net[key] = {} end
        assert(type(net[key]) == "table", "Dynamic Training: invalid net permission list")
        for _, existing in ipairs(net[key]) do if existing == name then return end end
        net[key][#net[key] + 1] = name
    end
    allow("allow_unsafe_api", "userhooks")
    allow("allow_dostring_in", "server")
    allow("allow_dostring_in", "mission") -- Keep the previous server permission when upgrading.
end
-- END DYNAMIC TRAINING PERSISTENCE HOST
'@
    $block = $block.Replace("`r`n", "`n").TrimEnd("`r", "`n").Replace("`n", $newline) + $newline
    if ($beginCount -eq 1) {
        $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '\r?\n.*?^' + [regex]::Escape($endMarker) + '(?:\r?\n|\z)'
        $match = [regex]::Match($oldHostText, $pattern)
        if (-not $match.Success) { throw 'Malformed persistence host block; autoexec.cfg and hook are unchanged.' }
        $newHostText = $oldHostText.Substring(0, $match.Index) + $block + $oldHostText.Substring($match.Index + $match.Length)
    } else {
        $separator = if ($oldHostText -eq '' -or $oldHostText.EndsWith("`n")) { '' } else { $newline }
        $newHostText = $oldHostText + $separator + $block
    }
}
& (Join-Path $PSScriptRoot 'Build-PersistenceHook.ps1')
$hookDirectory = Join-Path $resolvedRoot 'Scripts/Hooks'
New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null
$destination = Join-Path $hookDirectory 'DynamicTrainingPersistenceHook.lua'
$source = Join-Path $projectRoot 'build/DynamicTrainingPersistenceHook.lua'
if ((Test-Path -LiteralPath $destination) -and
    (Get-FileHash -LiteralPath $destination).Hash -eq (Get-FileHash -LiteralPath $source).Hash) {
    Write-Host 'Persistence hook already current.'
} else {
    if (Test-Path -LiteralPath $destination) {
        $backup = $destination + '.' + [guid]::NewGuid().ToString('N') + '.bak'
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    Copy-Item -LiteralPath $source -Destination $destination
    Write-Host "Installed: $destination"
}
if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
    throw 'Installed hook verification failed.'
}
if ($ConfigureHost) {
    if ($oldHostText -cne $newHostText) {
        if (Test-Path -LiteralPath $hostConfig) {
            Copy-Item -LiteralPath $hostConfig -Destination ($hostConfig + '.' + [guid]::NewGuid().ToString('N') + '.bak')
        }
        [System.IO.File]::WriteAllText($hostConfig, $newHostText, $hostEncoding)
        if ([System.IO.File]::ReadAllText($hostConfig) -cne $newHostText) { throw 'Host configuration verification failed.' }
        Write-Host 'Configured host API permissions: userhooks -> mission (previous server permission retained). Existing settings preserved.'
    } else { Write-Host 'Persistence host configuration already current.' }
}
Write-Host 'Restart DCS to load the hook. MissionScripting.lua is unchanged.'
