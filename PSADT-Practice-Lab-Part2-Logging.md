# PSADT v4.1.x Practice Lab — Part 2: Logging (`Write-ADTLogEntry`)

Verified against your local module (`PSAppDeployToolkit 4.1.8`) and your
`PSAppDeployToolkit\Config\config.psd1`. Same workflow as Part 1: paste each
exercise into `Install-ADTDeployment`'s `## <Perform Pre-Installation tasks here>`
section in `Invoke-AppDeployToolkit.ps1`, then run:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

---

## Where your logs actually go

Your config (`Config\config.psd1`) sets:

```
Toolkit.LogPath              = '$envWinDir\Logs\Software'          # used when RequireAdmin = $true
Toolkit.LogPathNoAdminRights = '$envProgramData\Logs\Software'      # used when RequireAdmin = $false
Toolkit.LogStyle             = 'CMTrace'
Toolkit.LogAppend            = $true
Toolkit.LogMaxHistory        = 10
Toolkit.LogMaxSize           = 10   # MB
Toolkit.LogWriteToHost       = $true
```

Your template's `$adtSession.RequireAdmin = $true`, so in practice your logs land
under `C:\Windows\Logs\Software`. But don't take my word for it — the session
object already knows its own exact path at runtime:

```powershell
Show-ADTInstallationPrompt -Message "Log folder : $($adtSession.LogPath)`nLog file   : $($adtSession.LogName)" -ButtonRightText 'OK'
```

Run that first, note the path, and keep a File Explorer window open on that
folder while you do the rest of this lab — you'll watch the `.log` file grow
live. `LogStyle = 'CMTrace'` means the file is best read with the free
**CMTrace.exe** / **OneTrace** viewer (color-codes warnings/errors), but plain
Notepad works fine too.

---

## Exercise 1 — The simplest possible log entry

```powershell
Write-ADTLogEntry -Message 'Hello from my first practice log entry.'
```

**Try it:** run it, then open the log file from the path Exercise 0 gave you.
Find your line. Notice it already has a timestamp, component name, and thread
info added automatically — you only supply `-Message`.

---

## Exercise 2 — Severity levels

`Write-ADTLogEntry -Severity` accepts a named enum, backed by these integers:

| Name | Value | Meaning |
|---|---|---|
| `Success` | 0 | explicit success marker |
| `Info` | 1 | default — normal progress |
| `Warning` | 2 | something recoverable/notable |
| `Error` | 3 | something failed |

```powershell
Write-ADTLogEntry -Message 'Practice: this is a Success entry.' -Severity Success
Write-ADTLogEntry -Message 'Practice: this is an Info entry (also the default).' -Severity Info
Write-ADTLogEntry -Message 'Practice: this is a Warning entry.'  -Severity Warning
Write-ADTLogEntry -Message 'Practice: this is an Error entry.'   -Severity Error
```

**Notice:** open the log in CMTrace/OneTrace if you have it — Warning shows
yellow, Error shows red. In a plain text editor you'll just see the severity
number embedded in the CMTrace-format line. `-Severity` also accepts the raw
integer (`-Severity 3`) since the enum is backed by `Int32`.

**Challenge:** loop over all four severities instead of writing them by hand:

```powershell
foreach ($sev in [enum]::GetNames([PSADT.Module.LogSeverity])) {
    Write-ADTLogEntry -Message "Looped severity: $sev" -Severity $sev
}
```

---

## Exercise 3 — Tagging where a message came from (`-Source`)

**Goal:** use `-Source` to label log lines so you can tell which part of your
script wrote them — essential once your script gets long.

```powershell
Write-ADTLogEntry -Message 'Checking prerequisites...' -Source 'PrereqCheck'
Write-ADTLogEntry -Message 'Prerequisites OK.'          -Source 'PrereqCheck'
Write-ADTLogEntry -Message 'Copying config file...'     -Source 'ConfigDeploy'
```

**Notice:** without `-Source`, PSADT auto-fills the calling function's name.
Set it explicitly inside loops/helper blocks where the auto-detected name
would otherwise be the same generic caller for every line.

---

## Exercise 4 — Logging inside conditions and loops

**Goal:** the real pattern — log a decision, not just an action.

```powershell
$components = @('Core', 'LanguagePack', 'Plugins')

