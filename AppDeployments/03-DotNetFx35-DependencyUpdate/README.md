# .NET Framework 3.5 — PSADT Shared-Dependency Update

Models a shared-dependency update workflow, not a plain "install this app"
package: detect whether the dependency needs installing → detect which apps
depend on it → confirm with the user (naming what needs to close) →
forcefully close those apps → install → check if a restart is needed → show
the right final message.

## What this does

- **Detects the dependency itself via the registry** (`Test-ADTRegistryValue` / `Get-ADTRegistryKey` against `HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5\Install`), not `Get-ADTApplication` — confirmed on the machine this was built on that .NET Framework 3.5 does **not** create a normal Add/Remove Programs entry, since it's a Windows feature, not a traditional MSI app.
- **Detects which example dependent apps are currently running** (`Get-ADTRunningProcesses`) — Notepad and Notepad++ are used as illustrative stand-ins. Windows has no API that tells you which arbitrary desktop apps require .NET Framework 3.5; a real deployment maintains this list from its own app inventory or vendor documentation.
- **Shows a confirmation prompt** naming the dependency and listing which dependent apps need to close, with **Install** / **Cancel** buttons.
- **Forcefully closes** any running dependent apps if the user proceeds — `Show-ADTInstallationWelcome -CloseProcesses -BlockExecution`, deliberately with no `-AllowDefer`, since this models a mandatory update rather than an optional app install.
- **Installs** via `Start-ADTProcess` with `/q /norestart` — Microsoft's own officially documented silent-install switches for this exact offline installer.
- **Checks the real exit code** (captured via `Start-ADTProcess -PassThru`, a confirmed `.ExitCode` field) against `$adtSession.AppRebootExitCodes` (1641/3010) to decide whether to show a restart-required message followed by the actual `Show-ADTInstallationRestartPrompt` countdown UI, or a plain "no restart required" summary.
- **Does not implement a real uninstall.** .NET Framework 3.5 is a Windows feature — removing it requires DISM (`Disable-WindowsOptionalFeature`), a different and more invasive operation that can break other software still relying on it. `Uninstall-ADTDeployment` here only cleans up this package's own practice registry markers and says so explicitly; this is an honest limitation, not a placeholder.

## Confirmed silent-mode-safe

This was actually tested, not assumed. `Show-ADTInstallationPrompt` returns
`$null` under `-DeployMode Silent` (verified: `"Bypassing
Show-ADTInstallationPrompt [Mode: Silent]"` in the log) rather than either
button's text, since nobody's there to click anything. The confirmation
prompt's gate is `if ($proceed -eq 'Cancel')` — **not** `-ne 'Install'` —
specifically so that a real silent run (where `$proceed` is `$null`) falls
through and proceeds instead of being mistaken for a cancellation.
`Show-ADTInstallationRestartPrompt` was also confirmed to skip forcing a
restart in Silent mode (`"Skipping restart because the deploy mode is set
to [Silent]"`) — the real restart, in a real silent deployment, is driven
by the exit code `Close-ADTSession` passes back to the parent process
(SCCM/Intune), which orchestrates the reboot on its own schedule.

## The `$forcePracticeRun` toggle

.NET Framework 3.5 is already installed on most dev machines. In a real
deployment that means this package should detect it's already satisfied and
skip straight past everything. `AppConfig.ps1` has
`$ForcePracticeRun = $true`, which forces the full flow to run
anyway so you can see it. Set it to `$false` to see the realistic
"already satisfied, doing nothing" behavior instead.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher. Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, detection method/path, install switches, the dependent-app list, `$ForcePracticeRun`, `$SupportsUninstall`. **This is the file you edit.**
- `DependencyUpdateLogic.ps1` — the standard detect → confirm → close → install → restart pattern, written generically against the config values above. Same file, unmodified, across every dependency-update package in this set.

## Test it

```powershell
cd "AppDeployments\03-DotNetFx35-DependencyUpdate"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

**What you should see, in order:** a prompt naming the dependency and
listing which example dependent apps are currently running (open Notepad
first to see this populated) → **Install** or **Cancel** → if anything was
running, the forced close-apps screen with a 20-second countdown → progress
bar → a final "installed successfully" message (with or without a restart
prompt, depending on whether Windows determines one is needed).

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```
(cleans up this package's own registry markers only — see above)

## Verify

**Log file:**
```
C:\Windows\Logs\Software\DotNetFx35.log
```

**Registry marker:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\DotNetFx35'
```

**The real dependency state:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' | Select-Object Version, Install, SP
```
