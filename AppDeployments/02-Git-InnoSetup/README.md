# Git for Windows — PSADT Deployment

Silent install/uninstall of Git for Windows 2.45.2, an Inno Setup–built EXE.

## What this does

- Checks whether Git Bash is currently running (`Get-ADTRunningProcesses`) and only shows a close-apps prompt if it actually is — `Show-ADTInstallationWelcome -CloseProcesses` with a 60-second countdown and the option to defer up to 3 times.
- Detects any existing Git install first (`Get-ADTApplication -Name 'Git' -NameMatch Contains`) and logs what it finds.
- Installs via `Start-ADTProcess` with `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` — the standard Inno Setup silent-install convention, confirmed by scanning this exact installer's binary for the "Inno Setup" signature string (not guessed from the app name).
- Confirms the install afterward and records the version under a registry marker, along with the app's own recorded uninstall command for reference.
- Uninstalls using the app's own `QuietUninstallStringFilePath`/`QuietUninstallStringArgumentList` (read from `Get-ADTApplication`) rather than a hardcoded path — falls back to the known Inno switches on `UninstallStringFilePath` if that's ever missing.
- `Repair-ADTDeployment` re-runs the installer with the same silent switches.

**One thing worth verifying on your machine:** the detection call uses `-NameMatch Contains` deliberately, since Inno Setup's default `DisplayName` for this installer is normally `Git version 2.45.2`. After your first real install, run the detection command below and consider tightening the script to `-NameMatch Exact` with the precise string you see.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher. Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, the Inno Setup switches, detection name, process to watch. **This is the file you edit.**
- `InstallLogic.ps1` — the standard install/uninstall/repair pattern, written generically against the config values above. Same file, unmodified, across every simple single-app package in this set.

## Test it

```powershell
cd "AppDeployments\02-Git-InnoSetup"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```

## Verify

**Log file:**
```
C:\Windows\Logs\Software\Git.log
```

**Registry marker:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\Git'
```

**App detection — and the exact DisplayName check mentioned above:**
```powershell
Import-Module '.\PSAppDeployToolkit\PSAppDeployToolkit.psd1' -Force
Get-ADTApplication -Name 'Git' -NameMatch Contains | Select-Object DisplayName, DisplayVersion, QuietUninstallString
```

**Outside PSADT:**
```powershell
git --version
```
