# Logitech Audio Enhancements Off

A small PowerShell utility for Windows 11 that sets **Audio enhancements** to
**Off** for an active Logitech PRO X Wireless Gaming Headset after sign-in.

This can be useful when Logitech's HX2E processing is automatically restored
and you prefer unprocessed stereo output.

## Privacy and safety

- No telemetry or network access.
- No usernames, computer-specific paths, endpoint IDs, or personal logs are
  included in this repository.
- The script does not overclock hardware, replace drivers, edit registry
  permissions, or disable Windows security features.
- A local log is created beside the script. `*.log` is excluded from Git.

## Requirements

- Windows 11
- Windows PowerShell 5.1
- Logitech PRO X Wireless Gaming Headset with the Logitech audio driver
- Logitech G HUB is recommended

The utility uses the stable Windows Settings automation ID for the Audio
enhancements control. It recognizes the visible Off label in several common
Windows display languages, including English and Norwegian.

## Install

1. Download the repository as a ZIP and extract it to a permanent folder.
2. Right-click Start, open **Windows PowerShell**, and change to that folder.
3. Run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

The installer creates a scheduled task named
`Keep Logitech Audio Enhancements Off`. It runs 25 seconds after you sign in.
Administrator privileges are not requested by the scripts.

To run it immediately:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-LogitechAudioEnhancementsOff.ps1
```

To verify the current setting without changing it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Set-LogitechAudioEnhancementsOff.ps1 -VerifyOnly -KeepWindow
```

## Other Logitech device names or display languages

The default device-name pattern is `Logitech PRO X Wireless Gaming Headset`.
You can supply a different regular expression:

```powershell
.\Set-LogitechAudioEnhancementsOff.ps1 -DeviceNamePattern 'Logitech PRO X 2.*'
```

If the script does not recognize the translated Off label, pass the exact text
shown by Windows:

```powershell
.\Set-LogitechAudioEnhancementsOff.ps1 -OffLabel 'Off'
```

## Uninstall

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

This removes only the scheduled task. You can then delete the extracted folder
manually.

## Known limitation

The scheduled task runs after Windows sign-in. If G HUB resets the setting when
the headset is power-cycled later in the same session, run the main script
again. This version does not continuously monitor the headset.

## Troubleshooting

Check `LogitechAudioEnhancementsOff.log` in the extracted folder. If more than
one playback device matches, use a narrower `-DeviceNamePattern`. If Windows is
using an unsupported display-language label, pass `-OffLabel`.

## License

MIT
