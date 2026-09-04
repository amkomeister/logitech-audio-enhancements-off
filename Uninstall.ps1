param(
    [string]$TaskName = 'Keep Logitech Audio Enhancements Off'
)

$ErrorActionPreference = 'Stop'
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task: $TaskName"
}
else {
    Write-Host "Scheduled task not found: $TaskName"
}

Write-Host 'No audio settings, drivers, or files were removed.'
