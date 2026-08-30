# PSADT Practice Deployments — Final Set (6 packages)

Each folder here is a **complete, self-contained PSADT package** — its own
copy of `PSAppDeployToolkit\`, `Config\`, `Assets\`, `Strings\`,
`SupportFiles\`, `Invoke-AppDeployToolkit.exe`, and the real installer under
`Files\`. This mirrors how PSADT packages are actually shipped in the real
world (SCCM/Intune Win32 apps are self-contained too) — nothing here is
scaled-down or simulated. Running Install/Uninstall genuinely
installs/uninstalls the app on your machine.

**Three script files per app, kept deliberately separate:**
- `Invoke-AppDeployToolkit.ps1` — stays close to the stock PSADT template (param block, module import, session open/close). Not app-specific, you shouldn't need to touch this.
- `AppConfig.ps1` — **the only file you edit for a new app.** Nothing but values: `$adtSession` (vendor, name, version, log name...), the installer filename/type, install switches, detection name, process to watch/close, and — for the dependency packages — the dependent-app list and detection method.
- `InstallLogic.ps1` (single-app packages) or `DependencyUpdateLogic.ps1` (dependency-update packages) — the standard `Install-ADTDeployment` / `Uninstall-ADTDeployment` / `Repair-ADTDeployment` pattern, written generically against the `AppConfig.ps1` values. No app-specific strings in here — same file, unmodified, across every package of that type in this set.

`Invoke-AppDeployToolkit.ps1` dot-sources both (`. "$PSScriptRoot\AppConfig.ps1"` then the logic file) early on, which runs them in the same scope so their variables and functions are visible to the rest of the launcher.


Every package combines all five practice-lab topics: **Part 1** (UI),
**Part 2** (logging, one dedicated `<App>.log` per package), **Part 3**
(a registry marker tree under `HKLM:\SOFTWARE\PSADT-Practice\<App>`),
**Part 4** (`Get-ADTApplication` detection before *and* after install),
**Part 5** (real running-process close/block — most visible in 5 and 6).
Packages 3 and 4 additionally demonstrate the **shared-dependency update
workflow**: detect an update is needed, detect which apps depend on it,
confirm with the user naming what needs to close, force-close them, install,
then show the right success/restart message.

Each folder has its own `README.md` with exact test commands and
verification steps — start there.

---

## Suggested order

1. **1, 2** — plain MSI and Inno EXE, confirms your setup works end to end.
2. **5, 6** — a second MSI and second Inno example, plus the real close/block flow.
3. **3, 4** — the dependency-update pattern, once the basics feel solid.

For each: run Install, verify (log file / registry marker / `Get-ADTApplication`
/ the real app itself), then run Uninstall and confirm the registry marker
tree and the app both disappear (except Package 3, which intentionally
doesn't support uninstall — see its README, .NET Framework 3.5 is a Windows
feature, not a removable app).

---

## Real issues found and fixed while building/testing these (worth knowing if you edit them)

**1. UTF-8 BOM.** Every `.ps1` file uses em dashes (—) in comments/messages.
Saved without a UTF-8 BOM, **Windows PowerShell 5.1** (what
`Invoke-AppDeployToolkit.exe` launches under the hood) misreads those
non-ASCII characters and corrupts nearby quotes/braces — producing
confusing "missing terminator" / "missing closing brace" errors nowhere
near the real problem. All files here are saved with a UTF-8 BOM and
verified (via the real PowerShell parser, not just eyeballing) to parse
cleanly. **If you edit any of them later in an editor that strips the BOM
and use a non-ASCII character, you can reintroduce this** — stick to plain
ASCII in your own edits, or confirm your editor preserves "UTF-8 with BOM"
for `.ps1` files.

**2. `AppProcessesToClose` at session level silently forces Silent mode.**
`Open-ADTSession` checks this property **before** your Install/Uninstall
functions run, and force-switches the whole deployment to Silent (no UI at
all) if none of the listed processes are currently running. Every
`AppConfig.ps1` here keeps `AppProcessesToClose = @()` in `$adtSession` and
instead tracks watched processes in a separate `$ProcessToWatch` (or
`$DependentApps` in 3/4) variable, read only by the logic file's functions.

**3. `Show-ADTInstallationPrompt` returns `$null` in Silent mode — a real
silent-deployment bug, found by actually testing it.** Packages 3 and 4 use
a confirmation prompt (`-ButtonRightText 'Install' -ButtonLeftText 'Cancel'`)
to gate whether to proceed. The original code checked `-ne 'Install'` to
decide whether to abort — but `Show-ADTInstallationPrompt` returns `$null`
under `-DeployMode Silent` (verified: `"Bypassing Show-ADTInstallationPrompt
[Mode: Silent]"` in the log), not either button's text, since nobody's there
to click anything. `$null -ne 'Install'` is `$true`, so a real silent
deployment would have logged "aborting" and **skipped the entire install**.
Fixed: the check is now `-eq 'Cancel'` — only an actual interactive Cancel
click aborts; Silent mode's `$null` correctly falls through and proceeds.
Also confirmed directly: `Show-ADTInstallationRestartPrompt` does **not**
force a restart in Silent mode either (`"Skipping restart because the
deploy mode is set to [Silent]"`) — the real restart, in a real silent
deployment, is driven by the exit code (1641/3010) `Close-ADTSession` passes
back to the parent process (SCCM/Intune), which orchestrates the reboot on
its own schedule. That's the correct pattern.

None of Packages 1, 2, 5, or 6 had this issue (checked directly) — it was
isolated to the two confirmation-prompt-gated dependency packages.
