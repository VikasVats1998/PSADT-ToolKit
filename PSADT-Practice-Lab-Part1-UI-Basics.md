# PSADT v4.1.x Practice Lab — Part 1: UI, Variables, Conditions, Loops

Confirmed against your local module: `PSAppDeployToolkit 4.1.8` in this folder
(`PSAppDeployToolkit\PSAppDeployToolkit.psd1`), and the exact cmdlet parameters
that ship with it. Everything below is verified to exist in your installed
version — not guessed from general PSADT knowledge.

## How to use this lab

You don't need a separate script. Use your real template and a scratch spot inside it:

1. Open `Invoke-AppDeployToolkit.ps1`.
2. Find the `Install-ADTDeployment` function → the `## <Perform Pre-Installation tasks here>` line (around line 143).
3. Paste **one exercise's code** there, save, and run from a terminal:
   ```powershell
   .\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
   ```
   (or `powershell.exe -File .\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Interactive`)
4. Watch the UI, close it, then delete/replace with the next exercise.

**Safety notes before you start:**
- Always run with `-DeployMode Interactive` while practicing, so dialogs actually show.
- For `CloseProcesses` exercises, target something harmless like `notepad` — open Notepad yourself first so you have something safe to test against. Never point practice exercises at apps you actually need running (browser, Outlook, etc.).
- Leave `$adtSession.AppName` etc. blank as they already are — you're only exercising the UI layer, not doing a real install.
- Exercise 9 (restart prompt) can trigger a **real restart** if you click through it carelessly — read its warning before running it.

---

## Quick refresher: variables, conditions, loops in PowerShell

You'll use plain PowerShell constructs *around* the PSADT cmdlets — PSADT doesn't invent its own syntax for these:

```powershell
# Variables (PSADT convention: camelCase for locals, and $adtSession is the session hashtable/object)
[String]$myAppName = 'Contoso Viewer'
[Int32]$retryCount = 0
$myList = @('one', 'two', 'three')          # array
$myMap  = @{ Key1 = 'A'; Key2 = 'B' }        # hashtable

# Conditions
if ($retryCount -lt 3) { 'low' } elseif ($retryCount -eq 3) { 'exact' } else { 'high' }

switch ($choice) {
    'Yes' { 'did yes thing' }
    'No'  { 'did no thing' }
    default { 'fallback' }
}

# Loops
foreach ($item in $myList) { $item }
for ($i = 0; $i -lt 5; $i++) { $i }
$i = 0; while ($i -lt 5) { $i++ }
do { $i++ } until ($i -ge 5)
```

Keep this section in mind — every exercise below combines these with a `Show-ADT*` cmdlet.

---

## Exercise 1 — Variables: reading the session and making your own

**Goal:** see what's already available in `$adtSession`, and practice typed variables.

```powershell
[String]$demoAppName    = 'Contoso Viewer'
[String]$demoAppVersion = '2.4.1'
[Int32]$demoStepCount   = 3

Show-ADTInstallationPrompt -Message @"
Deployment type : $($adtSession.DeploymentType)
Deploy mode     : $($adtSession.DeployMode)
Install phase   : $($adtSession.InstallPhase)

Practice app    : $demoAppName $demoAppVersion
Steps planned   : $demoStepCount
"@ -ButtonRightText 'OK'
```

**Notice:** `$adtSession` is populated automatically by `Open-ADTSession` — you never set `DeploymentType`/`DeployMode` yourself, they come from how you launched the script. `$demoAppName` etc. are just your own variables.

**Challenge:** add a `[Boolean]$demoSilentOverride = $false` and show it in the message too.

---

## Exercise 2 — Conditions: branching on a variable

**Goal:** practice `if / elseif / else` reacting to `$adtSession` state.

```powershell
if ($adtSession.DeployMode -eq 'Silent') {
    Write-ADTLogEntry -Message 'Running silently — no UI will be shown.'
}
elseif ($adtSession.DeploymentType -eq 'Uninstall') {
    Show-ADTInstallationPrompt -Message 'This is an UNINSTALL run.' -ButtonRightText 'OK' -Icon Information
}
else {
    Show-ADTInstallationPrompt -Message "This is a $($adtSession.DeploymentType) run in $($adtSession.DeployMode) mode." -ButtonRightText 'OK' -Icon Information
}
```

**Try it:** run once normally (Install/Interactive), then run again with `-DeploymentType Uninstall -DeployMode Interactive` and watch the branch change. (You'll need to temporarily put the same code block in `Uninstall-ADTDeployment`'s pre-uninstall section too.)

---

## Exercise 3 — Show-ADTInstallationWelcome: the real "app is running, close it" screen

**Goal:** exercise the welcome/close-apps dialog with the actual parameters your module supports.

Open Notepad manually first, then run:

```powershell
$saiwParams = @{
    CloseProcesses           = @('notepad')
    CloseProcessesCountdown  = 45      # auto-continue after 45s if user ignores it
    AllowDefer                = $true
    DeferTimes                = 2
    CheckDiskSpace             = $true
    RequiredDiskSpace         = 100    # MB, artificially small so it always passes
    PersistPrompt             = $true
    CustomText                = $false
}
Show-ADTInstallationWelcome @saiwParams
```

