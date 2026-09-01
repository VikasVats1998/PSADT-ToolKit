<#
.SYNOPSIS
    Interactive test harness for every PSAppDeployToolkit 4.1.8 UI function.

.DESCRIPTION
    Menu-driven script that exercises each cmdlet documented in
    PSADT-UI-Functions-Reference.md, one at a time, so you can visually
    confirm each dialog/prompt/notification works on this machine.

    Test targets used for the "close apps" style tests are, in order of
    preference: Notepad++ (falls back to Notepad), Microsoft Word (falls
    back to WordPad), and File Explorer.

    Run from the root of this template (next to the PSAppDeployToolkit folder):
        .\test.ps1

.NOTES
    Two menu items are marked DESTRUCTIVE / DANGER and are gated behind an
    extra typed confirmation because they have real side effects:
      [13] Show-ADTInstallationWelcome -Silent  -> silently KILLS the test apps, no save prompt
      [17] Show-ADTInstallationRestartPrompt with a live countdown -> will ACTUALLY REBOOT this
           machine if the dialog is left untouched until the countdown reaches zero.
    Everything else is safe to run repeatedly and only ever closes apps this
    script itself launched, after you interact with a dialog.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------
# Import the module from this template
# ------------------------------------------------------------------------
$moduleManifest = Join-Path $PSScriptRoot 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
if (-not (Test-Path $moduleManifest)) {
    throw "Could not find PSAppDeployToolkit.psd1 at '$moduleManifest'. Run this script from the template root."
}
Import-Module $moduleManifest -Force
Write-Host "PSAppDeployToolkit module loaded (v$((Import-Module $moduleManifest -PassThru -Force).Version))." -ForegroundColor Green

# ------------------------------------------------------------------------
# Test app helpers - Notepad++ / MS Word / File Explorer (with fallbacks)
# ------------------------------------------------------------------------
$script:LaunchedProcesses = @()

function Open-TestApps {
    $script:LaunchedProcesses = @()
    Write-Host "`nLaunching test applications..." -ForegroundColor Cyan

    # --- Notepad++ (fallback: Notepad) ---
    $npp = Get-Command notepad++.exe -ErrorAction SilentlyContinue
    if (-not $npp) {
        $npp = Get-Item "$env:ProgramFiles\Notepad++\notepad++.exe", "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($npp) {
        $nppPath = if ($npp.Source) { $npp.Source } else { $npp.FullName }
        Start-Process -FilePath $nppPath -ErrorAction Stop
        $script:LaunchedProcesses += @{ Name = 'notepad++'; Description = 'Notepad++' }
        Write-Host '  [OK] Launched Notepad++' -ForegroundColor DarkGray
    }
    else {
        Start-Process notepad.exe
        $script:LaunchedProcesses += @{ Name = 'notepad'; Description = 'Notepad (Notepad++ not installed - used fallback)' }
        Write-Host '  [!] Notepad++ not found - launched Notepad instead' -ForegroundColor DarkYellow
    }

    # --- Microsoft Word (fallback: WordPad) ---
    $word = Get-Command winword.exe -ErrorAction SilentlyContinue
    if (-not $word) {
        $word = Get-ChildItem "$env:ProgramFiles\Microsoft Office\root\Office*\WINWORD.EXE", "${env:ProgramFiles(x86)}\Microsoft Office\root\Office*\WINWORD.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($word) {
        $wordPath = if ($word.Source) { $word.Source } else { $word.FullName }
        Start-Process -FilePath $wordPath -ErrorAction Stop
        $script:LaunchedProcesses += @{ Name = 'winword'; Description = 'Microsoft Word' }
        Write-Host '  [OK] Launched Microsoft Word' -ForegroundColor DarkGray
    }
    else {
        try {
            Start-Process wordpad.exe -ErrorAction Stop
            $script:LaunchedProcesses += @{ Name = 'wordpad'; Description = 'WordPad (Word not installed - used fallback)' }
            Write-Host '  [!] Microsoft Word not found - launched WordPad instead' -ForegroundColor DarkYellow
        }
        catch {
            Write-Host '  [!] Neither Word nor WordPad could be launched - skipped' -ForegroundColor DarkYellow
        }
    }

    # --- File Explorer ---
    Start-Process explorer.exe
    $script:LaunchedProcesses += @{ Name = 'explorer'; Description = 'File Explorer' }
    Write-Host '  [OK] Launched File Explorer' -ForegroundColor DarkGray

    Start-Sleep -Seconds 2
}

