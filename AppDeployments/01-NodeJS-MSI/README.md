# Node.js — PSADT Deployment

Silent install/uninstall of Node.js 24.14.1 via its official MSI.

## What this does

- Detects whether Node.js is already installed (`Get-ADTApplication`) and logs the outcome before proceeding.
- Installs via `Start-ADTMsiProcess -Action Install`, using the MSI in `Files\node-v24.14.1-x64.msi`. Silence comes from `Config\config.psd1`'s `MSI.SilentParams = 'REBOOT=ReallySuppress /QN'` — no guessed switches needed, this is the standard MSI path.
- Confirms the install afterward with a second `Get-ADTApplication` check, and records the result (version, ProductCode) under a registry marker.
- Uninstalls via `Start-ADTMsiProcess -Action Uninstall -FilePath $existingApp.ProductCode` — using the real ProductCode PSADT detected, not a hardcoded GUID.
- `Repair-ADTDeployment` re-runs the MSI with `-Action Repair`.

Node.js has no persistent background process, so no close/block logic is used here.

## File layout

- `Invoke-AppDeployToolkit.ps1` — stock PSADT launcher (param block, module import, session open/close). Not app-specific, don't edit.
- `AppConfig.ps1` — everything that changes per app: `$adtSession` values, the installer filename/type, detection name, process to watch. **This is the file you edit.**
- `InstallLogic.ps1` — the standard `Install-ADTDeployment` / `Uninstall-ADTDeployment` / `Repair-ADTDeployment` pattern, written generically against the config values above. Same file, unmodified, across every simple single-app package in this set — don't edit it per app.

## Test it

```powershell
cd "AppDeployments\01-NodeJS-MSI"
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive
```
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```

## Verify

**Log file** (every run appends to the same file):
```
C:\Windows\Logs\Software\NodeJS.log
```

**Registry marker** (written by this package, separate from Node's own registration):
```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\PSADT-Practice\NodeJS'
```
Expect `InstallCompleted = 1`, `InstalledVersion`, `InstalledProductCode`, `InstallDate` after install; the whole key is removed after uninstall.

**App detection:**
```powershell
Import-Module '.\PSAppDeployToolkit\PSAppDeployToolkit.psd1' -Force
Get-ADTApplication -Name 'Node.js' -NameMatch Contains
```

**Outside PSADT:**
```powershell
node --version
```
