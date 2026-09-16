# UCM Tool — Building Blocks Reference (for beginners)

This explains **every piece** used in the UCM maintenance tool, split into two
groups:

- **Part A — PSADT commands** (come from the PSAppDeployToolkit module).
- **Part B — normal PowerShell** (language keywords, cmdlets, .NET calls).

Each entry says what it is, how the tool uses it, and a small standalone
example. If you copy an example to try it, put PSADT ones inside a running
deployment; the PowerShell ones work in any PowerShell window.

> Naming tip: PSADT v4 commands all contain **`ADT`** (e.g. `Show-ADT...`,
> `Write-ADT...`). If a command has `ADT` in the middle, it's from the toolkit,
> not from PowerShell itself.

---

# Part A — PSADT commands

## A1. The deployment skeleton: `$adtSession` and phases

PSADT runs your code inside `Invoke-AppDeployToolkit.ps1`, which is divided into
**Pre-Install → Install → Post-Install** phases. A session object called
`$adtSession` holds information about the run.

Used in the tool:

```powershell
$adtSession.DeploymentType   # 'Install', 'Uninstall', or 'Repair'
$adtSession.InstallPhase     # set by the template to label the log
$adtSession.DirFiles         # path to the 'Files' folder next to the script
$adtSession.InstallTitle     # the app title shown in dialogs
```

You don't create `$adtSession` — the template does. You just read from it. The
UCM wizard lives in the **Install** phase.

## A2. `Show-ADTInstallationPrompt` — the dialog workhorse

This shows one branded dialog. Almost every UCM screen is one call to it.
The **return value is the text of the button the user clicked** (a string).

**Buttons only** (a yes/no style screen):

```powershell
$answer = Show-ADTInstallationPrompt -Title 'Demo' -Subtitle 'Test' `
    -Message 'Proceed?' -ButtonLeftText 'Yes' -ButtonRightText 'No'
if ($answer -eq 'Yes') { 'user said yes' } else { 'user said no' }
```

Key parameters used in the tool:

| Parameter | What it does |
|-----------|--------------|
| `-Message` | The main text (required). |
| `-ButtonLeftText` / `-ButtonMiddleText` / `-ButtonRightText` | Up to three buttons. Return value = the clicked button's text. |
| `-RequestInput` | Adds a **text box** so the user can type an answer. |
| `-DefaultValue` | Pre-fills the text box. **Must not be empty/whitespace.** |
| `-SecureInput` | Masks the text box (password style). **Not in v4.1.8** — see A2.1. |
| `-ListItems` / `-DefaultIndex` | Shows a dropdown; result comes back as `.SelectedItem`. |
| `-Title` / `-Subtitle` | Header text. |
| `-NoExitOnTimeout` | If the dialog times out, don't kill the whole session. The tool sets this on every prompt. |

**Text input** (what the User / PC-name / selection screens do):

```powershell
$result = Show-ADTInstallationPrompt -Title 'Demo' -Subtitle 'Test' `
    -RequestInput -Message 'Enter PC name:' -ButtonRightText 'Next'
# the typed text is pulled out with the Get-UCMInputText helper (Part B10)
```

**Dropdown** (returns an object):

```powershell
$r = Show-ADTInstallationPrompt -Message 'Pick one:' `
    -ListItems @('Default','Minimal','Full') -DefaultIndex 0 -ButtonRightText 'OK'
