<#
Standard install/uninstall/repair logic. Generic across apps — reads
everything app-specific from AppConfig.ps1 (dot-sourced before this file).
Do not hardcode app values here; add a config variable instead.
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

    if ($ProcessToWatch) {
        $running = Get-ADTRunningProcesses -ProcessObjects @($ProcessToWatch)
        if ($running) {
            Write-ADTLogEntry -Message "$($adtSession.AppName) is currently running (PID(s): $($running.ProcessId -join ', '))." -Severity Warning -Source 'CloseApps'
            $welcomeParams = @{ CloseProcesses = @($ProcessToWatch); AllowDefer = $true; DeferTimes = 3; CloseProcessesCountdown = 60; CheckDiskSpace = $true; PersistPrompt = $true }
            if ($BlockExecution) { $welcomeParams['BlockExecution'] = $true }
            Show-ADTInstallationWelcome @welcomeParams
        }
        else {
            Write-ADTLogEntry -Message "$($adtSession.AppName) is not running." -Source 'CloseApps'
            Show-ADTInstallationWelcome -CheckDiskSpace
        }
    }
    else {
        Show-ADTInstallationWelcome -CheckDiskSpace
    }

    Show-ADTInstallationProgress -StatusMessage "Checking for an existing $($adtSession.AppName) installation..." -StatusBarPercentage 0

    $existingApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
    if ($existingApp) {
        Write-ADTLogEntry -Message "Detected existing install: $($existingApp.DisplayName) v$($existingApp.DisplayVersion)" -Source 'Detection'
    }
    else {
        Write-ADTLogEntry -Message "No existing $($adtSession.AppName) installation detected." -Source 'Detection'
    }

    Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'LastInstallAttempt' -Value (Get-Date -Format 'u') -Type String
    Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallCompleted'   -Value 0 -Type DWord


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage "Installing $($adtSession.AppName) ($InstallerType, silent)..." -StatusBarPercentage 40

    if ($InstallerType -eq 'MSI') {
        Write-ADTLogEntry -Message 'Starting MSI install via Start-ADTMsiProcess.' -Source 'Install'
        Start-ADTMsiProcess -Action Install -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile)
    }
    else {
        Write-ADTLogEntry -Message "Starting Start-ADTProcess with args: $InstallArgs" -Source 'Install'
        Start-ADTProcess -FilePath (Join-Path -Path $adtSession.DirFiles -ChildPath $InstallerFile) -ArgumentList $InstallArgs
    }

    Show-ADTInstallationProgress -StatusMessage 'Install command finished, verifying...' -StatusBarPercentage 80


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    if ($BlockExecution) { Unblock-ADTAppExecution }

    $installedApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
    if ($installedApp) {
        Write-ADTLogEntry -Message "Post-install detection confirms: $($installedApp.DisplayName) v$($installedApp.DisplayVersion)" -Severity Success -Source 'PostInstall'
        Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallCompleted' -Value 1 -Type DWord
        Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstalledVersion' -Value $installedApp.DisplayVersion -Type String
        Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstallDate'      -Value (Get-Date -Format 'u') -Type String
        if ($InstallerType -eq 'MSI') {
            Set-ADTRegistryKey -LiteralPath $practiceRegKey -Name 'InstalledProductCode' -Value ([String]$installedApp.ProductCode) -Type String
        }
    }
    else {
        Write-ADTLogEntry -Message "Post-install detection did NOT find $($adtSession.AppName) — install may have failed." -Severity Error -Source 'PostInstall'
    }

    Close-ADTInstallationProgress

    $summaryCompleted = Get-ADTRegistryKey -Path $practiceRegKey -Name 'InstallCompleted'
    $summaryVersion    = Get-ADTRegistryKey -Path $practiceRegKey -Name 'InstalledVersion'

    Show-ADTInstallationPrompt -Message "$($adtSession.AppName) install finished.`n`nRegistry marker InstallCompleted = $summaryCompleted`nRegistry marker InstalledVersion = $summaryVersion`n`nLog file: $($adtSession.LogPath)\$($adtSession.LogName)" -ButtonRightText 'OK'
    Show-ADTBalloonTip -BalloonTipTitle $adtSession.AppName -BalloonTipText 'Install complete.' -BalloonTipIcon Info
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    if ($ProcessToWatch) {
        $running = Get-ADTRunningProcesses -ProcessObjects @($ProcessToWatch)
        if ($running) {
            $welcomeParams = @{ CloseProcesses = @($ProcessToWatch); CloseProcessesCountdown = 60 }
            if ($BlockExecution) { $welcomeParams['BlockExecution'] = $true }
            Show-ADTInstallationWelcome @welcomeParams
        }
    }

    Show-ADTInstallationProgress -StatusMessage "Checking for $($adtSession.AppName) before uninstalling..." -StatusBarPercentage 0

    $existingApp = Get-ADTApplication -Name $DetectName -NameMatch $DetectNameMatch -ErrorAction SilentlyContinue
    if (-not $existingApp) {
        Write-ADTLogEntry -Message "$($adtSession.AppName) is not installed — nothing to uninstall." -Severity Warning -Source 'Detection'
        Close-ADTInstallationProgress
        Show-ADTInstallationPrompt -Message "$($adtSession.AppName) is not currently installed. Nothing to do." -ButtonRightText 'OK' -Icon Information
        return
    }

    Write-ADTLogEntry -Message "Found $($existingApp.DisplayName) v$($existingApp.DisplayVersion) — will uninstall." -Source 'Detection'


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    if ($InstallerType -eq 'MSI') {
        Show-ADTInstallationProgress -StatusMessage "Uninstalling $($adtSession.AppName) (MSI, via ProductCode)..." -StatusBarPercentage 40
        Start-ADTMsiProcess -Action Uninstall -FilePath $existingApp.ProductCode
    }
    else {
        Show-ADTInstallationProgress -StatusMessage "Uninstalling $($adtSession.AppName)..." -StatusBarPercentage 40
        if ($existingApp.QuietUninstallStringFilePath) {
            Start-ADTProcess -FilePath $existingApp.QuietUninstallStringFilePath -ArgumentList $existingApp.QuietUninstallStringArgumentList
        }
        else {
            Write-ADTLogEntry -Message 'No QuietUninstallString found — falling back to the configured install switches on UninstallStringFilePath.' -Severity Warning -Source 'Uninstall'
            Start-ADTProcess -FilePath $existingApp.UninstallStringFilePath -ArgumentList $InstallArgs
        }
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    if ($BlockExecution) { Unblock-ADTAppExecution }

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
