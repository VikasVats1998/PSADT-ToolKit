# UCM Maintenance Tool — Documentation

**IT Help Desk – LZFD Karlsruhe Maintenance**
Remote registry maintenance wizard built on PSAppDeployToolkit (PSADT) v4.1.8 native dialogs.

---

## 1. What this tool does

It is an operator-driven wizard, run interactively through PSADT, that lets a
help-desk admin:

1. Log in with domain credentials (validated against Active Directory).
2. Connect to a specific remote PC over WinRM.
3. Read a predefined set of registry targets from that PC.
4. Select which of those targets to delete (by number).
5. Delete the selected keys/values remotely.
6. Trigger a reboot of the remote PC.
7. Loop to a new PC or close.

Every step has a **Failed → Try Again / Cancel** branch.

It is **not** a silent MECM package. It only shows dialogs in *Interactive*
mode; if pushed silently, PSADT bypasses the prompts by design. The tool is
meant to be launched by a person at a console.

---

## 2. Architecture at a glance

The tool is a single block pasted into the **Install** section of
`Invoke-AppDeployToolkit.ps1`. It has three parts:

| Part | Purpose |
|------|---------|
| **Config** | `Resolve-UCMDomain` (domain number → FQDN) and `$script:UCMTargets` (the registry list). The only things you edit per environment. |
| **Backend functions** | Pure logic: AD auth, WinRM connect, registry read/delete, reboot. Each returns a `[pscustomobject]` with `Success` (bool) and `Message` (string). UI-agnostic. |
| **State machine** | A `while`/`switch` loop that drives the screens using `Show-ADTInstallationPrompt` and `Show-ADTInstallationProgress`, branching on each backend result's `.Success`. |

All UI goes through PSADT's own client/server dialog pipeline. There is **no
custom WPF window** — an earlier WPF approach failed because a hand-rolled
`ShowDialog()` cannot marshal cleanly through PSADT's separate dialog process.

### Transport model

Registry work runs **locally on the target** via PowerShell Remoting
(`Invoke-Command -ComputerName ... -Credential ...`). This avoids any
dependency on the RemoteRegistry service. The credentials entered in the UI are
passed as a `PSCredential` to every remote call, so the tool works regardless
of the identity the PSADT host process runs as, as long as the entered account
has rights on the target.

---

## 3. Prerequisites

- **PSADT v4.1.x** deployed (tested on 4.1.8). Note the version caveat in §8.
- The tool must run in **Interactive** mode (a user is logged on to answer the
  dialogs). The PSADT log will show `Installation is running in [Interactive] mode`.
- **WinRM enabled on target PCs.** In a domain this is usually set by GPO. If a
  target has WinRM off, Connect / Read / Delete all fail through the same
  channel — the Failed screen covers it.
- The **operator's domain account** must have, on the target PC:
  - local administrator rights (for HKLM deletes and reboot), and
  - WinRM reachability.
  A normal unprivileged account authenticates at the domain step but then fails
  at Connect/Delete.

---

## 4. Configuration (the only per-environment edits)

### 4.1 Domain mapping

```powershell
function Resolve-UCMDomain {
    param([string]$Number)
    switch ($Number) {
        '1'     { 'dom1.example.local' }   # <-- replace with your real FQDNs
        '2'     { 'dom2.example.local' }
        '3'     { 'dom3.example.local' }
        '4'     { 'dom4.example.local' }
        default { $null }
    }
}
```

Find your real domain FQDN by running, on a domain-joined machine:

```powershell
$env:USERDNSDOMAIN
```

Put that value in place of `dom1.example.local`. Until you do, AD validation
cannot reach a real domain controller and login will always fail regardless of
the password.

### 4.2 Registry targets

```powershell
$script:UCMTargets = @(
    [pscustomobject]@{ Index=1; Label='Example App Cache';   Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp\Cache';   Name='' }
    [pscustomobject]@{ Index=2; Label='Broken Policy Value';  Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp';         Name='BadPolicy' }
    # ...
)
```

Field rules:

- **`Hive`** — `HKEY_LOCAL_MACHINE` (machine-wide) or `HKEY_USERS` (a specific
  user by SID).
- **`Path`** — subkey path, no leading backslash.
- **`Name`** — empty string `''` deletes the **whole key** (recursive);
  a value name deletes just that **value**.
- **`Index`** — the number the operator types to select the target. Keep unique.

**Per-user (HKCU) keys:** you cannot open HKCU of another user remotely. Use
`HKEY_USERS\<SID>\...` and resolve the target user's SID first (e.g. from their
logged-on session). The remote session runs as the operator's admin account,
not the logged-on user, so the SID substitution is required.