Write-ADTLogEntry "User picked: $($r.SelectedItem)"
```

### A2.1 The `-SecureInput` caveat
`-SecureInput` (masked password box) was added **after** v4.1.8. On 4.1.8 it
throws *"No parameter found for SecureInput"*, so the tool uses a plain
`-RequestInput` box for the password (visible while typing). Masking would need
a native credential prompt (if your build has one) or a PSADT upgrade.

### A2.2 What `-SecureArgumentList` is (and isn't)
You may see `-SecureArgumentList` in PSADT docs. It belongs to
`Start-ADTProcess`, **not** to the dialogs, and only hides an executable's
command-line arguments from the **log file**. It does **not** mask dialog input.

## A3. `Show-ADTInstallationProgress` — the "please wait" screen

Shows a spinner with a message, in its own thread, while your code works.

```powershell
Show-ADTInstallationProgress -StatusMessage 'Analyzing credentials...'
# ... do slow work here (AD check, WinRM connect, registry read) ...
Close-ADTInstallationProgress
```

The tool shows it around every backend call (auth, connect, read, delete).

## A4. `Close-ADTInstallationProgress`

Closes the spinner from A3. Always pair it with a `Show-ADTInstallationProgress`.
(`Show-ADTInstallationPrompt` also auto-closes a running spinner before it draws.)

## A5. `Write-ADTLogEntry` — write to the PSADT log

Adds a line to the toolkit's log file. The tool uses it to record the registry
snapshot and each delete (your audit trail).

```powershell
Write-ADTLogEntry -Message 'Read complete' -Severity 1 -Source 'UCM'
```

`-Severity`: **1 = Info, 2 = Warning, 3 = Error**. `-Source` is a label you
choose (the tool uses `'UCM'`) so you can grep your own lines out of the log.

## A6. `Close-ADTSession`

Ends the whole deployment with an exit code. The template calls this; the tool
relies on `-NoExitOnTimeout` so a slow operator doesn't trigger it mid-wizard.

```powershell
Close-ADTSession -ExitCode 0
```

---

# Part B — normal PowerShell

## B1. `function` and `param`

Defines a reusable command and its inputs. All the `*-UCM*` helpers are functions.

```powershell
function Get-Sum {
    param([int]$A, [int]$B)
    $A + $B
}
Get-Sum -A 2 -B 3      # -> 5
```

## B2. `if / elseif / else`

Runs code based on a condition. Drives most success/fail branching.

```powershell
if ($auth.Success) { 'ok' } else { 'failed' }
```

## B3. `switch`

Cleaner than many `if`s when one value picks one of several branches. The whole
UCM wizard is a `switch ($state)`.

```powershell
switch ($state) {
    'Login'  { 'show login screen' }
    'Domain' { 'show domain screen' }
    default  { 'unknown state' }
}
```

## B4. `while` loop

Repeats while a condition holds. The wizard loops until `$state` becomes `Exit`.

```powershell
$i = 0
while ($i -lt 3) { "count $i"; $i++ }
```

## B5. `[pscustomobject]@{ ... }`

Builds a small object with named fields. Every backend function returns one so
the UI can check `.Success` and show `.Message`.

```powershell
$r = [pscustomobject]@{ Success = $true; Message = 'done' }
$r.Success    # -> True
$r.Message    # -> 'done'
```

## B6. `$script:` scope

A variable shared across the whole script (all functions and the loop), not just
one function. The tool keeps `$script:UCMCred`, `$script:UCMPC`, etc. this way.

```powershell
$script:Shared = 'visible everywhere in this file'
```

## B7. `try / catch`

Runs risky code and handles failure instead of crashing. Every remote call is
wrapped so a failure becomes a friendly `Success=$false` result.

```powershell
try   { Get-Item 'C:\does-not-exist' -ErrorAction Stop }
catch { "handled: $($_.Exception.Message)" }
```

`$_` is the current error; `.Exception.Message` is its text.

## B8. `Invoke-Command` — run code on a remote PC (WinRM)

Runs a script block **on the target machine** using PowerShell Remoting. This is
how Connect, Read, Delete, and Reboot actually reach the remote PC.

```powershell
Invoke-Command -ComputerName 'PC123' -Credential $cred -ScriptBlock {
    $env:COMPUTERNAME          # runs on PC123, returns its name
}
```

Passing data **into** the remote block uses `-ArgumentList` + `param()`:

```powershell
Invoke-Command -ComputerName 'PC123' -Credential $cred `
    -ArgumentList 'SOFTWARE\App' -ScriptBlock {
        param($path)
        Test-Path "Registry::HKEY_LOCAL_MACHINE\$path"
    }
```

## B9. Credentials: `PSCredential`, `ConvertTo-SecureString`, `.GetNetworkCredential()`

A `PSCredential` bundles a username + password for `-Credential` parameters.

Build one from a plain password:

```powershell
$sec  = ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force
$cred = [System.Management.Automation.PSCredential]::new('user@domain', $sec)
```

Read the plaintext back out (the tool uses this to feed the AD check):

```powershell
$cred.GetNetworkCredential().Password
```

`-AsPlainText -Force` is required by PowerShell to acknowledge you're turning a
normal string into a SecureString.

## B10. `.PSObject.Properties` — inspect an object's fields

Used inside `Get-UCMInputText` to find whichever property holds the typed text,
because the dialog result object's shape can vary by build.

```powershell
$obj = [pscustomobject]@{ Text = 'hello' }
$obj.PSObject.Properties['Text'].Value   # -> 'hello'
```

## B11. Active Directory check: `PrincipalContext.ValidateCredentials`

Verifies a username/password against a domain — this is what "Analyzing" does.
Requires loading the .NET assembly first with `Add-Type`.

```powershell
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
           [System.DirectoryServices.AccountManagement.ContextType]::Domain,
           'dom1.example.local')
$ctx.ValidateCredentials('vikas', 'P@ssw0rd')   # -> True or False
```

## B12. Registry cmdlets and the `Registry::` path

The remote blocks read and delete registry entries.

```powershell
# full provider path form used in the tool:
$path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\App'

Test-Path -LiteralPath $path                       # does the key exist?
Get-ItemPropertyValue -LiteralPath $path -Name 'X' # read a value
Remove-Item -LiteralPath $path -Recurse -Force     # delete a whole key
Remove-ItemProperty -LiteralPath $path -Name 'X' -Force  # delete one value
```

- `Registry::` lets you write the full hive name (`HKEY_LOCAL_MACHINE`,
  `HKEY_USERS`) explicitly — handy for remote/other-user hives.
- `-Recurse -Force` deletes a key and everything under it, no prompt.
- `-LiteralPath` treats the path literally (no wildcard surprises).

## B13. Text/number helpers

**Regex match** `-match` with a character class — decides the username format:

