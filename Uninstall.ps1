[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference = 'Stop'
$taskName = 'Logitech Stereo Guard 2'
if (-not $PSCmdlet.ShouldProcess($taskName, 'Stop and remove only the owned version 2 scheduled task')) { return }
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) { Write-Output 'Version 2 task is not installed.'; return }
$expected = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Watch-LogitechStereo.ps1') + '"'
if ($task.Description -ne 'LogitechStereoGuard2-owned-v2' -or @($task.Actions).Count -ne 1 -or $task.Actions[0].Arguments -ne $expected) {
    throw 'Ownership check failed. No task was changed. Run the uninstaller from its original installation folder.'
}
Stop-ScheduledTask -TaskName $taskName
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Write-Output 'Removed version 2 task. Legacy tasks, audio settings and local logs were preserved.'
