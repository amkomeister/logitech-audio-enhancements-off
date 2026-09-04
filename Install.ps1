param(
    [string]$TaskName = 'Keep Logitech Audio Enhancements Off',
    [int]$DelaySeconds = 25
)

$ErrorActionPreference = 'Stop'
$targetScript = Join-Path $PSScriptRoot 'Set-LogitechAudioEnhancementsOff.ps1'

if (-not (Test-Path -LiteralPath $targetScript)) {
    throw "Set-LogitechAudioEnhancementsOff.ps1 was not found beside Install.ps1."
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powerShellExe = Join-Path $PSHOME 'powershell.exe'
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
    $targetScript + '"'

$action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$trigger.Delay = 'PT' + $DelaySeconds + 'S'
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$registerParameters = @{
    TaskName = $TaskName
    Action = $action
    Trigger = $trigger
    Principal = $principal
    Settings = $settings
    Description = 'Turns off Windows audio enhancements for a Logitech PRO X Wireless headset after sign-in.'
    Force = $true
}
Register-ScheduledTask @registerParameters | Out-Null

Write-Host "Installed scheduled task: $TaskName"
Write-Host "It will run $DelaySeconds seconds after sign-in."
Write-Host 'Keep this folder in its current location while the task is installed.'
