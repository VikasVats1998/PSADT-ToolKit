# Node.js — PSADT Dependency Version-Upgrade

Models a dependency version-upgrade workflow, not a plain "install this app"
package: detect the current version → decide if an update is due → detect
which apps depend on it → confirm with the user → forcefully close them →
install → restart check → summary.

## What this does

- **Detects the installed version** via `Get-ADTApplication -Name 'Node.js'` and compares it against a target "available" version.
- **Detects which example dependent apps are currently running** (`Get-ADTRunningProcesses`) — Visual Studio Code (`Code`) and Notepad are used as illustrative stand-ins. Windows has no API that tells you which arbitrary desktop apps depend on a given runtime; a real deployment maintains this list from its own app inventory.
- **Shows a confirmation prompt** naming the available version and listing which dependent apps need to close, with **Install** / **Cancel** buttons.
- **Forcefully closes** any running dependent apps if the user proceeds — `Show-ADTInstallationWelcome -CloseProcesses -BlockExecution`, deliberately with no `-AllowDefer`.
- **Installs** the real MSI end to end via `Start-ADTMsiProcess`.
- **Shows a restart summary.** Node.js's MSI essentially never needs a restart, so this always ends with "no restart required" — accurate for this app, not a shortcut. (Reboot handling here relies on PSADT's own automatic exit-code check in `Close-ADTSession`, rather than manually inspecting `Start-ADTMsiProcess`'s `-PassThru` result — its return shape couldn't be confirmed the way `Start-ADTProcess`'s can.)
- **Uninstalls a real removal** via `Start-ADTMsiProcess -Action Uninstall -FilePath $existingApp.ProductCode`.

**What's simulated:** there's only one real Node.js MSI available (24.14.1),
so there's no genuinely newer build to install. `$SimulatedAvailableVersion`
in `AppConfig.ps1` is a hardcoded stand-in purely so you can exercise the
version-comparison decision logic — in a real dependency-update package
this number would come from a live source (a manifest file, a vendor API,
your patch-management tool's update feed), not a literal string. The
actual install step is real, not simulated.

## Confirmed silent-mode-safe

This was actually tested, not assumed. `Show-ADTInstallationPrompt` returns
`$null` under `-DeployMode Silent` rather than either button's text, since
nobody's there to click anything. The confirmation prompt's gate is
`if ($proceed -eq 'Cancel')` — **not** `-ne 'Install'` — specifically so
that a real silent run (where `$proceed` is `$null`) falls through and
proceeds instead of being mistaken for a cancellation.

## The `$ForcePracticeRun` toggle

`AppConfig.ps1` has `$ForcePracticeRun = $true`, which forces the full flow
to run for practice even if the version comparison says no update is
actually due. Set it to `$false` to see the realistic "already up to date,
doing nothing" behavior instead.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher. Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, detection method, `$SimulatedAvailableVersion`, the dependent-app list, `$ForcePracticeRun`, `$SupportsUninstall`. **This is the file you edit.**
- `DependencyUpdateLogic.ps1` — the standard detect → confirm → close → install → restart pattern, written generically against the config values above. Same file, unmodified, across every dependency-update package in this set.

## Test it

```powershell
cd "AppDeployments\04-NodeJS-VersionUpgrade"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

**What you should see:** a prompt naming the (simulated) available version
and listing running dependent apps → **Install** → forced close of anything
running → progress bar → "updated successfully, no restart required."

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```

**Want to see the restart-prompt UI itself**, independent of any real exit
code? Run this directly (module already imported by the session):
```powershell
Show-ADTInstallationRestartPrompt -CountdownSeconds 30 -CountdownNoHideSeconds 15
```

## Verify

**Log file:**
```
C:\Windows\Logs\Software\NodeJSUpgrade.log
```

**Registry marker:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\NodeJSUpgrade'
```

**App detection:**
```powershell
Import-Module '.\PSAppDeployToolkit\PSAppDeployToolkit.psd1' -Force
Get-ADTApplication -Name 'Node.js' -NameMatch Contains
```