function Confirm-Destructive {
    param([string]$Word, [string]$Warning)
    Write-Host "`n*** WARNING ***" -ForegroundColor Red
    Write-Host $Warning -ForegroundColor Red
    $answer = Read-Host "Type '$Word' (all caps) to proceed, or anything else to cancel"
    return $answer -ceq $Word
}

function Pause-Menu {
    Write-Host ''
    Read-Host 'Press Enter to return to the menu'
}

# ------------------------------------------------------------------------
# Individual UI tests (mirrors PSADT-UI-Functions-Reference.md)
# ------------------------------------------------------------------------

function Test-BalloonTip {
    Show-ADTBalloonTip -BalloonTipText 'This is a test balloon / toast notification.' -BalloonTipTitle 'PSADT UI Test' -BalloonTipIcon Info -Force
}

function Test-ProgressMarquee {
    Show-ADTInstallationProgress -StatusMessage "Testing the marquee progress dialog...`nThis will auto-close in 5 seconds."
    Start-Sleep -Seconds 5
    Close-ADTInstallationProgress
}

function Test-ProgressPercentage {
    foreach ($pct in 0, 25, 50, 75, 100) {
        Show-ADTInstallationProgress -StatusMessage 'Testing the percentage progress bar...' -StatusMessageDetail "$pct% complete" -StatusBarPercentage $pct
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 1
    Close-ADTInstallationProgress
}

function Test-PromptYesNo {
    $result = Show-ADTInstallationPrompt -Message 'Do you want to proceed with the installation?' -ButtonLeftText Yes -ButtonRightText No -Icon Question
    Write-Host "Button clicked: $result" -ForegroundColor Green
}

function Test-PromptThreeButtons {
    $result = Show-ADTInstallationPrompt -Message 'How are you feeling today?' -ButtonLeftText 'Good' -ButtonRightText 'Bad' -ButtonMiddleText 'Indifferent' -Icon Information
    Write-Host "Button clicked: $result" -ForegroundColor Green
}

function Test-PromptNoWait {
    Show-ADTInstallationPrompt -Message 'This prompt is non-blocking (-NoWait) - the console keeps running underneath it.' -ButtonLeftText 'OK' -Icon Information -NoWait
    Write-Host 'Console continued immediately - the dialog is still open on screen.' -ForegroundColor Green
}

function Test-PromptRequestInput {
    $result = Show-ADTInstallationPrompt -RequestInput -DefaultValue 'XXXX' -Message 'Please type in your favourite beer.' -ButtonRightText 'Submit'
    Write-Host 'Result returned:' -ForegroundColor Green
    $result | Format-List *
}

function Test-DialogBox {
    $result = Show-ADTDialogBox -Text 'Installation will take approximately 30 minutes. Do you wish to proceed?' -Buttons 'OkCancel' -DefaultButton 'Second' -Icon 'Exclamation' -NotTopMost
    Write-Host "Button clicked: $result" -ForegroundColor Green
}

function Test-HelpConsole {
    Write-Host 'Opening the help console in a new window - close it when done browsing.' -ForegroundColor Cyan
    Show-ADTHelpConsole
}

function Test-GetApplication {
    Write-Host "`nAll matches for 'Notepad++':" -ForegroundColor Cyan
    Get-ADTApplication -Name 'Notepad++' | Format-List DisplayName, DisplayVersion, Publisher, InstallDate, ProductCode

    Write-Host "`nAll matches for 'Microsoft' (first 5):" -ForegroundColor Cyan
    Get-ADTApplication -Name 'Microsoft' | Select-Object -First 5 DisplayName, DisplayVersion, Publisher | Format-Table -AutoSize

    $all = Get-ADTApplication
    Write-Host "`nTotal installed applications found: $($all.Count)" -ForegroundColor Green
}

function Test-UserNotificationState {
    $state = Get-ADTUserNotificationState
    Write-Host "Current user notification state: $state" -ForegroundColor Green
}

function Test-WelcomeCloseApps {
    Open-TestApps
    Write-Host "`nShowing Welcome dialog: prompts to close the 3 test apps, allows 2 deferrals, 2-min force-close countdown timer." -ForegroundColor Cyan
    Show-ADTInstallationWelcome -CloseProcesses $script:LaunchedProcesses -AllowDeferCloseProcesses -DeferTimes 2 -CloseProcessesCountdown 120 -PersistPrompt:$false
}

function Test-WelcomeSilentClose {
    if (-not (Confirm-Destructive -Word 'CLOSE' -Warning "This will SILENTLY KILL Notepad++/Notepad, Word/WordPad, and File Explorer with NO save prompt. Save any open work first.")) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }
    Open-TestApps
    Write-Host "`nSilently closing the test apps now..." -ForegroundColor Cyan
    Show-ADTInstallationWelcome -CloseProcesses $script:LaunchedProcesses -Silent
    Write-Host 'Done. (File Explorer/taskbar may briefly flicker as it restarts itself.)' -ForegroundColor Green
}

