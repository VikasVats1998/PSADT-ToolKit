# PSAppDeployToolkit v4.1.8 — UI Functions Reference

Complete reference for every user-interface related cmdlet shipped with **PSAppDeployToolkit 4.1.8** (confirmed via `PSAppDeployToolkit\PSAppDeployToolkit.psd1` → `ModuleVersion = '4.1.8'`).

Covers: welcome/close-apps dialogs, progress dialogs, install prompts, restart prompts (with countdown timer), balloon tip / toast notifications, generic dialog boxes, the help console, getting installed-application info, and reading the user's notification/focus-assist state.

> Generated from the live module help (`Get-Help -Full`) — every parameter, switch, and example below is exactly what ships in this template's `PSAppDeployToolkit\lib\PSADT.dll`.

---

## Table of Contents

1. [Show-ADTInstallationWelcome](#1-show-adtinstallationwelcome) — close-apps prompt, defer, countdown timer, block execution
2. [Show-ADTInstallationProgress](#2-show-adtinstallationprogress) — updatable progress dialog
3. [Close-ADTInstallationProgress](#3-close-adtinstallationprogress) — closes the progress dialog
4. [Show-ADTInstallationPrompt](#4-show-adtinstallationprompt) — custom branded prompt with buttons / text input
5. [Show-ADTInstallationRestartPrompt](#5-show-adtinstallationrestartprompt) — restart prompt with countdown timer
6. [Show-ADTBalloonTip](#6-show-adtballoontip) — system tray balloon / toast notification
7. [Show-ADTDialogBox](#7-show-adtdialogbox) — plain Win32 MessageBox-style dialog
8. [Show-ADTHelpConsole](#8-show-adthelpconsole) — graphical module help browser
9. [Get-ADTApplication](#9-get-adtapplication) — get installed app info
10. [Get-ADTUserNotificationState](#10-get-adtusernotificationstate) — Focus Assist / Presentation state
11. [Shared enums: WindowLocation & Icon](#11-shared-enums)
12. [Full worked example](#12-full-worked-example)

---

## 1. Show-ADTInstallationWelcome

Shows the welcome dialog: close running apps (with an optional **countdown timer**), let the user **defer**, block re-launch of apps, and check disk space.

```powershell
# Simple: just ask the user to close two apps
Show-ADTInstallationWelcome -CloseProcesses iexplore, winword, excel

# Silent close, no prompt shown
Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'winword' }, @{ Name = 'excel' } -Silent

# Close + block relaunch while deployment runs
Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'winword' }, @{ Name = 'excel' } -BlockExecution

# Custom descriptions + a countdown TIMER (10 minutes) before apps are force-closed
Show-ADTInstallationWelcome `
    -CloseProcesses @{ Name = 'winword'; Description = 'Microsoft Office Word' }, @{ Name = 'excel'; Description = 'Microsoft Office Excel' } `
    -CloseProcessesCountdown 600

# Persistent prompt (keeps re-centering itself so the user can't ignore it)
Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'winword' }, @{ Name = 'msaccess' }, @{ Name = 'excel' } -PersistPrompt

# Allow the user to defer until a deadline
Show-ADTInstallationWelcome -AllowDefer -DeferDeadline '2013-08-25'

# Full-featured: close + block + defer (max 10 times or until deadline) + 10-min close countdown
Show-ADTInstallationWelcome `
    -CloseProcesses @{ Name = 'winword' }, @{ Name = 'excel' } `
    -BlockExecution `
    -AllowDefer -DeferTimes 10 -DeferDeadline '2013-08-25' `
    -CloseProcessesCountdown 600
```

### Parameters

| Parameter | Type | Notes |
|---|---|---|
| `-CloseProcesses` | `ProcessDefinition[]` | Process(es) to close (no `.exe`). `@{ Name = 'winword'; Description = 'Microsoft Word' }` |
| `-HideCloseButton` | switch | Hide the "Close Processes" button, forcing manual closure |
| `-Silent` | switch | Close processes without prompting |
| `-CloseProcessesCountdown` | int | **Timer (seconds)** — apps auto-close after this, only if defer isn't active/expired |
| `-ForceCloseProcessesCountdown` | int | **Timer (seconds)** — apps auto-close regardless of defer state |
| `-ForceCountdown` | int | **Timer (seconds)** before auto-proceeding when defer is enabled |
| `-AllowDefer` | switch | Enables the Defer button |
| `-AllowDeferCloseProcesses` | switch | Defer button shown only if apps need closing (implies `-AllowDefer`) |
| `-DeferTimes` | int | Max number of times the user can defer |
| `-DeferDays` | int | Days since first run until deferral expires (converted to a deadline) |
| `-DeferDeadline` | datetime | Explicit deadline date/time for deferral |
| `-DeferRunInterval` | timespan | Min. time between re-prompts after a deferral (e.g. `([TimeSpan]::FromMinutes(30))`) |
| `-BlockExecution` | switch | Prevents users launching the listed apps during deployment |
| `-PromptToSave` | switch | Prompts to save open documents before closing apps |
| `-PersistPrompt` | switch | Dialog re-centers itself repeatedly — can't be ignored |
| `-WindowLocation` | enum | See [§11](#11-shared-enums) |
| `-MinimizeWindows` / `-NotTopMost` / `-AllowMove` | switch | Window behavior |
| `-CustomText` | switch | Show custom text from `strings.psd1` |
| `-CheckDiskSpace` | switch | Verify free disk space before continuing |
| `-RequiredDiskSpace` | int | Required space in MB (with `-CheckDiskSpace`) |

**Notes:** No active ADT session required. Dialog auto-times-out per `config.psd1` (default 55 min) and exits with SCCM fast-retry code `1618`.

---

## 2. Show-ADTInstallationProgress

Updatable "please wait" marquee progress dialog, rendered on its own WPF thread.

```powershell
# Default message from strings.psd1
Show-ADTInstallationProgress

# Custom message
Show-ADTInstallationProgress -StatusMessage 'Installation in Progress...'

# Multi-line message
Show-ADTInstallationProgress -StatusMessage "Installation in Progress...`nThe installation may take 20 minutes to complete."

# Positioned + not topmost
Show-ADTInstallationProgress -StatusMessage 'Installation in Progress...' -WindowLocation 'BottomRight' -NotTopMost

# With a percentage-driven status bar (fluent theme) and detail line
Show-ADTInstallationProgress -StatusMessage 'Installing...' -StatusMessageDetail 'Copying files (3 of 10)' -StatusBarPercentage 30
```

### Parameters

| Parameter | Type | Notes |
|---|---|---|
| `-StatusMessage` | string | Main message (position 1) |
| `-StatusMessageDetail` | string | Secondary detail line (fluent theme, position 2) |
| `-StatusBarPercentage` | int | If set, shows a determinate % bar instead of a scrolling marquee |
| `-MessageAlignment` | `Left \| Center \| Right` | Default `Center` |
| `-WindowLocation` | enum | See [§11](#11-shared-enums) |
| `-NotTopMost` / `-AllowMove` | switch | Window behavior |

**Note:** First call in a script also fires the "installation started" balloon tip (if enabled in `config.psd1`).

---

## 3. Close-ADTInstallationProgress

```powershell
Close-ADTInstallationProgress
```

Closes the dialog opened by `Show-ADTInstallationProgress`. No parameters. Also called automatically by `Close-ADTSession`.

---

## 4. Show-ADTInstallationPrompt

Custom branded prompt — up to 3 buttons, an icon, optional text-input box.

```powershell
# Yes/No prompt, react to the button clicked
$result = Show-ADTInstallationPrompt -Message 'Do you want to proceed with the installation?' -ButtonLeftText Yes -ButtonRightText No
switch ($result) {
    Yes { Write-ADTLogEntry 'User clicked the [Yes] button.' }
    No  { Write-ADTLogEntry 'User clicked the [No] button.' }
}

# Three buttons
Show-ADTInstallationPrompt -Message 'How are you feeling today?' -ButtonLeftText 'Good' -ButtonRightText 'Bad' -ButtonMiddleText 'Indifferent'

# Info prompt that doesn't block the script (-NoWait)
Show-ADTInstallationPrompt -Message 'You can customize text to appear at the end of an install, or remove it completely for unattended installations.' -ButtonLeftText 'OK' -Icon Information -NoWait

# Free-text input box
Show-ADTInstallationPrompt -RequestInput -Message 'Tell us why you think PSADT is the best thing since sliced bread.' -ButtonRightText 'Submit'

# Text input with a pre-filled default value
Show-ADTInstallationPrompt -RequestInput -DefaultValue 'XXXX' -Message 'Please type in your favourite beer.' -ButtonRightText 'Submit'
```

### Parameters

| Parameter | Type | Notes |
|---|---|---|
| `-Message` | string | **Required.** Prompt text |
| `-MessageAlignment` | `Left \| Center \| Right` | Default `Center` |
| `-ButtonLeftText` / `-ButtonMiddleText` / `-ButtonRightText` | string | Any combination; the clicked button's text is returned |
| `-RequestInput` | switch | Shows a text box for user input |
| `-DefaultValue` | string | Pre-fills the text box (`-RequestInput`) |
| `-Icon` | enum | `Application \| Asterisk \| Error \| Exclamation \| Hand \| Information \| Question \| Shield \| Warning \| WinLogo` |
| `-WindowLocation` | enum | See [§11](#11-shared-enums) |
| `-NoWait` | switch | Runs on its own thread — doesn't block the main script |
| `-PersistPrompt` / `-MinimizeWindows` / `-NotTopMost` / `-AllowMove` | switch | Window behavior |
| `-NoExitOnTimeout` | switch | Don't exit the script if the dialog times out |
| `-Force` | switch | Show even if `DeployMode` is silent |

**Returns:** the text of the button clicked.

---

## 5. Show-ADTInstallationRestartPrompt

Restart prompt with a **countdown timer** to a forced reboot. Three mutually-exclusive modes: countdown, no-countdown, silent.

```powershell
# Immediate prompt, no countdown
Show-ADTInstallationRestartPrompt -NoCountdown

# 300-second (5 min) countdown timer to forced restart
Show-ADTInstallationRestartPrompt -CountdownSeconds 300

# 600-second countdown, last 60 seconds the dialog can no longer be hidden
Show-ADTInstallationRestartPrompt -CountdownSeconds 600 -CountdownNoHideSeconds 60

# Silent-mode restart with its own short countdown (used when DeployMode is Silent/VerySilent)
Show-ADTInstallationRestartPrompt -SilentRestart -SilentCountdownSeconds 5
```

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-CountdownSeconds` | int | 60 | **Timer** — total seconds the prompt is shown before forced restart |
| `-CountdownNoHideSeconds` | int | 30 | Final seconds during which the dialog can't be minimized/hidden |
| `-NoCountdown` | switch | — | Show prompt with no timer, immediate restart choice |
| `-SilentRestart` | switch | — | Trigger the restart automatically when `DeployMode` is silent/very-silent |
| `-SilentCountdownSeconds` | int | 5 | **Timer** used in silent mode when `-SilentRestart` isn't specified |
| `-WindowLocation` | enum | — | See [§11](#11-shared-enums) |
| `-CustomText` | switch | — | Use custom text from `strings.psd1` |
| `-NotTopMost` / `-AllowMove` | switch | — | Window behavior |

**Warning:** code immediately after this call (including logging) may not execute if the countdown elapses and the machine reboots.

---

## 6. Show-ADTBalloonTip

System tray balloon tip (auto-converted to a Windows 10+ toast notification).

```powershell
Show-ADTBalloonTip -BalloonTipText 'Installation Started' -BalloonTipTitle 'Application Name'

Show-ADTBalloonTip -BalloonTipIcon 'Info' -BalloonTipText 'Installation Started' -BalloonTipTitle 'Application Name'

# Force display even when running silently, don't block the script
Show-ADTBalloonTip -BalloonTipText 'Installation Complete' -BalloonTipIcon Info -BalloonTipTime 5000 -NoWait -Force
```

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-BalloonTipText` | string | — | **Required.** Position 1 |
| `-BalloonTipIcon` | `None \| Info \| Warning \| Error` | `Info` | |
| `-BalloonTipTime` | int (ms) | 10000 | Display duration |
| `-NoWait` | switch | — | Show asynchronously |
| `-Force` | switch | — | Show even when running silently |

---

## 7. Show-ADTDialogBox

Plain Win32-style MessageBox. **`Show-ADTInstallationPrompt` is recommended over this** since it matches toolkit branding.

```powershell
Show-ADTDialogBox -Text 'Installation will take approximately 30 minutes. Do you wish to proceed?' -Buttons 'OkCancel' -DefaultButton 'Second' -Icon 'Exclamation' -NotTopMost
```

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-Text` | string | — | **Required.** Position 1 |
| `-Buttons` | `Ok \| OkCancel \| AbortRetryIgnore \| YesNoCancel \| YesNo \| RetryCancel \| CancelTryContinue` | `Ok` | |
| `-DefaultButton` | `First \| Second \| Third` | `First` | |
| `-Icon` | `None \| Stop \| Question \| Exclamation \| Information` | `None` | |
| `-NoWait` | switch | — | Non-blocking |
| `-ExitOnTimeout` | switch | — | Exit script if UI times out |
| `-NotTopMost` / `-Force` | switch | — | |

**Returns:** `PSADT.UserInterface.DialogResults.DialogBoxResult` — the clicked button's text.

---

## 8. Show-ADTHelpConsole

```powershell
Show-ADTHelpConsole
```

Opens a graphical PowerShell window listing every command exported by the module, with full help text for the selected command. No parameters. Useful for browsing all 134 module cmdlets interactively.

---

## 9. Get-ADTApplication

**"Get app info"** — queries the registry uninstall keys for installed application details.

```powershell
# All installed applications
Get-ADTApplication

# Contains-match on display name
Get-ADTApplication -Name 'Acrobat'

# Exact match
Get-ADTApplication -Name 'Adobe Acrobat Reader' -NameMatch 'Exact'

# By MSI ProductCode
Get-ADTApplication -ProductCode '{AC76BA86-7AD7-1033-7B44-AC0F074E4100}'

# MSI apps only, further filtered by publisher
Get-ADTApplication -Name 'Acrobat' -ApplicationType 'MSI' -FilterScript { $_.Publisher -match 'Adobe' }

# Include Windows updates/hotfixes in results
Get-ADTApplication -Name 'KB5' -IncludeUpdatesAndHotfixes
```

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-Name` | `string[]` | — | Display name to search for |
| `-NameMatch` | `Contains \| Exact \| Wildcard \| Regex` | `Contains` | Match mode for `-Name` |
| `-ProductCode` | `Guid[]` | — | MSI product code(s) |
| `-ApplicationType` | `All \| MSI \| EXE` | `All` | |
| `-IncludeUpdatesAndHotfixes` | switch | — | Include update/hotfix entries |
| `-FilterScript` | scriptblock | — | Extra filter, e.g. `{ $_.Publisher -match 'Adobe' }` |

### Returns — `PSADT.Types.InstalledApplication`

`PSPath`, `PSParentPath`, `PSChildName`, `ProductCode`, `DisplayName`, `DisplayVersion`, `UninstallString`, `QuietUninstallString`, `InstallSource`, `InstallLocation`, `InstallDate`, `Publisher`, `HelpLink`, `EstimatedSize`, `SystemComponent`, `WindowsInstaller`, `Is64BitApplication`

```powershell
# Practical example: bail out of the deployment if already installed at target version
$installed = Get-ADTApplication -Name 'Contoso App' -NameMatch Exact
if ($installed | Where-Object { $_.DisplayVersion -eq '2.1.0' }) {
    Write-ADTLogEntry 'Already installed at target version — exiting.'
    Close-ADTSession -ExitCode 0
}
```

---

## 10. Get-ADTUserNotificationState

Reads the logged-on user's Focus Assist / "Presentation mode" style notification state — useful for deciding **whether it's safe to pop a UI prompt** (a switch-like gating check before calling any `Show-ADT*` cmdlet above).

```powershell
Get-ADTUserNotificationState
```

Returns a `PSADT.LibraryInterfaces.QUERY_USER_NOTIFICATION_STATE` enum value. No parameters; no active ADT session required.

```powershell
# Gate a prompt behind the user's notification state
if ((Get-ADTUserNotificationState) -notmatch 'Busy|PresentationMode|Running') {
    Show-ADTInstallationPrompt -Message 'Ready to continue?' -ButtonRightText 'OK'
}
```

---

## 11. Shared enums

### `WindowLocation` (used by every `Show-ADT*` dialog)

```
Default | TopLeft | Top | TopRight | TopCenter | Center | BottomLeft | Bottom | BottomRight | BottomCenter
```

### `Icon` (Show-ADTInstallationPrompt)

```
Application | Asterisk | Error | Exclamation | Hand | Information | Question | Shield | Warning | WinLogo
```

### `Icon` (Show-ADTDialogBox)

```
None | Stop | Question | Exclamation | Information
```

---

## 12. Full worked example

Realistic pre-installation UI flow combining app-info lookup, a close-apps prompt with a defer + countdown timer, a progress dialog, and a restart prompt — matching the pattern used in `Invoke-AppDeployToolkit.ps1`.

```powershell
# 1. Skip if already installed at the target version
$existing = Get-ADTApplication -Name 'Contoso App' -NameMatch Exact
if ($existing | Where-Object { $_.DisplayVersion -eq '2.1.0' }) {
    Write-ADTLogEntry 'Contoso App 2.1.0 already installed — nothing to do.'
    Close-ADTSession -ExitCode 0
}

# 2. Notify the user installation is about to begin
Show-ADTBalloonTip -BalloonTipText 'Contoso App installation is starting shortly.' -BalloonTipTitle 'Contoso App' -NoWait

# 3. Ask the user to close blocking apps, allow 3 deferrals, force-close after 10 min
Show-ADTInstallationWelcome `
    -CloseProcesses @{ Name = 'ContosoApp'; Description = 'Contoso App' } `
    -BlockExecution `
    -AllowDeferCloseProcesses -DeferTimes 3 -DeferDeadline (Get-Date).AddDays(3) `
    -CloseProcessesCountdown 600 `
    -CheckDiskSpace

# 4. Show progress while the real work happens
Show-ADTInstallationProgress -StatusMessage 'Installing Contoso App, please wait...'
Start-ADTMsiProcess -Action Install -FilePath 'ContosoApp.msi'
Close-ADTInstallationProgress

# 5. Ask about a restart, with a 5-minute countdown timer
if (Test-ADTRegistryValue -Key 'HKLM:\SOFTWARE\Contoso' -Name 'RebootPending' -ErrorAction SilentlyContinue) {
    Show-ADTInstallationRestartPrompt -CountdownSeconds 300 -CountdownNoHideSeconds 60
}
```

---

### Source of truth

All syntax, parameters, and examples above come directly from `Get-Help -Full` against the compiled cmdlets in this template's `PSAppDeployToolkit\lib\PSADT.dll` (module version **4.1.8**, `PSAppDeployToolkit\PSAppDeployToolkit.psd1`). Run `Show-ADTHelpConsole` for the live, always-current version, or `Get-Help <CmdletName> -Full` for any single cmdlet.
