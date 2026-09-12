# Approved implementation plan: Stereo Guard 2

The approved scope is reconnect/reload recovery without changing drivers, registry ACLs or the existing legacy scheduled task.

1. Add a pure decision core and regression tests for absence, ambiguity, Off, Settings-in-use and cooldown.
2. Read active playback endpoint state and Disable_SysFx without writes; use a WMI device-change subscription and a 60-second fallback to catch missed driver/property resets.
3. Reuse the existing Settings UI setter only for required correction. Microsoft documents audio endpoint properties as read-only for clients; do not introduce unsupported silent registry writes. Debounce events, protect an already-open Settings window, and impose a five-minute correction cooldown.
4. Provide read-only verify/monitor, isolated named scheduled task with WhatIf and ownership checks, bounded sanitized logs, English documentation and offline test CI.
5. Test syntax, decision behavior and installer dry-runs locally. Hardware reconnection and actual setting changes require user testing; do not alter this development host's audio state.
