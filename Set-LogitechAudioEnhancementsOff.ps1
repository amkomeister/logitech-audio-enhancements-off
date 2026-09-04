param(
    [string]$DeviceNamePattern = 'Logitech PRO X Wireless Gaming Headset',
    [string]$OffLabel,
    [int]$EndpointWaitSeconds = 120,
    [int]$GHubWaitSeconds = 120,
    [switch]$KeepWindow,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot 'LogitechAudioEnhancementsOff.log'
$comboAutomationId = 'SystemSettings_Audio_Output_Enhance_Audio_ComboBox'
$renderRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$deviceNameProperty = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'

function Write-UiLog {
    param([string]$Message)
    ('{0:u} {1}' -f (Get-Date), $Message) |
        Out-File -LiteralPath $logPath -Append -Encoding utf8
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

    $settingsWasOpen = [bool](Get-Process SystemSettings -ErrorAction SilentlyContinue)
    $settingsUri = 'ms-settings:sound-properties?endpointId=' +
        [uri]::EscapeDataString($target.EndpointId)
    Start-Process $settingsUri
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

    if (-not $KeepWindow -and -not $settingsWasOpen) {
        try {
            $windowPattern = $window.GetCurrentPattern(
                [System.Windows.Automation.WindowPattern]::Pattern
            )
            $windowPattern.Close()
        }
        catch {
            # The setting is saved even if Windows Settings cannot be closed.
        }
    }

    exit 0
}
catch {
    Write-UiLog ('ERROR ' + $_.Exception.Message + ' | ' + $_.ScriptStackTrace)
    exit 1
}