**Notice:**
- If Notepad is running, PSADT lists it and offers to close it for you.
- `AllowDefer`/`DeferTimes` adds a "Defer" button — click it once, then re-run and confirm your defer count decreased (PSADT tracks defer history per app).
- `PersistPrompt` keeps re-showing the window in front even if you click away.

**Challenge:** change `CloseProcesses` to the richer form and see the friendly description appear in the dialog:
```powershell
CloseProcesses = @(@{ Name = 'notepad'; Description = 'Notepad (practice target)' })
```

---

## Exercise 4 — Show-ADTInstallationProgress + a loop: simulate real install progress

**Goal:** drive the progress bar and status text from a loop — this is the core "installer feels alive" pattern.

```powershell
$steps = @(
    @{ Message = 'Copying files...';       Percent = 20 }
    @{ Message = 'Registering components...'; Percent = 45 }
    @{ Message = 'Applying configuration...'; Percent = 70 }
    @{ Message = 'Finalizing...';           Percent = 95 }
    @{ Message = 'Done.';                   Percent = 100 }
)

Show-ADTInstallationProgress -StatusMessage 'Starting practice install...' -StatusMessageDetail 'Please wait' -StatusBarPercentage 0

foreach ($step in $steps) {
    Show-ADTInstallationProgress -StatusMessage $step.Message -StatusBarPercentage $step.Percent
    Start-Sleep -Seconds 2
}

Close-ADTInstallationProgress
```

**Notice:** calling `Show-ADTInstallationProgress` again just **updates** the existing window — it doesn't open a new one each time. `Close-ADTInstallationProgress` is what actually dismisses it; forgetting to call it leaves the window stuck on screen.

**Challenge:** rewrite the `foreach` as a `for` loop using array indices, and make the percentage a calculated value: `[Int32](($i + 1) / $steps.Count * 100)`.

---

## Exercise 5 — Show-ADTInstallationPrompt with `-RequestInput`: capturing real user input

This is the "user input value" feature you asked about — PSADT 4.1 added a genuine text-input box (`-RequestInput`/`-DefaultValue`), not just buttons.

**Goal:** capture typed text into a variable, then use it.

```powershell
$licenseKey = Show-ADTInstallationPrompt -RequestInput -DefaultValue 'XXXXX-XXXXX-XXXXX' `
    -Message 'Enter your practice license key:' -ButtonRightText 'Continue' -ButtonLeftText 'Cancel'

