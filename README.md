# Logitech Stereo Guard 2

Windows 11 / Windows PowerShell 5.1 utility that keeps Audio enhancements Off
for one matching active Logitech playback endpoint. No telemetry, downloads,
driver changes, registry writes, ACL changes or persistent execution-policy changes.

## Operation and limitations

A hidden logon worker listens to Win32_DeviceChangeEvent, coalesces notification
bursts for three seconds, and checks active playback endpoints. A read-only
check every 60 seconds catches missed events and G HUB property resets. If WMI
is unavailable, periodic checks continue. A mutex permits one worker per session.

Already-Off endpoints require no UI. Missing or ambiguous matches never cause
correction. Otherwise the existing Windows Settings UI setter selects Off.
**A corrective action can briefly display Settings.** Existing Settings windows
are left alone. Correction attempts are limited to once every five minutes;
this also delays closely spaced reconnects. Locked desktops may prevent correction.
The UI automation ID is not a promised stable Windows API.

Microsoft documents [audio endpoint properties](https://learn.microsoft.com/en-us/windows/win32/coreaudio/audio-endpoint-properties)
as properties clients should read, while [OpenPropertyStore](https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdevice-openpropertystore)
restricts non-admin clients to reads. No supported silent setter is established
here; unsupported registry writes and permission changes are deliberately avoided.
The read-only Disable_SysFx registry check is driver-dependent. Missing values
mean unknown, not confirmed Off. A successful check does not prove that every
possible processing stage in a particular audio stream is disabled.

## Verify without audio writes or Settings UI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-LogitechAudioEnhancementsOff.ps1 -VerifyOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-LogitechStereo.ps1 -VerifyOnly -Once
```

Exit 0 confirms one active endpoint is Off; exit 3 means unconfirmed, exit 1
means observation failure. Omit -Once for continuous observation; Ctrl+C stops
it. Watch mode still writes sanitized status logs in verify-only mode.

## Install and uninstall

Extract to a permanent folder and open Windows PowerShell there:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

Installation creates Logitech Stereo Guard 2, a new limited-privilege interactive
logon task starting 25 seconds after next sign-in. Existing tasks are never
overwritten. Keep the folder in place. Organization policy may deny installation.
Uninstall checks its ownership marker and script path, stops and removes only
that task, and preserves audio settings and logs. Legacy tasks remain untouched;
manually review and disable an old guard task to avoid overlapping corrections.
Do not run a manual worker alongside the scheduled worker.

Start immediately or perform one correction:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-LogitechStereo.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-LogitechAudioEnhancementsOff.ps1 -GHubWaitSeconds 0
```

Both scripts accept a narrow -DeviceNamePattern regular expression; the default
is Logitech PRO X Wireless Gaming Headset. The installer uses that default;
custom devices require a manually configured task action. The one-shot setter
supports -OffLabel for another language and -KeepWindow for UI troubleshooting.

## Data flow and troubleshooting

Local registry/process/event reads feed a decision, optional UI correction and
status logging. Device names and endpoint IDs remain in memory. Logs under the
current user's local app-data LogitechStereoGuard2 folder contain only fixed
status codes, UTC timestamps and numeric errors. They rotate at 1 MiB, retaining
one previous file. No names, paths, device IDs, raw errors or stack traces are
logged. Git excludes logs, captures and local configuration. Legacy version logs
could contain device names or paths: do not publish them.

Absent: wait for connection. Ambiguous: narrow the name pattern. SettingsBusy:
close Settings. VerifyRequired: Off is not confirmed. CorrectionFailed: check the
desktop is unlocked and the Off control exists; run the setter interactively.
EventFallback: periodic checking continues without WMI notifications.

## Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Offline tests cover decision safety, cooldown, syntax and installer WhatIf.
Windows CI also checks PSScriptAnalyzer errors. Actual audio writes, scheduled
task installation and physical headset/G HUB reload behavior are manual
acceptance tests, not established by offline tests. Verify the correct Settings
page stays Off after a headset reconnect and G HUB restart on your machine.

MIT. Version 2.0.0.

Settings is checked again immediately before opening, after device/G HUB waits.
Cleanup runs after success and failure, unless -KeepWindow is set. It only asks
the exact SystemSettings process returned by launch to close its main window;
it never searches for and terminates another Settings process. If Windows Shell
does not return an owning process for packaged-app activation, automatic cleanup
cannot be proven safe and is skipped. Close that Settings window manually before
the next guard correction. A user opening Settings at the exact launch instant
is an unavoidable race in the Shell/UI automation interface.