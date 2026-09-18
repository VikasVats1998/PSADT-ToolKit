#===============================================================================
# Funktionen
#===============================================================================

$AppName  = 'Notepad++'
$StageKey = "HKLM:\SOFTWARE\PSADT\Stages\$AppName"
$Source   = 'Install-Staged'

Function Get-InstallLevel {
    # Liest die aktuelle Stufe aus der Registry (0 wenn nicht vorhanden)
    $lvl = Get-ADTRegistryKey -Key $StageKey -Name 'CurrentInstallLevel'
    if ($null -eq $lvl) { return 0 }
    return [int]$lvl
}

Function Set-InstallLevel {
    param([int]$Level)
    # Schreibt die nächste Stufe in die Registry
    Set-ADTRegistryKey -Key $StageKey -Name 'CurrentInstallLevel' -Value $Level -Type DWord
    Write-ADTLogEntry -Message "CurrentInstallLevel auf $Level gesetzt." -Source $Source -Severity 1
}

Function Register-ResumeTask {
    # Startet das Paket nach dem Neustart erneut (SYSTEM, beim Systemstart)
    # Hinweis: Pfad muss den Neustart überleben (persistente Kopie / Repo), nicht ccmcache
    $exe       = Join-Path $adtSession.DirFiles '..\Invoke-AppDeployToolkit.exe'
    $action    = New-ScheduledTaskAction -Execute $exe -Argument '-DeploymentType Install -DeployMode Silent'
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "PSADT-Resume-$AppName" -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-ADTLogEntry -Message 'Resume-Task registriert.' -Source $Source -Severity 1
}

Function Complete-StagedInstall {
    # Aufräumen nach der letzten Stufe: Task und Registry-Schlüssel entfernen
    if (Get-ScheduledTask -TaskName "PSADT-Resume-$AppName" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "PSADT-Resume-$AppName" -Confirm:$false
    }
    Remove-ADTRegistryKey -Key $StageKey -Recurse
    Write-ADTLogEntry -Message 'Staged-Installation abgeschlossen und aufgeräumt.' -Source $Source -Severity 1
}


#===============================================================================
# Hauptablauf - stufenweise, neustart-resistente Installation
#===============================================================================

$current = Get-InstallLevel
Write-ADTLogEntry -Message "Setze Installation bei Stufe $current fort." -Source $Source -Severity 1

$running = $true
while ($running) {
    switch ($current) {

        0 {
            Write-ADTLogEntry -Message 'Stufe 0: Vorbereitung - Start.' -Source $Source -Severity 1
            # <-- deine Vorbereitungs-Funktion, z.B.:  Suspend_Bitlocker
            Set-InstallLevel 1
            $current = 1          # kein Neustart -> direkt zur nächsten Stufe
        }

        1 {
            Write-ADTLogEntry -Message 'Stufe 1: Installation - Start.' -Source $Source -Severity 1
            # <-- deine Installations-Funktion, z.B.:  Install_HP_Drivers
            Set-InstallLevel 2

            # Neustart-Stufe: Resume-Task setzen, dann mit 3010 beenden
            Register-ResumeTask
            Write-ADTLogEntry -Message 'Neustart erforderlich. Beende mit 3010.' -Source $Source -Severity 1
            Close-ADTSession -ExitCode 3010
            return
        }

        2 {
            Write-ADTLogEntry -Message 'Stufe 2: Nachbereitung nach Neustart - Start.' -Source $Source -Severity 1
            # <-- deine Nachbereitungs-Funktion
            Set-InstallLevel 3
            $current = 3
        }

        default {
            Complete-StagedInstall
            $running = $false
        }
    }
}
