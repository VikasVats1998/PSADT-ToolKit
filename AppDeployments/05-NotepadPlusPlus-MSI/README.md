# Notepad++ — PSADT Deployment

Silent install/uninstall of Notepad++ 8.9.8 via its MSI build, with a real
close/block flow since Notepad++ is realistically an app people leave open.

## What this does

- Checks whether Notepad++ is currently running (`Get-ADTRunningProcesses`) and only shows a close-apps prompt if it actually is.
- If running: `Show-ADTInstallationWelcome -CloseProcesses -BlockExecution` — a 60-second countdown to close it, then blocks it from being relaunched until the install finishes. If not running: just checks disk space and proceeds, no prompt.
- Detects any existing install first (`Get-ADTApplication -Name 'Notepad++' -NameMatch Contains`) and logs what it finds.
- Installs via `Start-ADTMsiProcess -Action Install`, using the MSI in `Files\`. Silence comes from `Config\config.psd1`'s `MSI.SilentParams`.
- **Confirmed by reading the MSI's own Property table directly** (via `Get-ADTMsiTableProperty`, no install performed): `ProductName = 'Notepad++ (x64)'`, `Manufacturer = 'Notepad++ team (MSI installer)'`, `ProductVersion = '8.9.8'`, `ProductCode = {224C0E17-FB79-4AE2-9A47-5556FCEF39C4}`. The maintainers deliberately label this build's `Manufacturer` field to be distinguishable from their separate NSIS EXE installer in Add/Remove Programs.
- Unblocks execution and confirms the install afterward, recording the version under a registry marker.
- Uninstalls via `Start-ADTMsiProcess -Action Uninstall -FilePath $existingApp.ProductCode`.
- `Repair-ADTDeployment` re-runs the MSI with `-Action Repair`.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher. Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, the process to close/block, detection name. **This is the file you edit.**
- `InstallLogic.ps1` — the standard install/uninstall/repair pattern (including the close/block logic), written generically against the config values above. Same file, unmodified, across every simple single-app package in this set.

## Test it

Open Notepad++ before either run to see the close/block flow:
```powershell
cd "AppDeployments\05-NotepadPlusPlus-MSI"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```

## Verify

**Log file:**
```
C:\Windows\Logs\Software\NotepadPlusPlus-MSI.log
```

**Registry marker:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\NotepadPlusPlusMSI'
```

**App detection — the MSI branch in action:**
```powershell
Import-Module '.\PSAppDeployToolkit\PSAppDeployToolkit.psd1' -Force
Get-ADTApplication -Name 'Notepad++' -NameMatch Contains | Select-Object DisplayName, Publisher, WindowsInstaller, ProductCode
```
`WindowsInstaller` should be `$true` and `ProductCode` populated — that's
what this package's `Uninstall-ADTDeployment` checks to decide it can
uninstall via `Start-ADTMsiProcess` rather than needing an EXE's
`QuietUninstallString`.
