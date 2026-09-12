[CmdletBinding(SupportsShouldProcess)]
param([ValidateRange(0,300)][int]$DelaySeconds = 25)
$ErrorActionPreference = 'Stop'
$taskName = 'Logitech Stereo Guard 2'
$targetScript = Join-Path $PSScriptRoot 'Watch-LogitechStereo.ps1'
if (-not (Test-Path -LiteralPath $targetScript)) { throw 'Guard script is missing.' }
if ($targetScript.Contains('"')) { throw 'Unsupported installation path.' }
if (-not $PSCmdlet.ShouldProcess($taskName, 'Create a new isolated logon task (existing tasks are never overwritten)')) { return }
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'Task already exists. Uninstall this version first.' }
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $targetScript + '"'
$action = New-ScheduledTaskAction -Execute $exe -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$trigger.Delay = 'PT' + $DelaySeconds + 'S'
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([timespan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'LogitechStereoGuard2-owned-v2' | Out-Null
Write-Output 'Installed Logitech Stereo Guard 2. Starts at next sign-in. Keep this folder in place.'
