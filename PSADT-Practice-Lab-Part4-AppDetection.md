# PSADT v4.1.x Practice Lab — Part 4: Detecting Installed Apps / Product Codes

Verified against your local module (`PSAppDeployToolkit 4.1.8`) — including a
live test of `Get-ADTApplication`'s actual return object on this machine, so
the property names below are confirmed real, not assumed. Same workflow:
paste each exercise into `Install-ADTDeployment`'s
`## <Perform Pre-Installation tasks here>` section, run:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

This is read-only detection work — nothing here installs, uninstalls, or
modifies anything, so it's safe to run repeatedly.

**Practice target:** use **"Microsoft Edge"** or **"Edge"** throughout — it's
built into Windows and virtually guaranteed to be present, so every exercise
below will actually return a match on your machine. Swap in any app you know
is installed if you prefer.

---

## What `Get-ADTApplication` actually returns

One object per matched app, confirmed fields (this is the real shape, from a
live query):

```
DisplayName, DisplayVersion, ProductCode, Publisher,
UninstallString, UninstallStringFilePath, UninstallStringArgumentList,
QuietUninstallString, QuietUninstallStringFilePath, QuietUninstallStringArgumentList,
InstallSource, InstallLocation, InstallDate,
EstimatedSize, SystemComponent, WindowsInstaller, Is64BitApplication,
HelpLink, PSPath, PSParentPath, PSChildName
```

Two fields matter most for deployment logic:
- **`ProductCode`** — only populated for real MSI installs (`WindowsInstaller = $true`). EXE-based installers (InstallShield, Inno Setup, NSIS, etc.) leave this empty — you uninstall those via `UninstallString`/`QuietUninstallString` instead.
- **`WindowsInstaller`** — tells you which of the above situations you're in, without needing to check `ProductCode` for `$null` yourself.

---

## Exercise 1 — Basic search

```powershell
$apps = Get-ADTApplication -Name 'Edge' -NameMatch Contains

if ($apps) {
    foreach ($app in $apps) {
        Write-ADTLogEntry -Message "Found: $($app.DisplayName) v$($app.DisplayVersion)"
    }
    Show-ADTInstallationPrompt -Message "Found $($apps.Count) match(es). See log for details." -ButtonRightText 'OK'
}
else {
    Show-ADTInstallationPrompt -Message 'No matches found.' -ButtonRightText 'OK' -Icon Warning
}
```

**Notice:** `Get-ADTApplication` can return **zero, one, or many** objects —
always test for `$null`/empty before assuming `$apps.DisplayVersion` will
work, and loop (`foreach`) rather than assume a single result.

---

## Exercise 2 — `-NameMatch` modes

**Goal:** practice all four matching strategies on the same target.

```powershell
foreach ($mode in 'Contains', 'Wildcard', 'Regex', 'Exact') {
    $pattern = switch ($mode) {
        'Contains' { 'Edge' }
        'Wildcard' { 'Microsoft Edge*' }
        'Regex'    { '^Microsoft Edge' }
        'Exact'    { 'Microsoft Edge' }
    }
    $result = Get-ADTApplication -Name $pattern -NameMatch $mode -ErrorAction SilentlyContinue
    Write-ADTLogEntry -Message "NameMatch=$mode, Pattern='$pattern' -> $($result.Count) match(es)"
}
```

**Notice:** `Exact` is strict — capitalization/spacing must match the
registry's `DisplayName` precisely, so it's the most likely to return zero
results if you guess the name slightly wrong. `Contains` is the most
forgiving and what you'll reach for most often.

---

## Exercise 3 — MSI vs EXE branch (`WindowsInstaller` / `ProductCode`)

**Goal:** the condition every real "detect, then uninstall/upgrade" script
needs.

```powershell
$apps = Get-ADTApplication -Name 'Edge' -NameMatch Contains -ErrorAction SilentlyContinue

foreach ($app in $apps) {
    if ($app.WindowsInstaller -and $app.ProductCode) {
        Write-ADTLogEntry -Message "$($app.DisplayName): MSI-based, ProductCode = $($app.ProductCode)"
        # Real uninstall would use: Start-ADTMsiProcess -Action Uninstall -FilePath $app.ProductCode
    }
    else {
        Write-ADTLogEntry -Message "$($app.DisplayName): EXE-based, QuietUninstallString = $($app.QuietUninstallStringFilePath) $($app.QuietUninstallStringArgumentList)"
        # Real uninstall would use: Start-ADTProcess -FilePath $app.QuietUninstallStringFilePath -ArgumentList $app.QuietUninstallStringArgumentList
    }
}
```

