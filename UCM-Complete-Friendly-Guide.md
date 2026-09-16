# UCM Maintenance Tool — Friendly Complete Guide

*A gentle, start-from-zero walkthrough of the whole script.*
*IT Help Desk – LZFD Karlsruhe Maintenance*

Welcome! This guide assumes you're new to PowerShell and PSADT. It explains the
**entire script from top to bottom** in plain language, shows the code, and
tells you how to set it up and run it safely. Take it slowly — you don't need to
memorise anything.

---

## 1. What is this tool, in one paragraph?

It's a small on-screen wizard that a help-desk person clicks through. It lets
them log in with their work account, connect to another PC on the network, look
at some specific Windows registry entries on that PC, delete the ones they
choose, and then restart that PC. It runs *inside* PSADT (the
PSAppDeployToolkit), which gives it the nice branded pop-up windows.

Think of it as a guided form with these screens:

> **Login → pick Domain → enter User → enter Password → (checking...) →
> enter PC name → Read registry → choose what to delete → Delete → Reboot →
> Done.**

At any step, if something goes wrong, you get a **Failed** screen with
**Try Again** or **Cancel**.

---

## 2. Two kinds of commands you'll see

The script mixes two "languages," and it helps to know which is which:

1. **PSADT commands** — these draw the pop-up windows and write the log. They
   always have **`ADT`** in the name, like `Show-ADTInstallationPrompt`. They
   only exist because the toolkit is loaded.

2. **Normal PowerShell** — the everyday building blocks: `function`, `if`,
   `switch`, `while`, and cmdlets like `Invoke-Command`. These work in any
   PowerShell window.

> **Rule of thumb:** see `ADT` in the middle of a command? It's from the
> toolkit. No `ADT`? It's plain PowerShell.

---

## 3. The shape of the script (the mental model)

The script has **three parts**. Once you see these, the rest is easy:

1. **Config** — the only bit you edit for your environment: which domain numbers
   map to which real domains, and the list of registry entries to work on.

2. **Backend functions** — small helpers that do the actual work (check the
   password, connect to the PC, read/delete registry, reboot). Each one hands
   back a little result object that says **`Success`** (true/false) and
   **`Message`** (what happened).

3. **The wizard loop** — the part that shows each screen and decides where to go
   next based on those `Success` results.

A repeating idea in part 3 is the **state machine**. Don't let the name scare
you. It just means: there's a variable called `$state` that holds the name of
the current screen (like `'Login'` or `'Reboot'`). A loop looks at `$state`,
shows that screen, and then sets `$state` to the next screen. It keeps going
until `$state` becomes `'Exit'`.

```
$state = 'Login'
while not exit:
    show the screen named $state
    set $state to the next screen
```

That's the whole engine.

---

## 4. A few concepts you'll meet (quick primer)

You'll see these again and again, so here they are once, simply:

**A function** is a named mini-command you define once and reuse.
```powershell
function Say-Hi { param([string]$Name) "Hi $Name" }
Say-Hi -Name 'Vikas'      # -> Hi Vikas
```

**A result object** groups a few named facts together.
```powershell
$r = [pscustomobject]@{ Success = $true; Message = 'done' }
$r.Success     # True
$r.Message     # 'done'
```
Every backend helper returns one of these so the wizard can do
`if ($r.Success) { go forward } else { show Failed }`.

**`switch`** picks one branch out of many based on a value.
```powershell
switch ($state) {
    'Login'  { 'show login' }
    'Reboot' { 'show reboot' }
}
```

**A credential** is a username+password bundle PowerShell can pass around safely.
It's what lets the tool act *as your admin account* on the remote PC.

**Remoting** (`Invoke-Command`) runs a block of code **on the other PC** instead
of yours. That's how it reaches into the target machine's registry.

That's enough theory. Now the actual script.

---

## 5. The complete script, explained section by section

Paste the whole thing into the **Install** section of
`Invoke-AppDeployToolkit.ps1`. Below, each block is shown, then explained.

### 5.1 Load a helper library

```powershell
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
```

`Add-Type` loads an extra .NET library. This one lets us check a password
against Active Directory later. It's a one-time setup line.

### 5.2 Config — domain mapping (EDIT THIS)

