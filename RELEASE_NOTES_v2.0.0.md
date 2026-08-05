# ProTee AutoStart v2.0.0

Biggest update yet. Download `ProTeeAutoStart-2.0.0.zip` below, extract, and run. Upgrading from an older version: just replace your old `.exe` with the new one - your settings are kept.

## New

- **Stop at the GSPro main menu** - new Setup option for facilities that don't want the bay auto-loading the practice range. The tool still handles updates, Play, and the launch-monitor connection, then finishes at the menu with GSPro focused in front of the ProTee connector window.
- **Works at any resolution, scale, and monitor setup** - the status banner is now invisible to the tool's own screen reading, so it can never block a button from being detected, on any screen size, display scale, monitor count, or orientation. It also sizes itself proportionally on smaller screens.
- **Banner follows GSPro automatically** - lands on whatever monitor GSPro is on, with a manual override in Setup (Auto / monitor number / Off).
- **End-of-sequence fix** - the final click and cursor parking now always happen on the GSPro screen, not the other monitor.
- **Update-prompt diagnostics** - if a ProTee Labs / GSPro update prompt appears with wording the tool doesn't recognize, it logs exactly what it saw so the wording can be added in the next release.
- **Properly branded executable** - the exe now carries full BA Custom Products version information (right-click, Properties, Details).

## Verify your download

SHA-256 of `ProTeeAutoStart.exe`:
`de1921bdd9b85608091788dec0bf5caf9d8586343d7cba5723699e30fc791400`

SHA-256 of `ProTeeAutoStart-2.0.0.zip`:
`1a9526514f50b6b81f080aa28f264175bee5a1b1cf2331a184e9a89014c79aa9`

First run may show a Windows SmartScreen warning (the exe is not code-signed yet): click More info, then Run anyway.