---

## 5. The wizard flow (state machine)

States and transitions:

```
Login ──Login──> Domain ──Next──> User ──Next──> Password
                                                     │
                                            (Analyzing = AD auth)
                                                     │ success
                                                     v
                                                  EnterPC ──Connect(WinRM)──> Read
                                                     │                          │
                                                     │                    (Read registry)
                                                     │                          v
                                                     │                       RegList ──Delete──> Reboot
                                                     │                                              │
                                                     │                                     (shutdown /r /t 60)
                                                     │                                              v
                                                     │                                            Done
                                                     │                                          │      │
                                                     └────────────── Start New ─────────────────┘   Close
                                                                                                       │
                                                                                                     Exit

Any backend failure ──> Failed ──Try Again──> (the state that failed)
                                └──Cancel────> Login
```

Screen-by-screen:

| State | Dialog | Backend call | On success | On fail |
|-------|--------|--------------|------------|---------|
| `Login` | Buttons: Login / Cancel | — | Domain | Exit |
| `Domain` | Input (default `1`), lists domains 1–4 | `Resolve-UCMDomain` | User | Failed |
| `User` | Input | — | Password | Login (if blank) |
| `Password` | Input (masked if supported) | `Test-UCMCredential` | EnterPC | Failed |
| `EnterPC` | Input, buttons Connect / Cancel | `Test-UCMConnection` | Read | Failed |
| `Read` | Buttons Read / Cancel | `Get-UCMRegistryData` | RegList | Failed |
| `RegList` | Input (list shown), Delete / Cancel | `Remove-UCMRegistryData` | Reboot | Failed |
| `Reboot` | Buttons Reboot / Close | `Restart-UCMComputer` | Done | Failed |
| `Done` | Buttons Start New / Close | — | EnterPC | Exit |
| `Failed` | Buttons Try Again / Cancel | — | `$retryState` | Login |

---

## 6. Backend functions

All return `[pscustomobject]@{ Success = <bool>; Message = <string>; ... }`.

### `Test-UCMCredential -DomainFqdn -User -PlainPw`
Validates credentials against AD using
`System.DirectoryServices.AccountManagement.PrincipalContext.ValidateCredentials`.
Accepts SAM (`vikas`), UPN (`vikas@domain`), or down-level (`DOM\vikas`).

### `Test-UCMConnection -ComputerName -Credential`
Opens a WinRM session and returns the remote `$env:COMPUTERNAME`. This is the
real reachability test (ping is not relied upon, since ICMP may be blocked).

### `Get-UCMRegistryData -ComputerName -Credential`
Reads every target and returns `.Items` (Index, Label, Exists, Value). It logs
each value **before** any deletion via `Write-ADTLogEntry` — this snapshot is
your record of what existed, since registry deletes are irreversible.

### `ConvertTo-UCMIndexList -Selection`
Parses operator input like `2,4,5` (or `2 4 5`) into a validated `int[]`,
discarding anything not in the target list.

### `Remove-UCMRegistryData -ComputerName -Credential -Indices`
Deletes the chosen targets. Whole-key targets use `Remove-Item -Recurse`; value
targets use `Remove-ItemProperty`. Returns per-item results and an aggregate
`Success` (true only if every deletion succeeded). Each action is logged.

### `Restart-UCMComputer -ComputerName -Credential`
Runs `shutdown.exe /r /t 60 /c '...'` on the target — a real reboot with a
60-second warning to the logged-on user.

### `Get-UCMInputText -Result`
Helper that extracts the typed text from an input dialog result. It is
defensive across builds: it handles a plain string, a `SecureString`, and an
object exposing any of `Text / Input / InputText / Value / Response /
SelectedItem`, falling back to `.ToString()`.

---

## 7. Integration into the PSADT template

1. Open `Invoke-AppDeployToolkit.ps1`.
2. Remove any `."$($adtSession.DirFiles)\app2.ps1"` dot-source line — this
   tool replaces the external-script approach.
3. Paste the whole UCM block into the **Install** section.
4. Edit `Resolve-UCMDomain` and `$script:UCMTargets` (§4).
5. Save the file as **UTF-8** (see §8 for why this matters).

---

## 8. Version caveats and known pitfalls

These are the issues encountered while building the tool and how they were
resolved — worth keeping for the next person.

### 8.1 `-SecureInput` does not exist in 4.1.8
The masked-password parameter (`-SecureInput`) was added *after* 4.1.8, so on
this build the Password screen must use a plain `-RequestInput` box. Trade-off:
the password is visible on screen while typing. Two options:

- **Plain box (works now):** remove `-SecureInput` from the Password state.
- **Native credential prompt (masked):** if your build has a credential cmdlet,
  use it. Check with:
  ```powershell
  Get-Command -Module PSAppDeployToolkit *Credential*, *SecureInput*
  ```
  and wire the Password screen to whatever it returns (returns a real
  `PSCredential`, so plaintext is never handled).

### 8.2 `-DefaultValue` rejects empty/whitespace
The parameter is validated as not-null-or-whitespace. Only prefill it where you
have a real default (e.g. Domain = `1`). Everywhere else use bare
`-RequestInput`. Never pass `-DefaultValue ''` — it throws.

### 8.3 Non-ASCII characters break the script on save
An em dash (`—`) or similar, saved as ANSI instead of UTF-8, gets mangled into
bytes that PowerShell misreads as a closing quote — producing a cascade of
"unexpected token", "missing `}`", and "unterminated string" parse errors from
a single character. **Keep the script ASCII-only** and save as UTF-8. Use a
plain hyphen `-` in UI text, not an em dash.

### 8.4 PowerShell arguments are space-separated, not comma-separated
Passing `SomeFunction 0,20,0,0` sends **one array**, not four values. This bit
an earlier helper. Native PSADT dialogs sidestep it, but keep it in mind for any
custom helper you add.

### 8.5 Interactive mode required
If the deployment is non-interactive, `Show-ADTInstallationPrompt` self-bypasses
and returns nothing, so the state machine cannot advance. This tool is intended
to be run interactively.

---

## 9. Testing safely

Do a self-contained end-to-end run before pointing it at anyone else's PC:

1. Fix `Resolve-UCMDomain` with your real FQDN (`$env:USERDNSDOMAIN`).
2. Log in with your own admin credentials.
3. At **Enter PC Name**, use your own hostname or `localhost` so Connect and
   Read succeed against a box you control.
4. With placeholder registry targets, Read will show everything as
   `[absent]` — that is expected, not a bug, until you set real keys.
5. **Do not press Reboot on your own workstation.** `Restart-UCMComputer` fires
   a real `shutdown /r` on success. Test the reboot path only against a
   throwaway VM or a spare machine you can restart.

### Isolating the reboot path
To test Connect → Reboot without Read/Delete, do **not** just comment out the
Read/RegList blocks — the `EnterPC` success line still points at `Read`, so the
loop would jump to a commented-out (missing) state and exit. Instead, redirect
the transition:

```powershell
# in EnterPC, on success:
if ($conn.Success) { $state='Reboot' } else { $retryState='EnterPC'; $script:UCMFailMsg=$conn.Message; $state='Failed' }
```

Or add a flag at the top and branch on it, which is cleaner to revert:

```powershell
$UCMSkipRegistry = $true   # TEST: jump Connect -> Reboot
# ...
if ($conn.Success) { $state = if ($UCMSkipRegistry) { 'Reboot' } else { 'Read' } } else { ... }
```

---

## 10. Security notes

- **Credentials:** entered as a `PSCredential` and passed only to remote calls.
  With the plain-box workaround (§8.1) the password is briefly on screen; prefer
  the native credential prompt once available.
- **Least privilege:** the operator account should have only the rights it needs
  on target PCs. Anyone who can run the tool can delete registry keys and reboot
  machines — treat access accordingly.
- **Audit trail:** the pre-deletion read snapshot and every delete action are
  written to the PSADT log via `Write-ADTLogEntry -Source 'UCM'`. Keep those
  logs; they are the only record of what was removed.
- **Irreversibility:** registry deletes cannot be undone. Consider exporting a
  `.reg`/JSON restore point from the read snapshot before deleting in
  production.

---

## 11. Troubleshooting quick reference

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Parse errors: unexpected token / missing `}` / unterminated string | Non-ASCII char saved as ANSI | Save UTF-8, keep ASCII-only (§8.3) |
| `Cannot convert System.Object[] to System.Double` | Comma-passed args to a helper | Use space-separated args or accept an array |
| `No parameter found for SecureInput` | 4.1.8 lacks `-SecureInput` | Remove it or use credential prompt (§8.1) |
| Dialog never appears / returns nothing | Non-interactive mode | Run interactively (§8.5) |
| Login fails with correct password | Placeholder domain FQDN | Set real FQDN in `Resolve-UCMDomain` (§4.1) |
| Connect fails on a valid PC | WinRM off / no rights | Enable WinRM; use an admin account (§3) |
| Reaches a state that does nothing, then exits | A transition points at a commented-out state | Redirect the transition (§9) |
