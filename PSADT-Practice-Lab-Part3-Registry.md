# PSADT v4.1.x Practice Lab — Part 3: Registry

Verified against your local module (`PSAppDeployToolkit 4.1.8`). Same workflow:
paste each exercise into `Install-ADTDeployment`'s
`## <Perform Pre-Installation tasks here>` section, run:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

**Safety note:** every exercise below uses `HKCU:\Software\PSADT-Practice` —
a throwaway key under *your own user hive*. It needs no admin rights and is
safe to create/delete freely. Never practice against real product/uninstall
registry keys.

**⚠️ Important gotcha confirmed on your installed version:** the four
cmdlets are **not parameter-symmetric**:

| Cmdlet | Path parameter(s) |
|---|---|
| `Get-ADTRegistryKey` | `-Path` **or** `-LiteralPath` |
| `Set-ADTRegistryKey` | `-LiteralPath` **only** (no `-Path`) |
| `Remove-ADTRegistryKey` | `-Path` **or** `-LiteralPath` |
| `Test-ADTRegistryValue` | `-Key` (its own name, not `-Path`) |

Get this wrong and you'll get a "parameter cannot be found" error, not a
silent failure — but it trips people up, so it's worth drilling deliberately.

---

## Exercise 1 — Basic write and read

```powershell
$practiceKey = 'HKCU:\Software\PSADT-Practice'

Set-ADTRegistryKey -LiteralPath $practiceKey -Name 'FirstValue' -Value 'Hello Registry' -Type String

$readBack = Get-ADTRegistryKey -Path $practiceKey -Name 'FirstValue'
Show-ADTInstallationPrompt -Message "Wrote and read back: $readBack" -ButtonRightText 'OK'
```

**Notice:** `Set-ADTRegistryKey` creates the key path automatically if it
doesn't exist yet — you don't need a separate "create key" step.

---

## Exercise 2 — Value types, driven by a loop

**Goal:** practice `[Microsoft.Win32.RegistryValueKind]` types PSADT accepts:
`String`, `ExpandString`, `Binary`, `DWord`, `MultiString`, `QWord`, `None`.

```powershell
$practiceKey = 'HKCU:\Software\PSADT-Practice'

$values = @(
    @{ Name = 'AppLabel';    Value = 'Contoso Viewer';               Type = 'String' }
    @{ Name = 'InstallPath'; Value = '%ProgramFiles%\Contoso';        Type = 'ExpandString' }
    @{ Name = 'RetryCount';  Value = 3;                               Type = 'DWord' }
    @{ Name = 'Features';    Value = @('Core', 'Plugins', 'Updater'); Type = 'MultiString' }
)

foreach ($v in $values) {
    Set-ADTRegistryKey -LiteralPath $practiceKey -Name $v.Name -Value $v.Value -Type $v.Type
    Write-ADTLogEntry -Message "Set $($v.Name) ($($v.Type)) = $($v.Value)" -Source 'RegistryPractice'
}

$installPath = Get-ADTRegistryKey -Path $practiceKey -Name 'InstallPath'
$features    = Get-ADTRegistryKey -Path $practiceKey -Name 'Features'

Show-ADTInstallationPrompt -Message "InstallPath (expanded): $installPath`nFeatures: $($features -join ', ')" -ButtonRightText 'OK'
```

**Notice:** `Get-ADTRegistryKey` expands `%ProgramFiles%`-style
`ExpandString` values automatically. Add `-DoNotExpandEnvironmentNames` if
you ever need the raw, unexpanded string back.

---

## Exercise 3 — `Test-ADTRegistryValue`: a "first run" marker pattern

**Goal:** the classic use case — check whether something has already run,
using a condition on `Test-ADTRegistryValue`'s boolean result.

```powershell
$practiceKey  = 'HKCU:\Software\PSADT-Practice'
$alreadyRan   = Test-ADTRegistryValue -Key $practiceKey -Name 'FirstRunComplete'

if ($alreadyRan) {
    Write-ADTLogEntry -Message 'FirstRunComplete marker found — this is a repeat run.' -Severity Warning
    Show-ADTInstallationPrompt -Message 'Marker found: this looks like a repeat run.' -ButtonRightText 'OK' -Icon Warning
}
else {
    Write-ADTLogEntry -Message 'No marker found — treating as first run.'
    Set-ADTRegistryKey -LiteralPath $practiceKey -Name 'FirstRunComplete' -Value 1 -Type DWord
    Show-ADTInstallationPrompt -Message 'No marker found. Marker has now been written — run this exercise again to see the other branch.' -ButtonRightText 'OK'
}
```

**Try it twice in a row** — first run takes the `else` branch and writes the
marker; second run takes the `if` branch. This exact pattern is how real
deployments detect "has this machine already been configured."

---

## Exercise 4 — Checking the key itself, not just a value (`-ReturnEmptyKeyIfExists`)

**Goal:** sometimes you need to know a *key* exists even if it has no named
values under it yet — `Get-ADTRegistryKey` without `-Name` normally returns
the value names/data as a hashtable-like object, but an empty key returns
`$null` unless you ask otherwise.

```powershell
$emptyKeyPath = 'HKCU:\Software\PSADT-Practice\EmptyMarkerKey'
New-Item -Path $emptyKeyPath -Force | Out-Null   # plain PowerShell, just to create an empty key for this test

