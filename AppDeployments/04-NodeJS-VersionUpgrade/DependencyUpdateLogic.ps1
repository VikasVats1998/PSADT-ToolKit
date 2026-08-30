<#
Standard shared-dependency update logic. Generic across apps — reads
everything app-specific from AppConfig.ps1 (dot-sourced before this file).
Do not hardcode app values here; add a config variable instead.

Pattern: detect whether the dependency needs installing -> detect which
apps depend on it -> confirm with the user, naming what needs to close ->
forcefully close those apps -> install -> check whether a restart is
required -> show the right final message.

Uninstall-ADTDeployment assumes $DetectionMethod = 'Application' when
$SupportsUninstall is $true (Get-ADTApplication-based). A Registry-detected
dependency (e.g. a Windows feature) has no supported uninstall path here by
design — see $SupportsUninstall in AppConfig.ps1.
#>

$practiceRegKey = "HKLM:\SOFTWARE\PSADT-Practice\$($adtSession.InstallName)"

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    if ($DetectionMethod -eq 'Registry') {
        $alreadySatisfied = Test-ADTRegistryValue -Key $DependencyRegPath -Name $DependencyRegInstalledValueName
        if ($alreadySatisfied) {
            $currentVersion = Get-ADTRegistryKey -Path $DependencyRegPath -Name $DependencyRegVersionValueName
            Write-ADTLogEntry -Message "$($adtSession.AppName) already present (Version $currentVersion)." -Source 'DependencyCheck'
        }
        else {
            Write-ADTLogEntry -Message "$($adtSession.AppName) is not currently installed." -Source 'DependencyCheck'
        }
        $updateNeeded = -not $alreadySatisfied
    }
    else {
        $existingApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
        if ($existingApp) {
            Write-ADTLogEntry -Message "Detected existing install: $($existingApp.DisplayName) v$($existingApp.DisplayVersion)" -Source 'DependencyCheck'
            try {
                $updateNeeded = [Version]$SimulatedAvailableVersion -gt [Version]$existingApp.DisplayVersion
            }
            catch {
                Write-ADTLogEntry -Message "Could not parse '$($existingApp.DisplayVersion)' for comparison — assuming an update is due." -Severity Warning -Source 'DependencyCheck'
                $updateNeeded = $true
            }
        }
        else {
            Write-ADTLogEntry -Message "$($adtSession.AppName) is not currently installed." -Source 'DependencyCheck'
            $updateNeeded = $true
        }
    }

    if (-not $updateNeeded -and -not $ForcePracticeRun) {
        Write-ADTLogEntry -Message 'Dependency already satisfied — skipping.' -Source 'DependencyCheck'
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) is already up to date. No action needed." -ButtonRightText 'OK' -Icon Information
        return
    }
    if (-not $updateNeeded -and $ForcePracticeRun) {
        Write-ADTLogEntry -Message '$ForcePracticeRun is $true — running the full flow anyway.' -Severity Warning -Source 'DependencyCheck'
    }

    $runningDependents = Get-ADTRunningProcesses -ProcessObjects $DependentApps
    $runningNames = if ($runningDependents) { $runningDependents.ProcessDescription -join ', ' } else { 'none currently running' }

    # Show-ADTInstallationPrompt returns $null under -DeployMode Silent (nobody
    # there to click) — gate on -eq 'Cancel', not -ne 'Install', so a real
    # silent run falls through and proceeds instead of being read as a cancel.
    $proceed = Show-ADTInstallationPrompt -Message "$($adtSession.AppName) needs to be installed on this machine.`n`nApps that depend on it: $runningNames`n`nPlease save your work in the apps listed above, then click Install to continue." -ButtonRightText 'Install' -ButtonLeftText 'Cancel' -Icon Information

    if ($proceed -eq 'Cancel') {
        Write-ADTLogEntry -Message 'User clicked Cancel at the confirmation prompt — aborting.' -Severity Warning -Source 'UserChoice'
        Show-ADTInstallationPrompt -Message 'Update cancelled — no changes were made.' -ButtonRightText 'OK'
        return
    }

    # No -AllowDefer: this models a mandatory dependency update, not an
    # optional app install the user can postpone.
    if ($runningDependents) {
        Show-ADTInstallationWelcome -CloseProcesses $DependentApps -CloseProcessesCountdown 20 -BlockExecution -PersistPrompt
    }

    Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'LastInstallAttempt' -Value (Get-Date -Format 'u') -Type String
    Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallCompleted'   -Value 0 -Type DWord


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage "Installing $($adtSession.AppName)..." -StatusBarPercentage 40

    if ($InstallerType -eq 'MSI') {
        Start-ADTMsiProcess -Action Install -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile)
        # Start-ADTMsiProcess -PassThru's return shape isn't confirmed the way
        # Start-ADTProcess's is — see README for why the exit code isn't
        # checked manually below for MSI installers.
        $exitCode = $null
    }
    else {
        $installResult = Start-ADTProcess -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile) -ArgumentList $InstallArgs -PassThru
        $exitCode = $installResult.ExitCode
    }

    Show-ADTInstallationProgress -StatusMessage 'Install command finished, verifying...' -StatusBarPercentage 80


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Unblock-ADTAppExecution

    if ($DetectionMethod -eq 'Registry') {
        $nowSatisfied = Test-ADTRegistryValue -Key $DependencyRegPath -Name $DependencyRegInstalledValueName
        if ($nowSatisfied) {
            $finalVersion = Get-ADTRegistryKey -Path $DependencyRegPath -Name $DependencyRegVersionValueName
            Write-ADTLogEntry -Message "$($adtSession.AppName) confirmed present (Version $finalVersion)." -Severity Success -Source 'PostInstall'
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallCompleted' -Value 1 -Type DWord
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstalledVersion' -Value $finalVersion -Type String
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallDate'      -Value (Get-Date -Format 'u') -Type String
        }
        else {
            Write-ADTLogEntry -Message "$($adtSession.AppName) still not detected after the install attempt." -Severity Error -Source 'PostInstall'
        }
    }
    else {
        $installedApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
        if ($installedApp) {
            Write-ADTLogEntry -Message "Post-install detection confirms: $($installedApp.DisplayName) v$($installedApp.DisplayVersion)" -Severity Success -Source 'PostInstall'
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallCompleted' -Value 1 -Type DWord
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstalledVersion' -Value $installedApp.DisplayVersion -Type String
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallDate'      -Value (Get-Date -Format 'u') -Type String
        }
        else {
            Write-ADTLogEntry -Message "Post-install detection did NOT find $($adtSession.AppName) — install may have failed." -Severity Error -Source 'PostInstall'
        }
    }

    Close-ADTInstallationProgress

    if ($null -ne $exitCode -and $exitCode -in $adtSession.AppRebootExitCodes) {
        Write-ADTLogEntry -Message "Installer returned exit code $exitCode — a restart is required to complete this install." -Severity Warning -Source 'PostInstall'
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) installed successfully. A restart is required to finish." -ButtonRightText 'OK' -Icon Information
        Show-ADTInstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 30
    }
    else {
        Write-ADTLogEntry -Message 'No restart required.' -Source 'PostInstall'
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) installed successfully. No restart required." -ButtonRightText 'OK' -Icon Information
    }

    Show-ADTBalloonTip -BalloonTipTitle $adtSession.AppName -BalloonTipText 'Dependency update complete.' -BalloonTipIcon Info
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    if (-not $SupportsUninstall) {
        $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
        Write-ADTLogEntry -Message "This package does not support uninstalling $($adtSession.AppName) — see README." -Severity Warning -Source 'Uninstall'
        Remove-ADTRegistryKey -Path $practiceRegKey -Recurse -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Removed practice registry tree: $practiceRegKey" -Source 'Uninstall'
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) was left installed on purpose.`n`nOnly this package's practice registry markers were cleaned up." -ButtonRightText 'OK' -Icon Information
        return
    }

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Show-ADTInstallationProgress -StatusMessage "Checking for $($adtSession.AppName) before uninstalling..." -StatusBarPercentage 0

    $existingApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
    if (-not $existingApp) {
        Write-ADTLogEntry -Message "$($adtSession.AppName) is not installed — nothing to uninstall." -Severity Warning -Source 'Detection'
        Close-ADTInstallationProgress
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) is not currently installed. Nothing to do." -ButtonRightText 'OK' -Icon Information
        return
    }

    Write-ADTLogEntry -Message "Found $($existingApp.DisplayName) v$($existingApp.DisplayVersion), ProductCode $($existingApp.ProductCode) — will uninstall." -Source 'Detection'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage "Uninstalling $($adtSession.AppName)..." -StatusBarPercentage 40

    if ($InstallerType -eq 'MSI') {
        Start-ADTMsiProcess -Action Uninstall -FilePath $existingApp.ProductCode
    }
    elseif ($existingApp.QuietUninstallStringFilePath) {
        Start-ADTProcess -FilePath $existingApp.QuietUninstallStringFilePath -ArgumentList $existingApp.QuietUninstallStringArgumentList
    }
    else {
        Write-ADTLogEntry -Message 'No QuietUninstallString found — falling back to the configured install switches on UninstallStringFilePath.' -Severity Warning -Source 'Uninstall'
        Start-ADTProcess -FilePath $existingApp.UninstallStringFilePath -ArgumentList $InstallArgs
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    $stillPresent = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
    if ($stillPresent) {
        Write-ADTLogEntry -Message "$($adtSession.AppName) still detected after uninstall attempt." -Severity Error -Source 'PostUninstall'
    }
    else {
        Write-ADTLogEntry -Message "$($adtSession.AppName) no longer detected — uninstall confirmed." -Severity Success -Source 'PostUninstall'
    }

    Remove-ADTRegistryKey -Path $practiceRegKey -Recurse -ErrorAction SilentlyContinue
    Write-ADTLogEntry -Message "Removed practice registry tree: $practiceRegKey" -Source 'PostUninstall'

    Close-ADTInstallationProgress
    Show-ADTInstallationPrompt -Message "$($adtSession.AppName) uninstall finished and practice registry markers cleaned up." -ButtonRightText 'OK'
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )
    $adtSession.InstallPhase = $adtSession.DeploymentType
    Show-ADTInstallationProgress -StatusMessage "Repairing $($adtSession.AppName)..."

    if ($InstallerType -eq 'MSI') {
        Start-ADTMsiProcess -Action Repair -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile)
    }
    else {
        Start-ADTProcess -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile) -ArgumentList $InstallArgs
    }

    Close-ADTInstallationProgress
}