```powershell
'DOM\vikas' -match '[\\@]'   # True: contains \ or @  (so it's already qualified)
'vikas'     -match '[\\@]'   # False: bare name, tool appends @domain
```

**Split on commas or spaces** — parses the `2,4,5` selection:

```powershell
'2, 4 5' -split '[,\s]+'    # -> 2, 4, 5   (splits on commas and/or spaces)
```

**Safe number parse** `TryParse` — turns text into a number without crashing:

```powershell
$n = 0
[int]::TryParse('4', [ref]$n)   # -> True, and $n becomes 4
```

**Blank check**:

```powershell
[string]::IsNullOrWhiteSpace('')     # -> True
[string]::IsNullOrWhiteSpace('abc')  # -> False
```

## B14. Pipeline filters: `Where-Object`, `ForEach-Object`, `Sort-Object`

Filter, transform, and de-duplicate the selected index list and the read items.

```powershell
1..6 | Where-Object { $_ -gt 3 }        # keep >3  -> 4,5,6
1..3 | ForEach-Object { $_ * 10 }       # transform -> 10,20,30
@(3,1,2,1) | Sort-Object -Unique        # sort + dedupe -> 1,2,3
```

`$_` is the current item in the pipeline.

## B15. `-join`

Glues a list into one string. Builds the numbered registry list for the dialog.

```powershell
@('a','b','c') -join "`n"    # a, b, c on separate lines
```

## B16. The `-f` format operator

Fills placeholders `{0} {1}` with values — used to format list rows and log lines.

```powershell
'{0}. {1} = {2}' -f 2, 'Policy', '[present]'
# -> '2. Policy = [present]'
```

## B17. Escape sequences and here-strings

`` `n `` inside a **double-quoted** string is a newline. The tool uses it to lay
out multi-line dialog messages.

```powershell
"Line 1`nLine 2"    # prints on two lines
```

## B18. The unary comma `,$x` (send an array as one argument)

`-ArgumentList` unrolls arrays. To pass a whole array as a **single** argument
into a remote block, prefix it with a comma. The tool does this with the target
list.

```powershell
Invoke-Command -ComputerName 'PC1' -Credential $cred `
    -ArgumentList (,$myArray) -ScriptBlock { param($arr) $arr.Count }
```

## B19. Splatting `@Hashtable`

Bundles common parameters once and reuses them, keeping calls short. The tool
defines `$UCMBase` (Title/Subtitle/NoExitOnTimeout) and splats it into every
prompt with `@UCMBase`.

```powershell
$common = @{ Title = 'Demo'; Subtitle = 'Test'; NoExitOnTimeout = $true }
Show-ADTInstallationPrompt @common -Message 'Hi' -ButtonRightText 'OK'
```

Note: splat uses `@` (`@common`), not `$` — that's what expands the hashtable
into named parameters.

## B20. `shutdown.exe` — trigger the reboot

A standard Windows program (not PowerShell), run inside the remote block.

```powershell
shutdown.exe /r /t 60 /c 'Maintenance complete. Restarting soon.'
```

- `/r` = restart, `/s` would be shut down.
- `/t 60` = wait 60 seconds first (gives the user warning).
- `/c '...'` = message shown to the user.

## B21. Comparison and membership operators used

```powershell
$a -eq $b        # equal
$a -ne $b        # not equal
$x -in @(1,2,3)  # is $x one of these?
$a -lt $b        # less than   ( -gt greater, -ge >=, -le <= )
-not $x          # logical NOT
```

PowerShell uses these worded operators instead of `==`, `!=`, `<`, `>`.

---

# Quick map: which line uses what

| Tool element | Built from |
|--------------|-----------|
| Every screen | `Show-ADTInstallationPrompt` (A2) + `switch`/`while` (B3/B4) |
| "Analyzing…" spinner | `Show-ADTInstallationProgress` / `Close-` (A3/A4) |
| Login validation | `PrincipalContext.ValidateCredentials` (B11) |
| Connect / Read / Delete / Reboot | `Invoke-Command` (B8) + credentials (B9) |
| Registry work | `Test-Path` / `Get-ItemPropertyValue` / `Remove-*` (B12) |
| Username format detection | `-match '[\\@]'` (B13) |
| `2,4,5` parsing | `-split`, `TryParse`, `Where/Sort` (B13/B14) |
| Reg list shown in dialog | `-f`, `-join`, `` `n `` (B16/B15/B17) |
| Reboot | `shutdown.exe /r /t` (B20) |
| Audit log lines | `Write-ADTLogEntry` (A5) |
| Shared state across the loop | `$script:` variables (B6) |
| Reusable prompt defaults | splatting `@UCMBase` (B19) |

---

# Where to learn more

- PSADT function reference: <https://psappdeploytoolkit.com/docs/reference>
- PowerShell built-in help, for any command in Part B:
  ```powershell
  Get-Help Invoke-Command -Examples
  Get-Help about_Splatting
  Get-Help about_Switch
  ```
- List a module's commands (e.g. to see what your PSADT build offers):
  ```powershell
  Get-Command -Module PSAppDeployToolkit *Credential*
  ```
