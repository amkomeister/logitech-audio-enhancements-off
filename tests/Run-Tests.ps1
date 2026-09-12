$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot '../StereoGuard.Core.ps1'
if (-not (Test-Path $core)) { throw 'FAIL: guard decision core has not been implemented' }
. $core
function Assert-Equal($Actual, $Expected, $Name) { if ($Actual -ne $Expected) { throw "FAIL: $Name (expected $Expected, got $Actual)" }; Write-Output "PASS: $Name" }
$now = [datetime]'2026-01-01T00:10:00Z'
Assert-Equal (Get-GuardDecision -MatchCount 0 -IsOff $false -Now $now) 'Absent' 'Disconnected device cannot trigger UI'
Assert-Equal (Get-GuardDecision -MatchCount 2 -IsOff $false -Now $now) 'Ambiguous' 'Ambiguous match cannot change another device'
Assert-Equal (Get-GuardDecision -MatchCount 1 -IsOff $true -Now $now) 'Off' 'Already Off does not open Settings'
Assert-Equal (Get-GuardDecision -MatchCount 1 -IsOff $false -Now $now -SettingsOpen $true) 'SettingsBusy' 'Existing Settings window is protected'
Assert-Equal (Get-GuardDecision -MatchCount 1 -IsOff $false -Now $now -LastAttempt $now.AddSeconds(-20)) 'Cooldown' 'Repeated events cannot cause UI storm'
Assert-Equal (Get-GuardDecision -MatchCount 1 -IsOff $false -Now $now -LastAttempt $now.AddSeconds(-301)) 'Correct' 'Reset is corrected after cooldown'
Assert-Equal (Get-GuardDecision -MatchCount 1 -IsOff $false -Now $now) 'Correct' 'First enabled endpoint is corrected'
$parseFailures = @()
Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter *.ps1 -Recurse | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    $parseFailures += $errors
}
Assert-Equal $parseFailures.Count 0 'All PowerShell files parse'
# WhatIf must return before touching the Task Scheduler boundary.
function Get-ScheduledTask { throw 'WhatIf attempted a task read/write' }
function Register-ScheduledTask { throw 'WhatIf attempted installation' }
function Unregister-ScheduledTask { throw 'WhatIf attempted removal' }
& (Join-Path $PSScriptRoot '../Install.ps1') -WhatIf
& (Join-Path $PSScriptRoot '../Uninstall.ps1') -WhatIf
Write-Output 'PASS: Install and uninstall WhatIf have no task side effects'
# Registry reads are the external boundary; endpoint filtering and interpretation stay real.
& {
    $cases = Get-Content (Join-Path $PSScriptRoot 'fixtures/endpoints.json') -Raw | ConvertFrom-Json
    function Get-ChildItem { [pscustomobject]@{ PSPath = 'SyntheticEndpoint' } }
    function Get-ItemProperty {
        param($LiteralPath)
        if ($LiteralPath -like '*FxProperties') {
            if ($null -eq $case.sysFx) { return [pscustomobject]@{} }
            return [pscustomobject]@{ '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' = $case.sysFx }
        }
        if ($LiteralPath -like '*Properties') { return [pscustomobject]@{ '{b3f8fa53-0004-438e-9003-51a46e139bfc},6' = $case.deviceName } }
        return [pscustomobject]@{ DeviceState = $case.deviceState }
    }
    foreach ($case in $cases) {
        $actual = @(Get-LogitechEndpointState)
        Assert-Equal $actual.Count $case.expectedCount $case.name
        if ($actual.Count) {
            Assert-Equal $actual[0].IsOff $case.expectedOff ($case.name + ' status')
            Assert-Equal $actual[0].Known $case.expectedKnown ($case.name + ' confidence')
        }
    }
}
# UI lifecycle is exercised with a fake process boundary, never actual Settings.
if (-not (Get-Command Invoke-GuardSettingsSession -ErrorAction SilentlyContinue)) { throw 'FAIL: ownership-aware Settings session is missing' }
& {
    $state = @{ Launches = 0; Corrections = 0; Closes = 0 }
    $launch = { $state.Launches++; [pscustomobject]@{ Owned = $true; Token = 'synthetic-owned-window' } }
    $correct = { param($lease) $state.Corrections++; throw 'Synthetic UI failure' }
    $close = { param($lease) if ($lease.Token -ne 'synthetic-owned-window') { throw 'Unowned close' }; $state.Closes++ }
    try { Invoke-GuardSettingsSession -IsOpen { $true } -Launch $launch -Correct $correct -Close $close } catch {}
    Assert-Equal $state.Launches 0 'Settings opened during endpoint wait is never navigated'
    try { Invoke-GuardSettingsSession -IsOpen { $false } -Launch $launch -Correct $correct -Close $close } catch {}
    Assert-Equal $state.Closes 1 'Failed correction closes the owned Settings session'
    try { Invoke-GuardSettingsSession -IsOpen { $false } -Launch $launch -Correct $correct -Close $close -KeepWindow } catch {}
    Assert-Equal $state.Closes 1 'KeepWindow retains Settings after failure'
    try { Invoke-GuardSettingsSession -IsOpen { $false } -Launch { [pscustomobject]@{ Owned = $false } } -Correct $correct -Close $close } catch {}
    Assert-Equal $state.Closes 1 'Unproven Settings ownership never permits cleanup'
}
& {
    $state = @{ Closed = 0; Corrected = 0 }
    Invoke-GuardSettingsSession -IsOpen { $false } -Launch { [pscustomobject]@{ Owned = $true } } -Correct { param($lease) $state.Corrected++ } -Close { param($lease) $state.Closed++ }
    Assert-Equal $state.Corrected 1 'Session executes the requested correction'
    Assert-Equal $state.Closed 1 'Successful correction also cleans up its session'
    $failed = $false
    try { Invoke-GuardSettingsSession -IsOpen { $false } -Launch { [pscustomobject]@{ Owned = $true } } -Correct { throw 'Synthetic failure' } -Close { param($lease) $state.Closed++ } } catch { $failed = $true }
    Assert-Equal $failed $true 'Cleanup does not hide correction failure'
}
