param(
    [string]$DeviceNamePattern = 'Logitech PRO X Wireless Gaming Headset',
    [string]$OffLabel,
    [int]$EndpointWaitSeconds = 120,
    [int]$GHubWaitSeconds = 120,
    [switch]$KeepWindow,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StereoGuard.Core.ps1')
$comboAutomationId = 'SystemSettings_Audio_Output_Enhance_Audio_ComboBox'
$renderRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$deviceNameProperty = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'

function Write-UiLog {
    param([string]$Message)
    # Never persist raw messages, device names, exception text or stack traces.
    if ($Message.StartsWith('ERROR')) { Write-GuardLog CorrectionFailed }
    elseif ($Message.StartsWith('SUCCESS')) { Write-GuardLog Corrected }
}

function Find-TargetEndpoint {
    $endpointMatches = @()

    foreach ($endpointKey in Get-ChildItem -LiteralPath $renderRegistryPath -ErrorAction Stop) {
        $endpoint = Get-ItemProperty -LiteralPath $endpointKey.PSPath -ErrorAction SilentlyContinue
        if (-not $endpoint -or $endpoint.DeviceState -ne 1) { continue }

        $propertiesPath = Join-Path $endpointKey.PSPath 'Properties'
        $properties = Get-ItemProperty -LiteralPath $propertiesPath -ErrorAction SilentlyContinue
        if (-not $properties) { continue }

        $deviceName = $properties.PSObject.Properties[$deviceNameProperty].Value
        if ($deviceName -and $deviceName -match $DeviceNamePattern) {
            $endpointMatches += [pscustomobject]@{
                DeviceName = $deviceName
                EndpointId = ('{0.0.0.00000000}.' + $endpointKey.PSChildName)
            }
        }
    }

    if ($endpointMatches.Count -gt 1) {
        throw ('More than one active playback endpoint matched: ' +
            (($endpointMatches.DeviceName | Sort-Object -Unique) -join ', ') +
            '. Use -DeviceNamePattern to select one device.')
    }

    return $endpointMatches | Select-Object -First 1
}

function Find-SettingsWindow {
    param($Root)

    $comboCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $comboAutomationId
    )
    $windows = $Root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    foreach ($candidate in $windows) {
        $combo = $candidate.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            $comboCondition
        )
        if ($combo) { return $candidate }
    }
    return $null
}

function Find-EnhancementsCombo {
    param($Window)

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $comboAutomationId
    )
    return $Window.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        $condition
    )
}

function Get-AllElements {
    param($Window)

    return $Window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )
}

function Test-TargetDevicePage {
    param($Window, [string]$DeviceName)

    $pagePattern = '^(?:\d+-\s*)?' + [regex]::Escape($DeviceName) + '$'
    foreach ($element in Get-AllElements -Window $Window) {
        if ($element.Current.Name -match $pagePattern) { return $true }
    }
    return $false
}

function Find-OffItem {
    param($Combo)

    $listItems = @()
    foreach ($element in $Combo.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )) {
        if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem) {
            $listItems += $element
        }
    }

    if ($OffLabel) {
        return $listItems | Where-Object { $_.Current.Name -eq $OffLabel } | Select-Object -First 1
    }

    $knownOffLabels = @(
        'Off', 'Av', 'Aus', 'Uit', 'Désactivé', 'Desactivado',
        'Disattivato', 'Wyłączone', 'Desligado', '关闭', 'オフ'
    )
    return $listItems |
        Where-Object { $knownOffLabels -contains $_.Current.Name } |
        Select-Object -First 1
}

