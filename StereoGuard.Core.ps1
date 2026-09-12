function Get-GuardDecision {
    param([int]$MatchCount, [bool]$IsOff, [datetime]$Now = [datetime]::UtcNow,
        [datetime]$LastAttempt = [datetime]::MinValue, [bool]$SettingsOpen = $false)
    if ($MatchCount -eq 0) { return 'Absent' }
    if ($MatchCount -ne 1) { return 'Ambiguous' }
    if ($IsOff) { return 'Off' }
    if ($SettingsOpen) { return 'SettingsBusy' }
    if (($Now - $LastAttempt).TotalSeconds -lt 300) { return 'Cooldown' }
    return 'Correct'
}

function Get-LogitechEndpointState {
    param([string]$DeviceNamePattern = 'Logitech PRO X Wireless Gaming Headset')
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $nameKey = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
    $fxKey = '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5'
    foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
        $state = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
        if ($state.DeviceState -ne 1) { continue }
        $properties = Get-ItemProperty -LiteralPath (Join-Path $key.PSPath 'Properties') -ErrorAction SilentlyContinue
        if (-not $properties) { continue }
        $name = $properties.PSObject.Properties[$nameKey]
        if (-not $name -or $name.Value -notmatch $DeviceNamePattern) { continue }
        $fx = Get-ItemProperty -LiteralPath (Join-Path $key.PSPath 'FxProperties') -ErrorAction SilentlyContinue
        $value = if ($fx) { $fx.PSObject.Properties[$fxKey] } else { $null }
        [pscustomobject]@{ IsOff = [bool]($value -and $value.Value -eq 1); Known = [bool]$value }
    }
}

function Write-GuardLog {
    param([Parameter(Mandatory)][ValidateSet('Started','Stopped','Off','Absent','Ambiguous','SettingsBusy','Cooldown','Correct','Corrected','CorrectionFailed','ObservationFailed','EventFallback','VerifyRequired','CleanupFailed')][string]$Code,
        [int]$ErrorCode = 0)
    $directory = Join-Path $env:LOCALAPPDATA 'LogitechStereoGuard2'
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $path = Join-Path $directory 'guard.log'
    if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 1MB) {
        Move-Item -LiteralPath $path -Destination (Join-Path $directory 'guard.previous.log') -Force
    }
    ('{0:o} {1} code={2}' -f [datetime]::UtcNow, $Code, $ErrorCode) | Add-Content -LiteralPath $path -Encoding UTF8
}
function Invoke-GuardSettingsSession {
    param([scriptblock]$IsOpen, [scriptblock]$Launch, [scriptblock]$Correct,
        [scriptblock]$Close, [switch]$KeepWindow)
    # This guard is intentionally immediately adjacent to launch, after all waits.
    if (& $IsOpen) { throw 'Settings is already open. Correction deferred.' }
    $lease = $null
    try {
        $lease = & $Launch
        & $Correct $lease
    }
    finally {
        if ($lease -and $lease.Owned -and -not $KeepWindow) {
            try { & $Close $lease } catch { Write-GuardLog CleanupFailed -ErrorCode $_.Exception.HResult }
        }
    }
}
