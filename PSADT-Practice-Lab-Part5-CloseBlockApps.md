# PSADT v4.1.x Practice Lab — Part 5: Closing / Blocking Running Applications

Verified against your local module (`PSAppDeployToolkit 4.1.8`). Same
workflow: paste each exercise into `Install-ADTDeployment`'s
`## <Perform Pre-Installation tasks here>` section, run:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

**Practice target throughout:** `notepad`. Open Notepad yourself before each
exercise so there's something real to detect/close/block. Never point these
exercises at an app you actually need running.

**⚠️ Safety rule for this file specifically:** `Block-ADTAppExecution`
prevents the target app from launching at all (Windows will show "this
program is blocked" if someone tries) until you call
`Unblock-ADTAppExecution` — or until `Close-ADTSession` runs, which
auto-unblocks everything as a safety net. Still, **always pair Block with an
explicit Unblock in the same exercise**, so you never leave a blocked app on
your real machine by accident (e.g. if you stop the script mid-debug with
Ctrl+C before it reaches the end).

---

## The shared type behind all of this: `ProcessDefinition`

`Get-ADTRunningProcesses -ProcessObjects`, `Block-ADTAppExecution -Processes`,
and `Show-ADTInstallationWelcome -CloseProcesses` (from Part 1) all accept
the **same underlying object shape** — confirmed on your module, it accepts
three forms:

```powershell
'notepad'                                        # plain name
@{ Name = 'notepad'; Description = 'Notepad' }    # name + friendly description
```

That's why, back in Part 1, `AppProcessesToClose = @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })`
worked as a mixed array — every cmdlet in this file understands the same two
forms.

---

## Exercise 1 — `Get-ADTRunningProcesses`: is it running right now?

Open Notepad, then:

```powershell
$running = Get-ADTRunningProcesses -ProcessObjects @('notepad')

if ($running) {
    Write-ADTLogEntry -Message "Detected running: $($running.ProcessName -join ', ')"
    Show-ADTInstallationPrompt -Message "Notepad is running (PID(s): $($running.ProcessId -join ', '))." -ButtonRightText 'OK'
}
else {
    Show-ADTInstallationPrompt -Message 'Notepad is not running.' -ButtonRightText 'OK' -Icon Warning
}
```

**Try it twice:** once with Notepad open, once with it closed — confirm the
`if`/`else` branch actually changes.

---

## Exercise 2 — Multiple targets with friendly descriptions, via a loop

```powershell
$targets = @(
    @{ Name = 'notepad'; Description = 'Notepad (practice target)' }
    @{ Name = 'calc';    Description = 'Calculator (practice target)' }
)

$running = Get-ADTRunningProcesses -ProcessObjects $targets

if ($running) {
    foreach ($proc in $running) {
        Write-ADTLogEntry -Message "Running: $($proc.ProcessDescription) [$($proc.ProcessName), PID $($proc.ProcessId)]"
    }
}
else {
    Write-ADTLogEntry -Message 'None of the practice targets are currently running.'
}
```

**Notice:** the returned objects carry the `Description` you supplied back
as `ProcessDescription` — this is what `Show-ADTInstallationWelcome` shows
the end user instead of a raw process name like `notepad.exe`.

---

## Exercise 3 — `Block-ADTAppExecution` + `Unblock-ADTAppExecution`

**Goal:** feel what "blocked" actually looks like from the user's side, then
release it — in the same run, every time.

```powershell
Show-ADTInstallationProgress -StatusMessage 'Blocking Notepad for the next 15 seconds — try opening it from the Start menu now...'

Block-ADTAppExecution -Processes @('notepad')
Write-ADTLogEntry -Message 'Notepad blocked.' -Source 'BlockPractice'

Start-Sleep -Seconds 15

Unblock-ADTAppExecution
Write-ADTLogEntry -Message 'Notepad unblocked.' -Source 'BlockPractice'

Close-ADTInstallationProgress
Show-ADTInstallationPrompt -Message 'Notepad is unblocked again — try opening it now, it should work.' -ButtonRightText 'OK'
```

**Try it:** during the 15-second window, try launching Notepad from the
Start menu — you should see Windows refuse/redirect it. After the
`Unblock-ADTAppExecution` line runs, confirm it opens normally again.

**Notice:** `Unblock-ADTAppExecution -Tasks` is optional — called with no
arguments (as above) it clears whatever this session blocked.

---

## Exercise 4 — Where this connects back to Part 1: `Show-ADTInstallationWelcome -BlockExecution`

**Goal:** see that the welcome dialog you practiced in Part 1 can do the
block/unblock dance for you automatically, instead of calling
`Block-`/`Unblock-ADTAppExecution` by hand.

Open Notepad, then:

```powershell
Show-ADTInstallationWelcome -CloseProcesses @('notepad') -BlockExecution -CloseProcessesCountdown 30
```

**Notice:** with `-BlockExecution`, once the user closes (or the countdown
auto-closes) Notepad, PSADT blocks it from being relaunched for the rest of
the deployment — automatically unblocked when `Close-ADTSession` runs at the
end of your script. This is the option to reach for in real deployments
instead of manually calling `Block-ADTAppExecution` yourself, unless you need
finer control over exactly when the block starts/ends.

---

## Exercise 5 (advanced) — Conditional welcome: only bother the user if something's actually running

**Goal:** combine `Get-ADTRunningProcesses` (a cheap check) with a condition,
so you only show the welcome/close dialog when there's genuinely something
to close — avoids an unnecessary prompt on machines where the app is already
closed.

```powershell
$targets = @('notepad', 'calc')
$running = Get-ADTRunningProcesses -ProcessObjects $targets

if ($running) {
    Write-ADTLogEntry -Message "Found $($running.Count) running target process(es) — showing welcome prompt." -Severity Warning
    Show-ADTInstallationWelcome -CloseProcesses $targets -BlockExecution -CloseProcessesCountdown 30
}
else {
    Write-ADTLogEntry -Message 'No target processes running — skipping welcome prompt entirely.'
}
```

**Notice:** `Show-ADTInstallationWelcome` would actually skip its own dialog
too if nothing in `-CloseProcesses` is running — but doing the check
yourself first lets you branch your *own* logic around it too (e.g. skip an
entire pre-install section, log a different message, etc.), not just the
dialog.

---

## Capstone — Full detect → log → block/close → proceed → unblock flow

**Goal:** everything from Parts 1, 2, and 5 in one realistic sequence.

```powershell
$targets = @(
    @{ Name = 'notepad'; Description = 'Notepad (practice target)' }
)

Write-ADTLogEntry -Message 'Checking for running target applications...' -Source 'CapstoneFlow'
$running = Get-ADTRunningProcesses -ProcessObjects $targets

if ($running) {
    foreach ($proc in $running) {
        Write-ADTLogEntry -Message "Must close: $($proc.ProcessDescription)" -Severity Warning -Source 'CapstoneFlow'
    }

    Show-ADTInstallationWelcome -CloseProcesses $targets -BlockExecution -AllowDefer -DeferTimes 1 -CloseProcessesCountdown 45
    Write-ADTLogEntry -Message 'User closed/allowed closing of target application(s); execution now blocked.' -Source 'CapstoneFlow'
}
else {
    Write-ADTLogEntry -Message 'Nothing running — proceeding without a welcome prompt.' -Source 'CapstoneFlow'
}

Show-ADTInstallationProgress -StatusMessage 'Simulating install work...' -StatusBarPercentage 0
for ($i = 1; $i -le 3; $i++) {
    Show-ADTInstallationProgress -StatusMessage "Working... step $i of 3" -StatusBarPercentage ($i * 33)
    Start-Sleep -Seconds 1
}
Close-ADTInstallationProgress

# BlockExecution from Show-ADTInstallationWelcome auto-unblocks at Close-ADTSession,
# but being explicit here is good practice and safe to call even if nothing is blocked.
Unblock-ADTAppExecution
Write-ADTLogEntry -Message 'Explicit unblock issued at end of practice flow.' -Source 'CapstoneFlow'

Show-ADTInstallationPrompt -Message 'Practice flow complete. Target application(s) can be reopened now.' -ButtonRightText 'OK'
```

---

## You've now covered the full Part 1-5 arc

- **Part 1:** UI basics — welcome, progress, prompts, dialogs, user input, conditions, loops
- **Part 2:** Logging — severities, sources, log file location, try/catch patterns
- **Part 3:** Registry — read/write/test/remove, first-run markers, per-user hives
- **Part 4:** App detection — `Get-ADTApplication`, MSI vs EXE branching, version checks
- **Part 5:** Closing/blocking real running apps, and how it ties back to `Show-ADTInstallationWelcome`

From here, the natural next step is combining all five into one real
deployment for a specific application you actually want to package — happy
to help wire that up against your template when you're ready.