if ([String]::IsNullOrWhiteSpace($licenseKey)) {
    Show-ADTInstallationPrompt -Message 'No key entered — cancelled.' -ButtonRightText 'OK' -Icon Warning
}
else {
    Show-ADTInstallationPrompt -Message "You entered: $licenseKey`n`nLength: $($licenseKey.Length) characters" -ButtonRightText 'OK'
}
```

**Notice:** the return value of the cmdlet **is** what the user typed (or the button text if they didn't type anything meaningful) — assign it directly with `$var = Show-ADTInstallationPrompt ...`.

**Challenge — combine input with a loop (re-prompt until valid):**

```powershell
[String]$computerLabel = ''
do {
    $computerLabel = Show-ADTInstallationPrompt -RequestInput -DefaultValue '' `
        -Message 'Enter a label with at least 3 characters:' -ButtonRightText 'OK' -ButtonLeftText 'Cancel'

    if ($computerLabel -eq 'Cancel') { break }

    if ($computerLabel.Length -lt 3) {
        Show-ADTInstallationPrompt -Message 'Too short — try again.' -ButtonRightText 'OK' -Icon Warning
    }
} until ($computerLabel.Length -ge 3)
```

---

## Exercise 6 — Buttons as a decision: switch on the return value

**Goal:** use a 3-button prompt to branch your script logic, like choosing an install path.

```powershell
$choice = Show-ADTInstallationPrompt -Message 'Choose install type:' `
    -ButtonLeftText 'Minimal' -ButtonMiddleText 'Typical' -ButtonRightText 'Full' -Icon Information

switch ($choice) {
    'Minimal' { Show-ADTInstallationPrompt -Message 'You chose Minimal — would install core files only.' -ButtonRightText 'OK' }
    'Typical' { Show-ADTInstallationPrompt -Message 'You chose Typical — would install core + common features.' -ButtonRightText 'OK' }
    'Full'    { Show-ADTInstallationPrompt -Message 'You chose Full — would install everything.' -ButtonRightText 'OK' }
    default   { Write-ADTLogEntry -Message "Unexpected choice: $choice" -Severity 2 }
}
```

**Notice:** the button's **text** is the return value — that's why `switch` matches on `'Minimal'`/`'Typical'`/`'Full'` exactly as typed in the `-Button*Text` parameters.

---

## Exercise 7 — Show-ADTDialogBox: the native Yes/No/Cancel alternative

**Goal:** compare PSADT's themed prompt (Exercise 6) against the plain native Windows dialog.

```powershell
$answer = Show-ADTDialogBox -Text 'Restart the practice app now?' -Buttons YesNoCancel -DefaultButton Second -Icon Question

switch ($answer) {
    'Yes'    { Show-ADTBalloonTip -BalloonTipTitle 'Practice' -BalloonTipText 'You chose Yes.' }
    'No'     { Show-ADTBalloonTip -BalloonTipTitle 'Practice' -BalloonTipText 'You chose No.' }
    'Cancel' { Write-ADTLogEntry -Message 'User cancelled the dialog.' -Severity 2 }
}
```

**Notice:** `Show-ADTDialogBox` is a native MessageBox (fast, no theming) — use it for quick internal decisions; use `Show-ADTInstallationPrompt` when you want the branded PSADT look for anything user-facing.

---

## Exercise 8 — Loops driving multiple UI updates: a mini component installer

**Goal:** combine `foreach`, a running counter, progress updates, and a balloon tip at the end.

```powershell
$components = @('Core Engine', 'Language Pack', 'Plugins', 'Sample Data')
[Int32]$done = 0

Show-ADTInstallationProgress -StatusMessage 'Installing components...' -StatusBarPercentage 0

foreach ($component in $components) {
    Show-ADTInstallationProgress -StatusMessage "Installing: $component" `
        -StatusMessageDetail "$($done + 1) of $($components.Count)" `
        -StatusBarPercentage ([Int32]($done / $components.Count * 100))
    Start-Sleep -Seconds 1
    $done++
}

Show-ADTInstallationProgress -StatusMessage 'Complete' -StatusBarPercentage 100
Start-Sleep -Seconds 1
Close-ADTInstallationProgress

Show-ADTBalloonTip -BalloonTipTitle 'Practice Install' -BalloonTipText "$done of $($components.Count) components installed." -BalloonTipIcon Info
```

**Challenge:** add a `while` loop retry wrapper around one "component" that randomly "fails" (`Get-Random -Maximum 2`), showing a warning prompt and retrying up to 3 times before giving up — practice `while`, a retry counter, and `break`.

---

## Exercise 9 — Show-ADTInstallationRestartPrompt (read the warning first)

**⚠️ This dialog can trigger a real Windows restart if you click the restart button and let a countdown finish.** Practice it deliberately and close it via "Restart Later" / the countdown-cancel path, or use `-NoCountdown` so nothing auto-triggers.

```powershell
Show-ADTInstallationRestartPrompt -NoCountdown -CustomText
```

**Notice:** with `-NoCountdown`, the dialog just sits there waiting for a manual click — safe for practicing the UI without risking an actual reboot. Only try `-CountdownSeconds` once you're comfortable, and stay at the keyboard to cancel it.

---

## Exercise 10 — Capstone: put it all together

**Goal:** one script exercising variables, a condition, a loop, user input, a decision, and progress — the shape of a real deployment's UI flow.

```powershell
[String]$targetLabel = ''
[Int32]$attempt = 0

Show-ADTInstallationWelcome -CloseProcesses @('notepad') -AllowDefer -DeferTimes 1 -CheckDiskSpace

do {
    $attempt++
    $targetLabel = Show-ADTInstallationPrompt -RequestInput -DefaultValue '' `
        -Message "Attempt $attempt — enter an install label (min 3 chars):" -ButtonRightText 'OK'
} until ($targetLabel.Length -ge 3 -or $attempt -ge 3)

if ($targetLabel.Length -lt 3) {
    Show-ADTInstallationPrompt -Message 'No valid label given — aborting practice run.' -ButtonRightText 'OK' -Icon Error
}
else {
    Show-ADTInstallationProgress -StatusMessage "Installing '$targetLabel'..." -StatusBarPercentage 0
    for ($i = 1; $i -le 5; $i++) {
        Show-ADTInstallationProgress -StatusMessage "Installing '$targetLabel'..." -StatusMessageDetail "Step $i of 5" -StatusBarPercentage ($i * 20)
        Start-Sleep -Seconds 1
    }
    Close-ADTInstallationProgress

    $confirm = Show-ADTDialogBox -Text "Install of '$targetLabel' finished. Open notes?" -Buttons YesNo -Icon Question
    if ($confirm -eq 'Yes') {
        Show-ADTBalloonTip -BalloonTipTitle 'Practice Install' -BalloonTipText "'$targetLabel' completed successfully." -BalloonTipIcon Info
    }
}
```

---

## Coming in Part 2

Once you're comfortable with the UI/variables/conditions/loops above, Part 2 will cover, still grounded in your actual v4.1.x module:

- **Logging** — `Write-ADTLogEntry` (severities, log file location/config)
- **Registry** — `Get-ADTRegistryKey`, `Set-ADTRegistryKey`, `Test-ADTRegistryValue`, `Remove-ADTRegistryKey`
- **Detecting installed apps / product codes** — `Get-ADTApplication`, MSI product codes, uninstall-key detection
- **Closing / blocking running applications for real** — `Get-ADTRunningProcesses`, `Block-ADTAppExecution`, `Unblock-ADTAppExecution`, and how that ties back into `Show-ADTInstallationWelcome`'s `CloseProcesses`

Just say the word when you're ready and I'll write that one the same way — verified against your installed module, not from memory.