```powershell
function Resolve-UCMDomain {
    param([string]$Number)
    switch ($Number) {
        '1'     { 'dom1.example.local' }
        '2'     { 'dom2.example.local' }
        '3'     { 'dom3.example.local' }
        '4'     { 'dom4.example.local' }
        default { $null }
    }
}
```

When the operator types `1`, this turns it into the real domain name
(`dom1.example.local`). **`dom1.example.local` is a placeholder — replace it
with your real domain.** To find your real one, run this anywhere:
```powershell
$env:USERDNSDOMAIN
```
If the operator types something that isn't 1–4, the `default` branch returns
`$null` (nothing), and the wizard shows Failed.

### 5.3 Config — the registry list (EDIT THIS)

```powershell
$script:UCMTargets = @(
    [pscustomobject]@{ Index=1; Label='Example App Cache';   Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp\Cache';   Name='' }
    [pscustomobject]@{ Index=2; Label='Broken Policy Value';  Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp';         Name='BadPolicy' }
    [pscustomobject]@{ Index=3; Label='Stale Profile Key';    Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp\Profiles'; Name='' }
    [pscustomobject]@{ Index=4; Label='Legacy Add-in';        Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Vendor\Addin';       Name='' }
    [pscustomobject]@{ Index=5; Label='User Autostart Value'; Hive='HKEY_USERS';         Path='<SID>\SOFTWARE\Example';      Name='Runonce' }
)
```

This is the numbered menu of registry entries the tool can delete. Each row has:

