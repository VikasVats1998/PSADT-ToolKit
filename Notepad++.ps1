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
        Uninstall_NotepadPP
        Complete-StagedInstall   # evtl. offenes Stage-Tracking / Resume-Task entfernen
    }

    default {   # Install / Repair
        $current = Get-InstallLevel
        Write-Log "Setze Installation bei Stufe $current fort."

        $running = $true
        while ($running) {
            switch ($current) {

                0 {
                    Write-Log 'Stufe 0: Vorbereitung - Start.'
                    Copy-PackageToPersist
                    # <-- weitere Vorbereitungsschritte hier
                    Set-InstallLevel 1
                    $current = 1          # kein Neustart -> direkt weiter
                }

                1 {
                    Write-Log 'Stufe 1: Installation - Start.'
                    Install_NotepadPP
                    Set-InstallLevel 2

                    # Neustart-Stufe: Resume-Task setzen, dann mit 3010 beenden
                    Register-ResumeTask
                    Write-Log 'Neustart erforderlich. Beende mit 3010.'
                    Close-ADTSession -ExitCode 3010
                    return
                }

                2 {
                    Write-Log 'Stufe 2: Nachbereitung nach Neustart - Start.'
                    # <-- Konfiguration nach dem Neustart hier
                    Set-InstallLevel 3
                    $current = 3
                }

                default {
                    Complete-StagedInstall
                    $running = $false
                }
            }
        }
    }
}
