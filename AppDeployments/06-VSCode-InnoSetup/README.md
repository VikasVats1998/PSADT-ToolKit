# Visual Studio Code — PSADT Deployment

Silent install/uninstall of VS Code 1.114.0, an Inno Setup–built EXE, with a
real close/block flow since VS Code is realistically an app people leave
open.

## What this does

- Checks whether VS Code is currently running (`Get-ADTRunningProcesses` against the `Code` process) and only shows a close-apps prompt if it actually is.
- If running: `Show-ADTInstallationWelcome -CloseProcesses -BlockExecution` — closes it and blocks it from being relaunched until the install finishes.
- Detects any existing install first (`Get-ADTApplication -Name 'Visual Studio Code' -NameMatch Contains`) and logs what it finds.
- Installs via `Start-ADTProcess` with `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-` — the standard Inno Setup silent-install convention, confirmed by scanning this exact installer's binary for the "Inno Setup" signature string.
- Unblocks execution and confirms the install afterward, recording the version under a registry marker.
- Uninstalls using the app's own `QuietUninstallStringFilePath`/`QuietUninstallStringArgumentList`, falling back to the known Inno switches if that's ever missing.
- `Repair-ADTDeployment` re-runs the installer with the same silent switches.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher. Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, the Inno Setup switches, the process to close/block, detection name. **This is the file you edit.**
- `InstallLogic.ps1` — the standard install/uninstall/repair pattern (including the close/block logic), written generically against the config values above. Same file, unmodified, across every simple single-app package in this set.

## Test it

Open VS Code first to see the close/block flow:
```powershell
cd "AppDeployments\06-VSCode-InnoSetup"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```

## Verify

**Log file:**
```
C:\Windows\Logs\Software\VSCode.log
```

**Registry marker:**
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\VSCode'
```

**App detection:**
```powershell
Import-Module '.\PSAppDeployToolkit\PSAppDeployToolkit.psd1' -Force
Get-ADTApplication -Name 'Visual Studio Code' -NameMatch Contains
```

## Note on install switches

VS Code's Inno Setup installer specifically supports `/MERGETASKS` to
control optional tasks — e.g. `/VERYSILENT /NORESTART /MERGETASKS=!runcode`
skips the "Open with Code" context-menu entry. Adjust `$InstallArgs` in
`AppConfig.ps1` if you want different defaults.