foreach ($component in $components) {
    Write-ADTLogEntry -Message "Starting install of component: $component" -Source 'ComponentLoop'

    if ($component -eq 'Plugins') {
        Write-ADTLogEntry -Message "$component is optional — skipping in this practice run." -Severity Warning -Source 'ComponentLoop'
        continue
    }

    Write-ADTLogEntry -Message "$component installed successfully." -Severity Success -Source 'ComponentLoop'
}
```

**Notice:** every branch of the `if` gets its own log line. When something
breaks in a real deployment weeks later, this is what tells you *which*
branch executed — the alternative is guessing.

---

## Exercise 5 — Try/Catch: logging real failures

**Goal:** practice the standard error-logging shape you'll reuse everywhere.

```powershell
try
{
    Write-ADTLogEntry -Message 'Attempting a deliberately broken command...' -Source 'PracticeFailure'
    Get-Item -LiteralPath 'C:\this\path\definitely\does\not\exist.txt' -ErrorAction Stop
}
catch
{
    Write-ADTLogEntry -Message "Practice failure caught: $($_.Exception.Message)" -Severity Error -Source 'PracticeFailure'
}
```

**Notice:** this is the same shape used in your template's own outer
`catch` block at the bottom of `Invoke-AppDeployToolkit.ps1` (it calls
`Resolve-ADTErrorRecord` for a fuller dump — try swapping `$_.Exception.Message`
for `(Resolve-ADTErrorRecord -ErrorRecord $_)` and compare the verbosity).

---

## Exercise 6 — A separate log file for one noisy section (`-LogFileDirectory` / `-LogFileName`)

**Goal:** redirect specific log entries to their own file — useful for
verbose troubleshooting output you don't want cluttering the main log.

```powershell
$debugLogDir = "$($adtSession.LogPath)\PracticeDebug"
New-ADTFolder -Path $debugLogDir -ErrorAction SilentlyContinue

for ($i = 1; $i -le 5; $i++) {
    Write-ADTLogEntry -Message "Verbose iteration $i of 5" `
        -LogFileDirectory $debugLogDir -LogFileName 'PracticeDebug.log'
}

Write-ADTLogEntry -Message "Verbose detail written separately to $debugLogDir\PracticeDebug.log"
```

**Notice:** the main session log only gets that last summary line — the loop's
noise lives in its own file, in its own folder.

---

## Exercise 7 — `PassThru`: log and return the message in one step

```powershell
$status = Write-ADTLogEntry -Message 'Practice: capturing this message as a variable too.' -PassThru
Show-ADTInstallationPrompt -Message "Just logged and captured:`n$status" -ButtonRightText 'OK'
```

**Notice:** handy when you want to log something *and* immediately reuse the
same text in a UI prompt without repeating the string.

---

## Capstone — Step tracker: progress UI + severity-aware logging + random failure

**Goal:** combine everything above with Part 1's progress-loop pattern.

```powershell
$steps = @('Check prerequisites', 'Copy files', 'Register components', 'Apply settings', 'Cleanup')
[Int32]$stepNum = 0
[Int32]$failures = 0

Show-ADTInstallationProgress -StatusMessage 'Starting practice deployment...' -StatusBarPercentage 0

foreach ($step in $steps) {
    $stepNum++
    $percent = [Int32]($stepNum / $steps.Count * 100)
    Show-ADTInstallationProgress -StatusMessage $step -StatusMessageDetail "Step $stepNum of $($steps.Count)" -StatusBarPercentage $percent
    Write-ADTLogEntry -Message "Step $stepNum/$($steps.Count): $step - starting" -Source 'StepTracker'

    Start-Sleep -Milliseconds 800

    # Randomly "fail" ~1 in 4 steps, to practice Warning/Error logging paths.
    if ((Get-Random -Maximum 4) -eq 0) {
        $failures++
        Write-ADTLogEntry -Message "Step $stepNum/$($steps.Count): $step - simulated failure" -Severity Error -Source 'StepTracker'
    }
    else {
        Write-ADTLogEntry -Message "Step $stepNum/$($steps.Count): $step - completed" -Severity Success -Source 'StepTracker'
    }
}

Close-ADTInstallationProgress

if ($failures -gt 0) {
    Write-ADTLogEntry -Message "Practice run finished with $failures simulated failure(s). See log for details." -Severity Warning
    Show-ADTInstallationPrompt -Message "Finished with $failures simulated failure(s).`nCheck the log at:`n$($adtSession.LogPath)\$($adtSession.LogName)" -ButtonRightText 'OK' -Icon Warning
}
else {
    Write-ADTLogEntry -Message 'Practice run finished with no failures.' -Severity Success
    Show-ADTInstallationPrompt -Message 'All steps completed successfully.' -ButtonRightText 'OK' -Icon Information
}
```

**Try it a few times** — since the failure is random, run it 3-4 times and
compare the log file between a clean run and one with failures. This is
exactly the shape of a real deployment: UI progress for the user, a
structured log for you.

---

## Next up

**Part 3 — Registry** (`Get/Set/Test/Remove-ADTRegistryKey`) is the next file:
`PSADT-Practice-Lab-Part3-Registry.md`.
