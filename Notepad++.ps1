#===============================================================================
# Install.ps1  -  Notepad++ 8.9.2 (stufenweise, neustart-resistent)
# Aufruf per Dot-Sourcing aus Invoke-AppDeployToolkit.ps1
#===============================================================================

#--- Variablen -----------------------------------------------------------------
$AppName     = 'Notepad++'
$AppVer      = '8.9.2'
$Source      = "Deploy-$AppName"
$StageKey    = "HKLM:\SOFTWARE\PSADT\Stages\$AppName"
$PkgPersist  = "$env:ProgramData\TechKalu\Packages\$AppName"
$LogFilePath = "$env:SystemDrive\Logs"
$LogFile     = "$($AppName)_$($adtSession.DeploymentType).log"
if (-not (Test-Path $LogFilePath)) { New-Item -Path $LogFilePath -ItemType Directory -Force | Out-Null }

#===============================================================================
# Funktionen
#===============================================================================

Function Write-Log {
    param([string]$Message,[int]$Severity = 1)
    Write-ADTLogEntry -Message $Message -Source $Source -LogFileDirectory $LogFilePath `
        -LogFileName $LogFile -LogType CMTrace -Severity $Severity
}

Function Get-InstallLevel {
    # Aktuelle Stufe aus der Registry lesen (0 wenn nicht vorhanden)
    $lvl = Get-ADTRegistryKey -Key $StageKey -Name 'CurrentInstallLevel'
    if ($null -eq $lvl) { return 0 }
    return [int]$lvl
}

Function Set-InstallLevel {
    param([int]$Level)
    Set-ADTRegistryKey -Key $StageKey -Name 'CurrentInstallLevel' -Value $Level -Type DWord
    Write-Log "CurrentInstallLevel auf $Level gesetzt."
}

Function Copy-PackageToPersist {
    # Beim ersten Lauf (ccmcache) das Paket an einen neustart-sicheren Ort kopieren,
    # damit der Resume-Task nach dem Neustart die EXE noch findet.
    $pkgRoot = Split-Path $adtSession.DirFiles -Parent
    if ($pkgRoot -ne $PkgPersist) {
        Copy-ADTFile -Path "$pkgRoot\*" -Destination $PkgPersist -Recurse
        Write-Log "Paket nach '$PkgPersist' kopiert."
    }
}

Function Register-ResumeTask {
    # Startet das Paket nach dem Neustart automatisch erneut (SYSTEM, beim Systemstart)
    $exe       = Join-Path $PkgPersist 'Invoke-AppDeployToolkit.exe'
    $action    = New-ScheduledTaskAction -Execute $exe -Argument '-DeploymentType Install -DeployMode Silent'
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "PSADT-Resume-$AppName" -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log 'Resume-Task registriert.'
}

Function Remove-PersistFolder {
    # Selbstlöschung zeitverzögert, damit der laufende Prozess die EXE freigibt
    $cmd = "Start-Sleep -Seconds 15; Remove-Item -LiteralPath '$PkgPersist' -Recurse -Force; " +
           "Unregister-ScheduledTask -TaskName 'PSADT-Cleanup-$AppName' -Confirm:`$false"
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "PSADT-Cleanup-$AppName" -Action $action -Trigger $trigger `
        -Principal $principal -Force | Out-Null
    Write-Log 'Aufräum-Task für Persist-Ordner geplant.'
}

Function Complete-StagedInstall {
    # Aufräumen nach der letzten Stufe: Resume-Task und Stage-Schlüssel entfernen.
    # Die persistente Kopie ($PkgPersist) wird bewusst nicht gelöscht, da der Prozess
    # ggf. daraus läuft - bei Bedarf per separatem Aufräum-Schritt entfernen.
    if (Get-ScheduledTask -TaskName "PSADT-Resume-$AppName" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "PSADT-Resume-$AppName" -Confirm:$false
    }
    if (Test-Path $StageKey) { Remove-ADTRegistryKey -Key $StageKey -Recurse }
    Write-Log 'Staged-Installation abgeschlossen und aufgeräumt.'
}

Function Install_NotepadPP {
    $Setup = "$($adtSession.DirFiles)\npp.$AppVer.Installer.x64.exe"
    if (-not (Test-Path $Setup)) {
        Write-Log "Fehler: Setup nicht gefunden: $Setup" 3
        Show-ADTInstallationPrompt -Message "Setup nicht gefunden: $Setup" -ButtonRightText 'OK' -Severity Error
        Exit 55501
    }
    Write-Log "Starte Installation: $Setup /S"
    $Result = Start-ADTProcess -FilePath $Setup -ArgumentList '/S' -PassThru
    Write-Log "Installation beendet. ExitCode: $($Result.ExitCode)"
}

Function Uninstall_NotepadPP {
    $Uninst = "$env:ProgramFiles\Notepad++\uninstall.exe"
    if (Test-Path $Uninst) {
        Write-Log "Starte Deinstallation: $Uninst /S"
        $Result = Start-ADTProcess -FilePath $Uninst -ArgumentList '/S' -PassThru -IgnoreExitCodes '*'
        Write-Log "Deinstallation beendet. ExitCode: $($Result.ExitCode)"
    } else {
        Write-Log 'Notepad++ nicht installiert - nichts zu tun.' 2
    }
}

#===============================================================================
# Hauptablauf
#===============================================================================

switch ($adtSession.DeploymentType) {

    'Uninstall' {
        Show-ADTInstallationPrompt -Message 'Deinstallation Notepad++ - Start.' -ButtonRightText 'OK'
        Uninstall_NotepadPP
        Complete-StagedInstall     # offenes Stage-Tracking / Resume-Task entfernen
    }

    default {   # Install / Repair - stufenweise
        $current = Get-InstallLevel
        Write-Log "Setze Installation bei Stufe $current fort."

        $running = $true
        while ($running) {
            switch ($current) {

                0 {
                    Write-Log 'Stufe 0: Vorbereitung - Start.'
                    Show-ADTInstallationPrompt -Message 'Stufe 0: Vorbereitung - Start.' -ButtonRightText 'OK'
                    Copy-PackageToPersist
                    Set-InstallLevel 1
                    $current = 1
                }

                1 {
                    Write-Log 'Stufe 1: Deinstallation Altversion - Start.'
                    Show-ADTInstallationPrompt -Message 'Stufe 1: Deinstallation - Start.' -ButtonRightText 'OK'
                    Uninstall_NotepadPP
                    Set-InstallLevel 2
                    Register-ResumeTask
                    Write-Log 'Neustart erforderlich. Beende mit 3010.'
                    Close-ADTSession -ExitCode 3010
                    return
                }

                2 {
                    Write-Log 'Stufe 2: Installation - Start.'
                    Show-ADTInstallationPrompt -Message 'Stufe 2: Installation - Start.' -ButtonRightText 'OK'
                    Install_NotepadPP
                    Set-InstallLevel 3
                    Register-ResumeTask
                    Write-Log 'Neustart erforderlich. Beende mit 3010.'
                    Close-ADTSession -ExitCode 3010
                    return
                }

                3 {
                    Write-Log 'Stufe 3: Nachbereitung nach Neustart - Start.'
                    Show-ADTInstallationPrompt -Message 'Stufe 3: Nachbereitung - Start.' -ButtonRightText 'OK'
                    Set-InstallLevel 4
                    $current = 4
                }

                default {
                    Complete-StagedInstall
                    $running = $false
                }
            }
        }
    }
}