**Notice:** this `if/else` is the actual decision point that determines
*which* uninstall cmdlet family you'd call — get this branch wrong and you'd
try to feed an EXE path to an MSI-only cmdlet (or vice versa).

---

## Exercise 4 — Looking up by a known `ProductCode`

**Goal:** once you already know an app's GUID (from vendor docs, or from a
prior `Get-ADTApplication` run), query it directly — much faster and more
precise than a name search.

```powershell
# First, discover a real ProductCode on this machine to use as our practice input:
$sample = Get-ADTApplication -ApplicationType MSI | Select-Object -First 1

if ($sample) {
    $byCode = Get-ADTApplication -ProductCode $sample.ProductCode
    Show-ADTInstallationPrompt -Message "Looked up by ProductCode:`n$($byCode.DisplayName)" -ButtonRightText 'OK'
}
else {
    Show-ADTInstallationPrompt -Message 'No MSI-installed apps found to demo this with.' -ButtonRightText 'OK' -Icon Warning
}
```

**Notice:** `-ProductCode` accepts an array (`guid[]`) — you can pass several
GUIDs in one call if you're checking for any of a known set of versions.

---

## Exercise 5 (advanced) — `-FilterScript`: custom logic, e.g. version comparison

**Goal:** combine detection with a condition PSADT doesn't have a built-in
parameter for — here, "installed but older than X."

```powershell
$minVersion = [Version]'100.0.0.0'

$outdated = Get-ADTApplication -Name 'Edge' -NameMatch Contains -FilterScript {
    param($App)
    try { [Version]$App.DisplayVersion -lt $minVersion } catch { $false }
}

if ($outdated) {
    foreach ($app in $outdated) {
        Write-ADTLogEntry -Message "$($app.DisplayName) v$($app.DisplayVersion) is older than $minVersion — would trigger upgrade." -Severity Warning
    }
}
else {
    Write-ADTLogEntry -Message 'No outdated matches — installed version(s) already meet the minimum.'
}
```

**Notice:** `-FilterScript` runs *after* the name/type filters, on each
candidate app object — use it for anything version/publisher/size-based that
the simpler parameters can't express directly. Wrap the version cast in
`try/catch` since not every `DisplayVersion` string is guaranteed to parse
as `[Version]`.

---

## Exercise 6 (advanced) — `-IncludeUpdatesAndHotfixes`

```powershell
$withoutHotfixes = Get-ADTApplication -Name 'Microsoft' -NameMatch Contains
$withHotfixes     = Get-ADTApplication -Name 'Microsoft' -NameMatch Contains -IncludeUpdatesAndHotfixes

Write-ADTLogEntry -Message "Without hotfixes: $($withoutHotfixes.Count) result(s). With hotfixes: $($withHotfixes.Count) result(s)."
```

**Notice:** by default, PSADT filters out Windows Update/KB entries so a
broad name search doesn't drown in hotfix noise — only add
`-IncludeUpdatesAndHotfixes` if you specifically need to detect a KB.

---

## Capstone — "Required apps" detection sweep

**Goal:** the shape of a real pre-install prerequisite check: loop over a
list of required apps, detect each, log + collect results, summarize.

```powershell
$required = @('Edge', 'PowerShell', 'This App Does Not Exist 12345')
$found    = @()
$missing  = @()

foreach ($name in $required) {
    $match = Get-ADTApplication -Name $name -NameMatch Contains -ErrorAction SilentlyContinue

    if ($match) {
        $found += $name
        Write-ADTLogEntry -Message "Prerequisite check: '$name' -> FOUND ($($match.Count) match(es))" -Severity Success
    }
    else {
        $missing += $name
        Write-ADTLogEntry -Message "Prerequisite check: '$name' -> MISSING" -Severity Warning
    }
}

$summary = "Found: $($found.Count)/$($required.Count)`nMissing: $($missing -join ', ')"

if ($missing.Count -gt 0) {
    Show-ADTInstallationPrompt -Message $summary -ButtonRightText 'OK' -Icon Warning
}
else {
    Show-ADTInstallationPrompt -Message $summary -ButtonRightText 'OK' -Icon Information
}
```

---

## Next up

**Part 5 — Closing / blocking running applications for real**
(`Get-ADTRunningProcesses`, `Block-ADTAppExecution`, `Unblock-ADTAppExecution`)
is next: `PSADT-Practice-Lab-Part5-CloseBlockApps.md`.