function Test-WelcomeBlockExecution {
    Open-TestApps
    Write-Host "`nShowing Welcome dialog with -BlockExecution: close the apps via the dialog, then this script will try to relaunch one of them to prove it's blocked, then automatically unblocks." -ForegroundColor Cyan
    try {
        Show-ADTInstallationWelcome -CloseProcesses $script:LaunchedProcesses -BlockExecution -CloseProcessesCountdown 90
        Write-Host "`nAttempting to relaunch Notepad while execution is blocked..." -ForegroundColor Cyan
        Start-Process notepad.exe -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host 'If blocking worked, Notepad either failed to open or showed a blocked-application message.' -ForegroundColor Green
    }
    finally {
        Write-Host 'Removing the execution block (Unblock-ADTAppExecution)...' -ForegroundColor Cyan
        Unblock-ADTAppExecution
    }
}

function Test-WelcomeDeferPersist {
    Write-Host "`nShowing Welcome dialog with -AllowDefer and -PersistPrompt (no CloseProcesses - just tests defer + persist behavior). The dialog will re-center itself repeatedly; use the Defer button to dismiss." -ForegroundColor Cyan
    Show-ADTInstallationWelcome -AllowDefer -DeferTimes 3 -DeferDeadline (Get-Date).AddDays(1) -PersistPrompt
}

function Test-RestartPromptNoCountdown {
    Write-Host "`nShowing restart prompt with NO countdown - it will NOT force a restart, just prompts. Close it manually / click a button." -ForegroundColor Cyan
    Show-ADTInstallationRestartPrompt -NoCountdown
}

function Test-RestartPromptCountdown {
    if (-not (Confirm-Destructive -Word 'REBOOT' -Warning "This shows a REAL restart countdown. If you do NOT click 'Minimize'/'Restart Later' or otherwise cancel before the timer hits zero, THIS MACHINE WILL REBOOT. Save all work first. You will have 90 seconds.")) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }
    Write-Host "Showing restart prompt with a 90-second countdown - interact with the dialog to cancel/defer it well before it reaches zero." -ForegroundColor Red
    Show-ADTInstallationRestartPrompt -CountdownSeconds 90 -CountdownNoHideSeconds 30
}

function Invoke-AllSafeTests {
    Test-BalloonTip; Pause-Menu
    Test-ProgressMarquee; Pause-Menu
    Test-ProgressPercentage; Pause-Menu
    Test-PromptYesNo; Pause-Menu
    Test-PromptThreeButtons; Pause-Menu
    Test-PromptNoWait; Pause-Menu
    Test-PromptRequestInput; Pause-Menu
    Test-DialogBox; Pause-Menu
    Test-HelpConsole; Pause-Menu
    Test-GetApplication; Pause-Menu
    Test-UserNotificationState; Pause-Menu
    Test-WelcomeCloseApps; Pause-Menu
    Test-WelcomeBlockExecution; Pause-Menu
    Test-WelcomeDeferPersist; Pause-Menu
    Test-RestartPromptNoCountdown; Pause-Menu
    Write-Host "`nAll safe tests complete. Items [13] and [17] are DESTRUCTIVE/DANGER and were skipped - run them individually if you want to test them." -ForegroundColor Yellow
}