try {
    if ($VerifyOnly) {
        $states = @(Get-LogitechEndpointState -DeviceNamePattern $DeviceNamePattern)
        if ($states.Count -eq 1 -and $states[0].IsOff) { Write-Output 'Off'; exit 0 }
        Write-Output 'Off could not be confirmed (absent, ambiguous, enabled or unsupported property).'
        exit 3
    }
    if (Get-Process SystemSettings -ErrorAction SilentlyContinue) {
        throw 'Close Windows Settings before running a correction.'
    }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    if ($GHubWaitSeconds -gt 0) {
        $gHubDeadline = (Get-Date).AddSeconds($GHubWaitSeconds)
        while ((Get-Date) -lt $gHubDeadline -and
            -not (Get-Process lghub_agent -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 2
        }
        if (Get-Process lghub_agent -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 8
        }
    }

    $endpointDeadline = (Get-Date).AddSeconds($EndpointWaitSeconds)
    do {
        $target = Find-TargetEndpoint
        if (-not $target) { Start-Sleep -Seconds 2 }
    } while (-not $target -and (Get-Date) -lt $endpointDeadline)

    if (-not $target) {
        throw ('No active playback endpoint matched "' + $DeviceNamePattern + '".')
    }

    $settingsUri = 'ms-settings:sound-properties?endpointId=' +
        [uri]::EscapeDataString($target.EndpointId)
    Invoke-GuardSettingsSession -KeepWindow:$KeepWindow -IsOpen {
        [bool](Get-Process SystemSettings -ErrorAction SilentlyContinue)
    } -Launch {
        $launchTime = [datetime]::UtcNow
        $process = Start-Process $settingsUri -PassThru
        # The Shell may not return a process for an activated packaged application.
        # Never infer ownership from an arbitrary process appearing after launch.
        $owned = $process -and $process.ProcessName -eq 'SystemSettings' -and $process.StartTime.ToUniversalTime() -ge $launchTime
        [pscustomobject]@{ Owned = [bool]$owned; Process = $process }
    } -Close {
        param($lease)
        $process = $lease.Process
        # Keep the exact process handle returned by launch; do not search by name or kill.
        if (-not $process.HasExited -and -not $process.CloseMainWindow()) {
            throw 'Owned Settings window did not accept the close request.'
        }
    } -Correct {
        param($lease)
    $root = [System.Windows.Automation.AutomationElement]::RootElement

    $windowDeadline = (Get-Date).AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 500
        $window = Find-SettingsWindow -Root $root
    } while (-not $window -and (Get-Date) -lt $windowDeadline)
    if (-not $window) { throw 'Windows Settings did not open.' }

    $pageDeadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $correctPage = Test-TargetDevicePage -Window $window -DeviceName $target.DeviceName
    } while (-not $correctPage -and (Get-Date) -lt $pageDeadline)
    if (-not $correctPage) {
        throw 'Windows Settings did not open the matched device page.'
    }

    Write-UiLog ('TARGET device=' + $target.DeviceName)

    $combo = Find-EnhancementsCombo -Window $window
    if (-not $combo) { throw 'The Audio enhancements control was not found.' }

    $expand = $combo.GetCurrentPattern(
        [System.Windows.Automation.ExpandCollapsePattern]::Pattern
    )
    if ($expand.Current.ExpandCollapseState -eq
        [System.Windows.Automation.ExpandCollapseState]::Collapsed) {
        $expand.Expand()
        Start-Sleep -Milliseconds 400
    }

    $off = Find-OffItem -Combo $combo
    if (-not $off) {
        throw 'The Off option was not recognized. Pass its visible text with -OffLabel.'
    }

    $selection = $off.GetCurrentPattern(
        [System.Windows.Automation.SelectionItemPattern]::Pattern
    )

    if ($VerifyOnly) {
        if (-not $selection.Current.IsSelected) {
            throw 'VERIFY failed: Audio enhancements is not Off.'
        }
        Write-UiLog 'VERIFY Audio enhancements=Off'
        exit 0
    }

    if (-not $selection.Current.IsSelected) {
        $selection.Select()
        Start-Sleep -Seconds 1
    }
    if (-not $selection.Current.IsSelected) {
        throw 'Windows did not keep the Off selection.'
    }

    Write-UiLog 'SUCCESS Audio enhancements=Off'

    }

    exit 0
}
catch {
    Write-GuardLog CorrectionFailed -ErrorCode $_.Exception.HResult
    Write-Output 'Correction failed. Check connection, unlocked desktop and the Off control.'
    exit 1
}