$normalResult = Get-ADTRegistryKey -Path $emptyKeyPath
$forcedResult = Get-ADTRegistryKey -Path $emptyKeyPath -ReturnEmptyKeyIfExists

Show-ADTInstallationPrompt -Message "Without -ReturnEmptyKeyIfExists: $(if ($null -eq $normalResult) { '<null>' } else { $normalResult })`nWith -ReturnEmptyKeyIfExists: $(if ($null -eq $forcedResult) { '<null>' } else { 'key object returned' })" -ButtonRightText 'OK'
```

**Notice:** use `-ReturnEmptyKeyIfExists` when your condition needs to
distinguish "key exists but is empty" from "key doesn't exist at all" —
without it, both cases look identical (`$null`).

---

## Exercise 5 — Cleanup: `Remove-ADTRegistryKey`, conditionally

**Goal:** only remove something if your marker condition says it's safe to.

```powershell
$practiceKey = 'HKCU:\Software\PSADT-Practice'

if (Test-ADTRegistryValue -Key $practiceKey -Name 'FirstRunComplete') {
    Remove-ADTRegistryKey -Path $practiceKey -Name 'FirstRunComplete'
    Write-ADTLogEntry -Message 'Removed FirstRunComplete marker.'
}

# Full cleanup of everything from this lab, including subkeys:
Remove-ADTRegistryKey -Path $practiceKey -Recurse -ErrorAction SilentlyContinue
Write-ADTLogEntry -Message 'Removed entire HKCU:\Software\PSADT-Practice tree.'

Show-ADTInstallationPrompt -Message 'Practice registry keys cleaned up.' -ButtonRightText 'OK'
```

**Notice:** `-Recurse` is required to delete a key that still has subkeys —
without it, `Remove-ADTRegistryKey` only removes a key that's already empty
(or a single named value, if you pass `-Name`).

---

## Exercise 6 (advanced) — `-Wow6432Node`: the 32-bit registry view

**Goal:** understand when you need this switch.

On 64-bit Windows, 32-bit applications write their `HKLM\SOFTWARE\...` keys
under the redirected `HKLM\SOFTWARE\WOW6432Node\...` path instead. If you're
checking/writing settings for a 32-bit app, add `-Wow6432Node` so PSADT reads
from (or writes to) the correct redirected location instead of the native
64-bit one.

```powershell
# Read a real example: most 32-bit apps register their uninstall info under WOW6432Node.
Get-ADTRegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -Wow6432Node -ErrorAction SilentlyContinue |
    Select-Object -First 1
```

**Notice:** this only matters on 64-bit OS with a 32-bit target app. If
you're unsure whether a value is native or redirected, check both — with and
without `-Wow6432Node` — while troubleshooting.

---

## Exercise 7 (advanced) — `-SID`: acting on another user's hive

**Goal:** understand the pattern (read-only here — don't write to another
user's hive during practice).

`-SID` lets registry cmdlets target a specific user's `HKEY_USERS\<SID>\...`
hive instead of the current process's `HKCU`. This is how PSADT reaches
per-user settings for *all* logged-on users, not just the account running
the deployment (which, for SYSTEM-context deployments, has no meaningful
`HKCU` of its own).

```powershell
foreach ($profile in Get-ADTUserProfiles) {
    $hasMarker = Test-ADTRegistryValue -Key 'Software\PSADT-Practice' -Name 'FirstRunComplete' -SID $profile.SID -ErrorAction SilentlyContinue
    Write-ADTLogEntry -Message "User $($profile.NTAccount) (SID $($profile.SID)): marker present = $hasMarker"
}
```

**Notice:** the loop + `-SID` combination is exactly how you'd apply a
per-user registry setting to every real profile on a machine, not just
whoever happens to be logged in when your script runs.

---

## Capstone — First-run marker + per-setting logging, all together

```powershell
$practiceKey = 'HKCU:\Software\PSADT-Practice'

$settings = @(
    @{ Name = 'AppLabel';   Value = 'Contoso Viewer'; Type = 'String' }
    @{ Name = 'RetryCount'; Value = 3;                Type = 'DWord' }
)

if (Test-ADTRegistryValue -Key $practiceKey -Name 'ConfigApplied') {
    Write-ADTLogEntry -Message 'Configuration already applied — skipping.' -Severity Warning
    Show-ADTInstallationPrompt -Message 'Already configured (marker found). Run Exercise 5''s cleanup to reset and try again.' -ButtonRightText 'OK' -Icon Warning
}
else {
    foreach ($setting in $settings) {
        Set-ADTRegistryKey -LiteralPath $practiceKey -Name $setting.Name -Value $setting.Value -Type $setting.Type
        Write-ADTLogEntry -Message "Applied setting: $($setting.Name) = $($setting.Value)" -Severity Success -Source 'ConfigApply'
    }
    Set-ADTRegistryKey -LiteralPath $practiceKey -Name 'ConfigApplied' -Value 1 -Type DWord
    Show-ADTInstallationPrompt -Message "Applied $($settings.Count) setting(s) and wrote the completion marker." -ButtonRightText 'OK'
}
```

---

## Next up

**Part 4 — Detecting installed apps / product codes** (`Get-ADTApplication`)
is next: `PSADT-Practice-Lab-Part4-AppDetection.md`.