# ------------------------------------------------------------------------
# Menu
# ------------------------------------------------------------------------
$menu = [ordered]@{
    '1'  = @{ Label = 'Show-ADTBalloonTip'; Action = ${function:Test-BalloonTip} }
    '2'  = @{ Label = 'Show-ADTInstallationProgress (marquee)'; Action = ${function:Test-ProgressMarquee} }
    '3'  = @{ Label = 'Show-ADTInstallationProgress (percentage bar)'; Action = ${function:Test-ProgressPercentage} }
    '4'  = @{ Label = 'Show-ADTInstallationPrompt (Yes/No)'; Action = ${function:Test-PromptYesNo} }
    '5'  = @{ Label = 'Show-ADTInstallationPrompt (3 buttons)'; Action = ${function:Test-PromptThreeButtons} }
    '6'  = @{ Label = 'Show-ADTInstallationPrompt (-NoWait)'; Action = ${function:Test-PromptNoWait} }
    '7'  = @{ Label = 'Show-ADTInstallationPrompt (-RequestInput)'; Action = ${function:Test-PromptRequestInput} }
    '8'  = @{ Label = 'Show-ADTDialogBox'; Action = ${function:Test-DialogBox} }
    '9'  = @{ Label = 'Show-ADTHelpConsole'; Action = ${function:Test-HelpConsole} }
    '10' = @{ Label = 'Get-ADTApplication (get app info)'; Action = ${function:Test-GetApplication} }
    '11' = @{ Label = 'Get-ADTUserNotificationState'; Action = ${function:Test-UserNotificationState} }
    '12' = @{ Label = 'Show-ADTInstallationWelcome - close Notepad++/Word/Explorer (prompt + defer + countdown timer)'; Action = ${function:Test-WelcomeCloseApps} }
    '13' = @{ Label = 'Show-ADTInstallationWelcome -Silent   [DESTRUCTIVE - silently kills test apps]'; Action = ${function:Test-WelcomeSilentClose} }
    '14' = @{ Label = 'Show-ADTInstallationWelcome -BlockExecution (auto-unblocks after)'; Action = ${function:Test-WelcomeBlockExecution} }
    '15' = @{ Label = 'Show-ADTInstallationWelcome -AllowDefer -PersistPrompt'; Action = ${function:Test-WelcomeDeferPersist} }
    '16' = @{ Label = 'Show-ADTInstallationRestartPrompt -NoCountdown (safe)'; Action = ${function:Test-RestartPromptNoCountdown} }
    '17' = @{ Label = 'Show-ADTInstallationRestartPrompt -CountdownSeconds   [DANGER - can trigger a real reboot]'; Action = ${function:Test-RestartPromptCountdown} }
    'A'  = @{ Label = 'Run ALL safe tests in sequence (skips 13 and 17)'; Action = ${function:Invoke-AllSafeTests} }
    'Q'  = @{ Label = 'Quit'; Action = $null }
}

do {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host " PSAppDeployToolkit 4.1.8 - UI Function Test Harness" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    foreach ($key in $menu.Keys) {
        $label = $menu[$key].Label
        $color = if ($label -match 'DESTRUCTIVE|DANGER') { 'Red' } else { 'White' }
        Write-Host ("  [{0,2}] {1}" -f $key, $label) -ForegroundColor $color
    }
    $choice = (Read-Host "`nEnter a test number/letter").Trim().ToUpper()

    if ($menu.Contains($choice)) {
        if ($choice -eq 'Q') { break }
        try {
            & $menu[$choice].Action
        }
        catch {
            Write-Host "Test failed: $_" -ForegroundColor Red
        }
        if ($choice -ne 'A') { Pause-Menu }
    }
    else {
        Write-Host 'Invalid selection.' -ForegroundColor Yellow
    }
} while ($true)

Write-Host "`nExiting test harness. Note: this script never opened an ADT session, so there is nothing to close." -ForegroundColor Cyan