- **`Index`** — the number the operator types to pick it.
- **`Label`** — a friendly name shown on screen.
- **`Hive`** — `HKEY_LOCAL_MACHINE` (settings for the whole machine) or
  `HKEY_USERS` (a specific user's settings).
- **`Path`** — where the entry lives (no leading backslash).
- **`Name`** — leave it empty (`''`) to delete a whole **key** (a folder and
  everything in it), or put a value name to delete just that one **value**.

`$script:` at the front means "this list is available everywhere in the script."

> **About user settings:** you can't peek into another person's `HKCU` remotely.
> That's why user entries use `HKEY_USERS\<SID>` — you replace `<SID>` with the
> user's ID. For a first test, stick to `HKEY_LOCAL_MACHINE` rows.

### 5.4 The window title

```powershell
$UCMTitle = 'IT Help Desk - LZFD Karlsruhe Maintenance'
```

Just the text shown at the top of every pop-up.

### 5.5 Helper — read what the operator typed

```powershell
function Get-UCMInputText {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    if ($Result -is [securestring]) { return (New-Object System.Management.Automation.PSCredential 'x', $Result).GetNetworkCredential().Password }
    foreach ($p in 'Text','Input','InputText','Value','Response','SelectedItem') {
        $prop = $Result.PSObject.Properties[$p]
        if ($prop -and $null -ne $prop.Value) {
            if ($prop.Value -is [securestring]) { return (New-Object System.Management.Automation.PSCredential 'x', $prop.Value).GetNetworkCredential().Password }
            return [string]$prop.Value
        }
    }
    return [string]$Result
}
```

When a text-box dialog closes, PSADT hands back the typed text — but different
toolkit versions wrap it slightly differently (sometimes a plain string,
sometimes an object with a `.Text` or `.Value` field). This helper quietly tries
each possibility and returns the plain text no matter which shape it is. You
don't call it directly; the wizard uses it after each input screen. It's here so
the tool works across builds without you having to worry about it.

### 5.6 Backend — check the login

```powershell
function Test-UCMCredential {
    param([string]$DomainFqdn,[string]$User,[string]$PlainPw)
    try {
        $sam = if ($User -match '[\\@]') { ($User -split '[\\@]')[-1] } else { $User }
        $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                    [System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainFqdn)
        $ok = $ctx.ValidateCredentials($sam, $PlainPw)
        if ($ok) { [pscustomobject]@{ Success=$true;  Message="Authenticated against $DomainFqdn" } }
        else     { [pscustomobject]@{ Success=$false; Message='Invalid username or password.' } }
    } catch { [pscustomobject]@{ Success=$false; Message="Domain not reachable: $($_.Exception.Message)" } }
}
```

This asks Active Directory "is this username + password correct?" and returns a
`Success`/`Message` object. `ValidateCredentials` is the line that actually
checks. The `try/catch` means if the domain can't be reached at all, it returns
a friendly failure instead of crashing. (`$($_.Exception.Message)` is just "the
error's text.")

### 5.7 Backend — connect to the PC

```powershell
function Test-UCMConnection {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        $n = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
        [pscustomobject]@{ Success=$true; Message="Connected to $n" }
    } catch { [pscustomobject]@{ Success=$false; Message="Cannot reach $ComputerName over WinRM: $($_.Exception.Message)" } }
}
```

`Invoke-Command` tries to run one tiny thing on the remote PC (ask it its own
name). If that works, the connection is good. This uses **WinRM**, the Windows
remote-management channel — it must be turned on for the target PC (usually it is
in a company domain).

### 5.8 Backend — read the registry

```powershell
function Get-UCMRegistryData {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        $data = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ArgumentList (,$script:UCMTargets) -ScriptBlock {
            param($Targets)
            foreach ($t in $Targets) {
                $full = "Registry::$($t.Hive)\$($t.Path)"; $exists=$false; $val=$null
                if ([string]::IsNullOrWhiteSpace($t.Name)) { $exists = Test-Path -LiteralPath $full }
                else { try { $val = Get-ItemPropertyValue -LiteralPath $full -Name $t.Name -ErrorAction Stop; $exists=$true } catch { $exists=$false } }
                [pscustomobject]@{ Index=$t.Index; Label=$t.Label; Exists=$exists; Value=$val }
            }
        }
        foreach ($r in $data) { Write-ADTLogEntry -Message ("READ [{0}] {1} Exists={2} Value={3}" -f $r.Index,$r.Label,$r.Exists,$r.Value) -Source 'UCM' }
        [pscustomobject]@{ Success=$true; Message='Read complete'; Items=($data | Sort-Object Index) }
    } catch { [pscustomobject]@{ Success=$false; Message="Read failed: $($_.Exception.Message)"; Items=@() } }
}
```

This runs **on the remote PC** and checks each entry in your list: does it exist,
and what's its value? It returns an `.Items` list the wizard will display as a
numbered menu. It also writes each finding to the PSADT log with
`Write-ADTLogEntry` — that's your record of what was there *before* anything is
deleted. (`(,$script:UCMTargets)` is a small trick to send the whole list as one
argument; the leading comma matters.)

### 5.9 Backend — turn "2,4,5" into real numbers

```powershell
function ConvertTo-UCMIndexList {
    param([string]$Selection)
    $valid = $script:UCMTargets.Index
    ($Selection -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $n=0; if ([int]::TryParse($_.Trim(),[ref]$n)) { $n } else { -1 } }) |
        Where-Object { $_ -in $valid } | Sort-Object -Unique
}
```

The operator types something like `2,4,5`. This splits that on commas/spaces,
turns each piece into a number safely, throws away anything that isn't a real
menu number, and removes duplicates. The result is a clean list of numbers to
delete.

### 5.10 Backend — delete the chosen entries

```powershell
function Remove-UCMRegistryData {
    param([string]$ComputerName,[pscredential]$Credential,[int[]]$Indices)
    $chosen = $script:UCMTargets | Where-Object { $_.Index -in $Indices }
    try {
        $res = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ArgumentList (,$chosen) -ScriptBlock {
            param($Targets)
            foreach ($t in $Targets) {
                $full = "Registry::$($t.Hive)\$($t.Path)"; $ok=$false; $msg=''
                try {
                    if ([string]::IsNullOrWhiteSpace($t.Name)) {
                        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop; $ok=$true; $msg='Key deleted' }
                        else { $ok=$true; $msg='Already absent' }
                    } else { Remove-ItemProperty -LiteralPath $full -Name $t.Name -Force -ErrorAction Stop; $ok=$true; $msg='Value deleted' }
                } catch { $ok=$false; $msg=$_.Exception.Message }
                [pscustomobject]@{ Index=$t.Index; Label=$t.Label; Success=$ok; Message=$msg }
            }
        }
        foreach ($r in $res) { Write-ADTLogEntry -Message ("DELETE [{0}] {1} -> {2} ({3})" -f $r.Index,$r.Label,$r.Success,$r.Message) -Severity $(if($r.Success){1}else{3}) -Source 'UCM' }
        $all = ($res | Where-Object { -not $_.Success }).Count -eq 0
        [pscustomobject]@{ Success=$all; Message=$(if($all){'All selected items deleted.'}else{'One or more deletions failed.'}); Results=$res }
    } catch { [pscustomobject]@{ Success=$false; Message="Delete failed: $($_.Exception.Message)"; Results=@() } }
}
```

Runs on the remote PC and deletes each chosen entry — a whole key
(`Remove-Item -Recurse`) or a single value (`Remove-ItemProperty`). Every action
is logged. It reports overall `Success = $true` only if **every** deletion
worked. **Note:** registry deletion cannot be undone, which is why the read in
5.8 logs everything first.

### 5.11 Backend — reboot the PC

```powershell
function Restart-UCMComputer {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            shutdown.exe /r /t 60 /c 'IT maintenance complete. This PC will restart shortly.'
        }
        [pscustomobject]@{ Success=$true; Message="Reboot triggered on $ComputerName." }
    } catch { [pscustomobject]@{ Success=$false; Message="Reboot failed: $($_.Exception.Message)" } }
}
```

Runs the standard Windows `shutdown` program on the remote PC. `/r` = restart,
`/t 60` = wait 60 seconds first (so the user gets a warning), `/c` = the message
they see. **This is a real restart** — only aim it at a machine that's meant to
be restarted.

### 5.12 Shared settings for every pop-up

```powershell
$UCMBase = @{ Title=$UCMTitle; Subtitle='User Configuration Maintenance'; NoExitOnTimeout=$true }
```

Instead of repeating the same three settings on every dialog, we put them in one
bundle and reuse it (this is called "splatting"). `NoExitOnTimeout=$true` means:
if a dialog is left open too long, don't shut the whole tool down — just move on.

### 5.13 The wizard loop (the heart)

```powershell
$script:UCMCred=$null; $script:UCMDomain=$null; $script:UCMUser=$null; $script:UCMPC=$null; $script:UCMRead=$null
$state='Login'; $retryState=$null

while ($state -and $state -ne 'Exit') {
    switch ($state) {

        'Login' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Willkommen bei UCM.`n`nUser Configuration Maintenance - Profil-Reparatur & Wartungs-Workspace." -ButtonLeftText 'Login' -ButtonRightText 'Cancel'
            $state = if ($r -eq 'Login') { 'Domain' } else { 'Exit' }
        }

        'Domain' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue '1' -Message "Choose Domain Number:`n`n1. Domain 1`n2. Domain 2`n3. Domain 3`n4. Domain 4" -ButtonRightText 'Next'
            $num = Get-UCMInputText $r
            $fqdn = Resolve-UCMDomain $num
            if ($fqdn) { $script:UCMDomain=$fqdn; $state='User' }
            else { $retryState='Domain'; $state='Failed' }
        }

        'User' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Domain: $script:UCMDomain`n`nEnter user name:" -ButtonRightText 'Next'
            $script:UCMUser = Get-UCMInputText $r
            $state = if ([string]::IsNullOrWhiteSpace($script:UCMUser)) { 'Login' } else { 'Password' }
        }

        'Password' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Enter password for $script:UCMUser :" -ButtonRightText 'Login'
            $pw = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($pw)) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Analyzing credentials...'
                $auth = Test-UCMCredential -DomainFqdn $script:UCMDomain -User $script:UCMUser -PlainPw $pw
                Close-ADTInstallationProgress
                if ($auth.Success) {
                    $sec = ConvertTo-SecureString $pw -AsPlainText -Force
                    $upn = if ($script:UCMUser -match '[\\@]') { $script:UCMUser } else { "$script:UCMUser@$script:UCMDomain" }
                    $script:UCMCred = [System.Management.Automation.PSCredential]::new($upn, $sec)
                    $pw=$null; $sec=$null
                    $state='EnterPC'
                } else { $retryState='Password'; $script:UCMFailMsg=$auth.Message; $state='Failed' }
            }
        }

        'EnterPC' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message 'Successful. Enter PC Name:' -ButtonLeftText 'Connect' -ButtonRightText 'Cancel'
            $script:UCMPC = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($script:UCMPC)) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage "Connecting to $script:UCMPC ..."
                $conn = Test-UCMConnection -ComputerName $script:UCMPC -Credential $script:UCMCred
                Close-ADTInstallationProgress
                if ($conn.Success) { $state='Read' } else { $retryState='EnterPC'; $script:UCMFailMsg=$conn.Message; $state='Failed' }
            }
        }

        'Read' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Connected to $script:UCMPC.`n`nRead the registry keys?" -ButtonLeftText 'Read' -ButtonRightText 'Cancel'
            if ($r -eq 'Read') {
                Show-ADTInstallationProgress -StatusMessage 'Reading registry...'
                $script:UCMRead = Get-UCMRegistryData -ComputerName $script:UCMPC -Credential $script:UCMCred
                Close-ADTInstallationProgress
                if ($script:UCMRead.Success) { $state='RegList' } else { $retryState='Read'; $script:UCMFailMsg=$script:UCMRead.Message; $state='Failed' }
            } else { $state='Login' }
        }

        'RegList' {
            $list = ($script:UCMRead.Items | ForEach-Object { "{0}. {1} = {2}" -f $_.Index, $_.Label, $(if($_.Exists){'[present]'}else{'[absent]'}) }) -join "`n"
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Read successful:`n`n$list`n`nSelect the numbers to delete (e.g. 2,4,5):" -ButtonLeftText 'Delete' -ButtonRightText 'Cancel'
            $sel = Get-UCMInputText $r
            $idx = ConvertTo-UCMIndexList $sel
            if (-not $idx) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Deleting selected keys...'
                $del = Remove-UCMRegistryData -ComputerName $script:UCMPC -Credential $script:UCMCred -Indices $idx
                Close-ADTInstallationProgress
                if ($del.Success) { $state='Reboot' } else { $retryState='RegList'; $script:UCMFailMsg=$del.Message; $state='Failed' }
            }
        }

        'Reboot' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message 'Successful. Trigger reboot?' -ButtonLeftText 'Reboot' -ButtonRightText 'Close'
            if ($r -eq 'Reboot') {
                $rb = Restart-UCMComputer -ComputerName $script:UCMPC -Credential $script:UCMCred
                if ($rb.Success) { $state='Done' } else { $retryState='Reboot'; $script:UCMFailMsg=$rb.Message; $state='Failed' }
            } else { $state='Done' }
        }

        'Done' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Maintenance successful for PC {$script:UCMPC}." -ButtonLeftText 'Start New' -ButtonRightText 'Close'
            $state = if ($r -eq 'Start New') { 'EnterPC' } else { 'Exit' }
        }

        'Failed' {
            $msg = if ($script:UCMFailMsg) { "Failed:`n`n$script:UCMFailMsg" } else { 'Failed.' }
            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Try Again' -ButtonRightText 'Cancel'
            $script:UCMFailMsg=$null
            $state = if ($r -eq 'Try Again') { $retryState } else { 'Login' }
        }
    }
}
```

Reading this is easier than it looks. The first two lines set up empty
"memory slots" (`$script:UCMCred`, `$script:UCMPC`, etc.) that get filled in as
the operator progresses, and set the starting screen to `'Login'`.

Then the `while` loop repeats until `$state` is `'Exit'`. Inside, `switch`
matches the current `$state` to its screen block. Each block:

1. shows a dialog with `Show-ADTInstallationPrompt`,
2. (sometimes) shows the "please wait" spinner and calls a backend helper,
3. sets `$state` to the next screen based on the result.

Notice the pattern for failures: it remembers which screen failed
(`$retryState = 'Password'`) and jumps to `'Failed'`. The Failed screen's
**Try Again** sends you back to exactly that remembered screen. That's how every
retry branch works with almost no extra code.

A few small things you'll spot:
- `` `n `` inside the messages means "new line."
- `@UCMBase` pours in the shared Title/Subtitle/timeout settings from 5.12.
- `$r -eq 'Login'` checks which button was clicked (the dialog returns the
  button's text).
- The password is cleared (`$pw=$null`) right after it's used.

---

## 6. Setting it up (first-time checklist)

1. Open `Invoke-AppDeployToolkit.ps1` in an editor (VS Code is nice; ISE works).
2. If there's an old line like `."$($adtSession.DirFiles)\app2.ps1"`, delete it
   — this script replaces that approach.
3. Paste the whole script from section 5 into the **Install** part.
4. Edit **`Resolve-UCMDomain`** (5.2) with your real domain (`$env:USERDNSDOMAIN`).
5. Edit **`$script:UCMTargets`** (5.3) with real registry entries — for a first
   test you can leave the placeholders; they'll just show as `[absent]`.
6. **Save the file as UTF-8.** (See section 8 for why this matters a lot.)

---

## 7. Running it safely (please read before testing)

Do your first run against **yourself**, not a colleague's PC:

- Log in with **your own** admin username and password.
- At **Enter PC Name**, type your **own computer's name** or `localhost`.
- With placeholder registry entries, **Read** will show everything as
  `[absent]` — that's normal, not a bug.
- **Do NOT press Reboot on your own machine.** It really will restart your PC
  after 60 seconds. Test the reboot step only on a spare/test machine (a VM is
  ideal).

For the tool to get past "Analyzing" and connect, your account needs to be an
**admin on the target PC**, and that PC needs **WinRM** turned on (normal in a
company domain). A regular user account will log in fine but fail at Connect.

---

## 8. Things that already tripped us up (so they don't trip you)

- **Save as UTF-8, use only plain characters.** A fancy dash (`—`) saved in the
  wrong format turns into gibberish that breaks the whole script with confusing
  "unexpected token" errors. Stick to a normal hyphen `-`.
- **`-SecureInput` (masked password) isn't in version 4.1.8.** That's why the
  Password screen here is a normal box and the password is **visible while
  typing**. It still works; it's just not hidden. If you later move to a newer
  PSADT, you can add `-SecureInput` to the Password dialog to mask it.
- **`-SecureArgumentList` does NOT hide dialog input.** It only hides an
  program's command-line from the log file. Different thing entirely.
- **Interactive mode only.** These pop-ups only appear when a person is logged
  on to answer them. The tool is meant to be run by hand, not pushed silently.
- **Don't just comment out a screen to skip it.** If a screen still points to
  the one you removed, the loop jumps to a screen that no longer exists and quits.
  Instead, change where the previous screen sends you (change the `$state='...'`).

---

## 9. If something goes wrong

| You see... | It probably means... | Do this |
|------------|----------------------|---------|
| "unexpected token" / "missing }" errors | File saved in wrong format / fancy character | Save as UTF-8, replace any `—` with `-` |
| "No parameter found for SecureInput" | Your PSADT is 4.1.8 (no masking yet) | Use the plain password box (as in 5.13) |
| Login fails with the right password | Domain still set to the placeholder | Put your real domain in `Resolve-UCMDomain` |
| Connect fails on a real PC | WinRM off, or your account isn't admin there | Enable WinRM; use an admin account |
| Dialogs never appear | Running silently (non-interactive) | Run it interactively |
| It quietly exits mid-flow | A screen points to a removed/renamed state | Fix the `$state='...'` target |

---

## 10. Mini-glossary

- **PSADT** — PSAppDeployToolkit; provides the branded pop-ups and logging.
- **Cmdlet** — a PowerShell command (e.g. `Invoke-Command`).
- **Function** — a mini-command you define (all the `*-UCM*` ones).
- **Credential** — a username+password bundle for logging in as someone.
- **WinRM** — the Windows channel that lets one PC run commands on another.
- **Registry** — Windows' settings database; keys are like folders, values like
  files inside them.
- **Hive** — a top-level registry area (`HKEY_LOCAL_MACHINE`, `HKEY_USERS`).
- **State machine** — the "current screen" variable + loop that runs the wizard.
- **Splatting** — bundling parameters in a hashtable and reusing them (`@UCMBase`).
- **Interactive mode** — a real person is present to click the dialogs.

---

You've got this. Start with section 6, test against your own machine per section
7, and keep this guide open beside the script. When a line looks strange, find
its block in section 5 — the explanation right under it will tell you what it's
doing.
