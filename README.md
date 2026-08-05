# WinTool — Windows Optimization & Debloat Utility

A PowerShell + WPF utility for optimizing, debloating, and configuring Windows,
in the spirit of Chris Titus Tech's WinUtil. Built so tweaks/apps live in JSON
config files instead of being hardcoded — anyone can add or edit a tweak
without touching the GUI logic.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (ships with Windows) — no PowerShell 7 install required
- Administrator rights (the script self-elevates if launched normally)
- [winget](https://aka.ms/getwinget) for the App Installer tab (pre-installed on modern Windows 10/11)

## Running it

```powershell
# From the project folder:
powershell -ExecutionPolicy Bypass -File main.ps1
```

The script checks for admin rights and relaunches itself elevated (via a UAC
prompt) if needed. You do not need to manually "Run as Administrator" —
though you can, and it will just skip the relaunch step.

## What it does

| Tab | Purpose |
|---|---|
| **Performance** | Visual effects, power plan, Nagle's algorithm, hibernation |
| **Privacy** | Telemetry, advertising ID, location tracking, activity history |
| **Explorer** | File extensions, hidden files, classic context menu, default view |
| **Debloat** | Removes bundled apps (Xbox, Cortana, OneDrive, Bing apps, etc.) |
| **Updates** | Toggle auto-update, enable driver updates, reset WU components |
| **App Installer** | Batch-installs common apps via `winget` |
| **Log** | Live view of the session's action log |

Every tweak is a checkbox. Nothing is pre-checked. Nothing is applied until
you click **Apply Selected**. Risky tweaks (flagged `RequiresConfirmation` in
`tweaks.json`) show an extra warning dialog before running.

### Safety behavior

- **Elevation check** on launch (`Assert-Admin` in `functions/Core.ps1`)
- **System Restore point** created automatically before applying tweaks, and
  on-demand via the "Create Restore Point" button
- **Full session logging** to `Documents\WinTool-Logs\WinTool_<timestamp>.log`,
  mirrored live in the Log tab
- **Confirmation dialogs** for anything flagged as risky (e.g., removing Edge,
  resetting Windows Update components)
- Every action is wrapped in try/catch — one failing tweak won't crash the run
  or block the others

## Project structure

```
wintool/
├── main.ps1                 # Entry point — builds the GUI, wires buttons
├── tweaks.json               # All tweaks, grouped by category, with Apply/Undo actions
├── apps.json                  # Winget app catalog, grouped by category
├── functions/
│   ├── Core.ps1               # Admin check, restore point, logging
│   ├── Tweaks.ps1              # Generic engine that runs tweak actions
│   ├── AppInstaller.ps1         # winget install/uninstall wrapper
│   └── ConfigProfile.ps1         # Export/import a selected-tweaks profile as JSON
└── README.md
```

## Adding a new tweak

Open `tweaks.json`, pick (or add) a category array, and append an object:

```json
{
  "Id": "MyNewTweak",
  "Name": "Human-readable name shown in the UI",
  "Description": "One sentence explaining what this does.",
  "Category": "Performance",
  "RequiresConfirmation": false,
  "Apply": [
    { "Type": "Registry", "Path": "HKCU:\\Some\\Path", "Name": "ValueName", "Value": 1, "ValueType": "DWord" }
  ],
  "Undo": [
    { "Type": "Registry", "Path": "HKCU:\\Some\\Path", "Name": "ValueName", "Value": 0, "ValueType": "DWord" }
  ]
}
```

Supported `Type` values (handled in `functions/Tweaks.ps1`):

- `Registry` — set a registry value (`Path`, `Name`, `Value`, `ValueType`)
- `Service` — `Action` is one of `Enable`/`Disable`/`Manual`/`Automatic`
- `Command` — arbitrary PowerShell string, run via `Invoke-Expression`
- `AppxRemove` — `Packages` is an array of Appx package name prefixes
- `Note` — no-op, just logs a message (used for actions that can't be auto-undone)

No code changes are needed for a straightforward new tweak — just add the
JSON entry and it appears in the matching tab automatically.

## Adding a new app to the installer

Add an entry to the right category array in `apps.json`:

```json
{ "Id": "Some.Unique.Id", "Name": "Display Name", "WingetId": "Publisher.PackageName" }
```

Find the correct `WingetId` with:

```powershell
winget search "app name"
```

## Config profiles

Use **Export Profile** / **Import Profile** to save or load a specific
combination of checked tweaks and apps as a `.json` file — handy for setting
up multiple machines identically. Profiles only store IDs, so they stay valid
even if `tweaks.json`/`apps.json` are later edited (as long as IDs don't change).

## Known limitations / things to harden before wide distribution

- The script is unsigned — Windows SmartScreen will warn on first run. Consider
  code-signing if distributing broadly.
- `AppxRemove` actions are not automatically reversible; reinstalling from the
  Microsoft Store is the manual fallback (noted in each tweak's `Undo` block).
- `Invoke-Expression` is used for the generic `Command` action type for
  flexibility — since all commands come from your own `tweaks.json` (not user
  input), this is safe as shipped, but don't wire arbitrary external/remote
  JSON into this field without review.
- No auto-update mechanism for the tool itself; re-download/re-clone to update.
