param(
    [string]$DeviceNamePattern = 'Logitech PRO X Wireless Gaming Headset',
    [ValidateRange(30,3600)][int]$FallbackSeconds = 60,
    [switch]$VerifyOnly,
    [switch]$Once
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StereoGuard.Core.ps1')
# Validate expressions before subscribing; no device labels are logged.
try { [void][regex]::new($DeviceNamePattern) } catch { Write-Error 'Invalid device-name regular expression.'; exit 1 }
$mutex = New-Object System.Threading.Mutex($false, 'Local\LogitechStereoGuard2')
$owned = $false
$subscription = $null
$source = 'LogitechStereoGuard2.DeviceChange'
$lastAttempt = [datetime]::MinValue
$lastCode = ''
try {
    try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { Write-Output 'Another guard instance is already running.'; exit 2 }
    Write-GuardLog Started
    if (-not $Once) {
        try { $subscription = Register-WmiEvent -Class Win32_DeviceChangeEvent -SourceIdentifier $source -ErrorAction Stop }
        catch { Write-GuardLog EventFallback -ErrorCode $_.Exception.HResult }
    }
    do {
        try {
            $matches = @(Get-LogitechEndpointState -DeviceNamePattern $DeviceNamePattern)
            $isOff = $matches.Count -eq 1 -and $matches[0].IsOff
            $code = Get-GuardDecision -MatchCount $matches.Count -IsOff $isOff -LastAttempt $lastAttempt -SettingsOpen ([bool](Get-Process SystemSettings -ErrorAction SilentlyContinue))
            if ($VerifyOnly -and $code -eq 'Correct') { $code = 'VerifyRequired' }
            if ($code -ne $lastCode) { Write-GuardLog $code; $lastCode = $code; Write-Output $code }
            if ($code -eq 'Correct') {
                $lastAttempt = [datetime]::UtcNow
                $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
                & $exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Set-LogitechAudioEnhancementsOff.ps1') -GHubWaitSeconds 0 -EndpointWaitSeconds 10 -DeviceNamePattern $DeviceNamePattern
                if ($LASTEXITCODE -eq 0) { Write-GuardLog Corrected } else { Write-GuardLog CorrectionFailed -ErrorCode $LASTEXITCODE }
            }
            if ($Once -and $VerifyOnly -and -not $isOff) { exit 3 }
        }
        catch { Write-GuardLog ObservationFailed -ErrorCode $_.Exception.HResult; if ($Once) { exit 1 } }
        if (-not $Once) {
            if ($subscription) {
                $event = Wait-Event -SourceIdentifier $source -Timeout $FallbackSeconds
                if ($event) {
                    # Let driver enumeration settle and coalesce a burst of notifications.
                    Start-Sleep -Seconds 3
                    Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event
                }
            } else { Start-Sleep -Seconds $FallbackSeconds }
        }
    } while (-not $Once)
}
finally {
    if ($subscription) {
        Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event
        Remove-Job -Job $subscription -Force -ErrorAction SilentlyContinue
    }
    if ($owned) { $mutex.ReleaseMutex(); Write-GuardLog Stopped }
    $mutex.Dispose()
}
