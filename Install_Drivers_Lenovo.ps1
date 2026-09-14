<#
===============================================================================
 Lenovo Treiber-, BIOS- und Firmware-Installation via TVSU
 Deployment ueber PSAppDeployToolkit (PSADT) und Microsoft SCCM/MECM
-------------------------------------------------------------------------------
 WICHTIG - vor dem Produktiveinsatz auf ECHTER Hardware pruefen:
  1. Ob Win32_ComputerSystemProduct.Name die MTM fuer 20YR, 11T4, 11TB, 330B
     korrekt zurueckgibt.
  2. Ob nach dem Lauf die WMI-Klasse root\lenovo\Lenovo_Updates gefuellt ist
     (haengt am Parameter -exporttowmi).
  3. Den kompletten BitLocker->BIOS-Reboot-Zyklus auf je einem verschluesselten
     Geraet pro Modell.
 HINWEIS: tvsu.exe liefert KEINE offiziell dokumentierten Exit-Codes. Erfolg,
 Fehler und Reboot-Bedarf werden daher aus den WMI-Daten (Lenovo_Updates)
 abgeleitet - das ist zuverlaessiger als der Prozess-Exit-Code.
===============================================================================
#>

#===============================================================================
# FUNKTIONEN
#===============================================================================

#-------------------------------------------------------------------------------
# BitLocker voruebergehend aussetzen (fuer BIOS-/Firmware-Flash)
# Setzt Schutz fuer EINEN Neustart aus. Nach dem Reboot reaktiviert Windows
# den Schutz automatisch. Es wird BEWUSST nicht manuell fortgesetzt, damit
# ein BIOS-Flash beim naechsten Boot nicht in die Recovery laeuft.
#-------------------------------------------------------------------------------
Function Suspend_Bitlocker {
    try {
        $Volume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        if ($Volume.ProtectionStatus -eq "On") {
            Suspend-BitLocker -MountPoint "C:" -RebootCount 1 -ErrorAction Stop
            $Global:BitLockerWasSuspended = $true
            $Message = "BitLocker wurde fuer einen Neustart ausgesetzt (anstehender BIOS-/Firmware-Flash)."
            Write-ADTLogEntry -Message $Message -Source "Suspend_Bitlocker" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
        else {
            # Kein aktiver Schutz -> nichts auszusetzen (Status Off oder bereits suspended)
            $Global:BitLockerWasSuspended = $false
            $Message = "BitLocker ist nicht aktiv (Status: $($Volume.ProtectionStatus)). Kein Aussetzen noetig."
            Write-ADTLogEntry -Message $Message -Source "Suspend_Bitlocker" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
    }
    catch {
        # BitLocker nicht vorhanden / Volume nicht verschluesselt -> als "nicht ausgesetzt" behandeln
        $Global:BitLockerWasSuspended = $false
        $Message = "BitLocker-Status konnte nicht ermittelt werden (evtl. nicht verschluesselt): $($_.Exception.Message)"
        Write-ADTLogEntry -Message $Message -Source "Suspend_Bitlocker" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Warning
    }
}

#-------------------------------------------------------------------------------
# NVIDIA Control Panel installieren
# Wird bei uns nicht automatisch ueber den Store nachgezogen, daher manuell.
# Zusaetzliche Absicherung: nur installieren, wenn auch NVIDIA-Hardware da ist.
#-------------------------------------------------------------------------------
Function Install_Nvidia_Control_Panel {

    # Pruefen, ob ueberhaupt eine NVIDIA-GPU verbaut ist
    $NvidiaGpu = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*NVIDIA*" }
    if (-not $NvidiaGpu) {
        $Message = "Keine NVIDIA-GPU erkannt. NVIDIA Control Panel wird nicht installiert."
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        return
    }

    # Pruefen, ob die NVIDIA Control Panel App im Repository vorhanden ist
    if (!(Test-Path "$DriverRepository\Nvidia Treiber")) {
        $Message = "Die NVIDIA Control Panel App ist nicht vorhanden, sie wird nicht installiert."
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        return
    }

    # Variablen: Appx-Paket und Lizenzdatei suchen
    $Nvidia_AppxPackage_File = Get-ChildItem -Path "$DriverRepository\Nvidia Treiber\Display.Driver\NVCPL\*.appx" | Select-Object -First 1
    $Nvidia_AppxLicense_File = Get-ChildItem -Path "$DriverRepository\Nvidia Treiber\Display.Driver\NVCPL\*_License1.xml" | Select-Object -First 1

    if (-not $Nvidia_AppxPackage_File) {
        $Message = "Kein NVIDIA Appx-Paket im Repository gefunden. Installation wird uebersprungen."
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Warning
        return
    }

    $Message = "Pfad der NVIDIA Control Panel Appx-Datei: $Nvidia_AppxPackage_File"
    Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

    # Installierte Versionsnummer ermitteln
    try {
        $InstalledVersion = (Get-AppxProvisionedPackage -Online | Where-Object PackageName -like "NVIDIACorp.NVIDIAControlPanel*").Version
        $Message = "Installierte NVIDIA Control Panel Version: $InstalledVersion"
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    }
    catch {
        Write-ADTLogEntry -Message "Fehler bei Versionsermittlung: $($_.Exception.Message)" -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    }

    # Versionsnummer der Appx-Datei aus dem AppxManifest.xml ermitteln
    try {
        # Appx-Datei nach C:\Temp\AppxPackage entpacken (vorher aufraeumen)
        if (Test-Path "C:\Temp\AppxPackage") { Remove-Item -Recurse -Force "C:\Temp\AppxPackage" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$Nvidia_AppxPackage_File", "C:\Temp\AppxPackage")

        # Zeile mit "Identity Name=" suchen und Version per Regex ableiten
        $VersionNumberLine = (Select-String -Path "C:\Temp\AppxPackage\AppxManifest.xml" -Pattern "Identity Name=").Line
        $VersionOfAppxFile = [regex]::Match($VersionNumberLine, 'Version\s*=\s*"([\d\.]+)"').Groups[1].Value

        $Message = "NVIDIA Control Panel Version der Appx-Datei im Repository: $VersionOfAppxFile"
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

        # Entpackten Ordner wieder loeschen
        Remove-Item -Recurse -Force "C:\Temp\AppxPackage"
    }
    catch {
        Write-ADTLogEntry -Message "Fehler bei Versionsermittlung der Appx-Datei: $($_.Exception.Message)" -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
        return
    }

    # Nur installieren, wenn Repository-Version von installierter Version abweicht
    if ($InstalledVersion -ne $VersionOfAppxFile) {
        $Message = "Installiere das NVIDIA Control Panel....."
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

        Add-AppxProvisionedPackage -Online -PackagePath "$Nvidia_AppxPackage_File" -LicensePath $Nvidia_AppxLicense_File -LogPath "C:\Logs\Nvidia Control Panel.log"

        # Erneut pruefen, ob die Installation erfolgreich war
        try {
            $InstalledVersion = (Get-AppxProvisionedPackage -Online | Where-Object PackageName -like "NVIDIACorp.NVIDIAControlPanel*").Version
        }
        catch { }

        if ($InstalledVersion -eq $VersionOfAppxFile) {
            $Message = "Das NVIDIA Control Panel wurde erfolgreich installiert."
            Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
        else {
            $Message = "Fehler: Das NVIDIA Control Panel konnte nicht installiert werden."
            Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
        }
    }
    else {
        $Message = "Die Version im Repository ist nicht neuer als die installierte Version. Keine Aktualisierung noetig."
        Write-ADTLogEntry -Message $Message -Source "Install_Nvidia_Control_Panel" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    }
}

#-------------------------------------------------------------------------------
# Registry-Werte SICHERN, bevor sie geaendert werden
# Der komplette Teilbaum Policies\Lenovo wird exportiert, damit ein evtl.
# vorhandener (z. B. per GPO gesetzter) Zustand wiederhergestellt werden kann.
#-------------------------------------------------------------------------------
Function Backup_Registry_Keys {
    $Global:RegBackupFile = "$LogFilePath\Lenovo_Policies_Backup_$($env:COMPUTERNAME).reg"
    try {
        if (Test-Path "HKLM:\Software\Policies\Lenovo") {
            # reg.exe export sichert Schluessel inkl. Werttypen originalgetreu
            & reg.exe export "HKLM\Software\Policies\Lenovo" "$RegBackupFile" /y | Out-Null
            $Message = "Registry-Sicherung erstellt: $RegBackupFile"
            Write-ADTLogEntry -Message $Message -Source "Backup_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
        else {
            $Global:RegBackupFile = $null
            $Message = "Kein bestehender Policies\Lenovo-Schluessel vorhanden. Keine Sicherung noetig."
            Write-ADTLogEntry -Message $Message -Source "Backup_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
    }
    catch {
        $Global:RegBackupFile = $null
        Write-ADTLogEntry -Message "Fehler bei Registry-Sicherung: $($_.Exception.Message)" -Source "Backup_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Warning
    }
}

#-------------------------------------------------------------------------------
# Temporaere Registry-Werte ENTFERNEN (Ausgangszustand herstellen)
#-------------------------------------------------------------------------------
Function Reset_Registry_Keys {
    # Von uns gesetzten Policy-Zweig entfernen
    Remove-Item -Path "HKLM:\Software\Policies\Lenovo" -Force -Recurse -ErrorAction SilentlyContinue

    # Nachfolgende Einzelwerte entfernen
    $Base = "HKLM:\SOFTWARE\Wow6432Node\Lenovo\System Update\Preferences\UserSettings"
    Remove-ItemProperty -Path "$Base\Scheduler" -Name "SchedulerAbility"        -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "DebugEnable"             -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "DisplayInformationScreen" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "DisplayLicenseNotice"    -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "DisplayLicenseNoticeSU"  -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "IgnoreLocalLicense"      -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "AskBeforeClosing"        -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$Base\General"   -Name "EULAAccepted"            -ErrorAction SilentlyContinue
}

#-------------------------------------------------------------------------------
# Gesicherten Registry-Zustand WIEDERHERSTELLEN (im finally-Block genutzt)
#-------------------------------------------------------------------------------
Function Restore_Registry_Keys {
    # Erst unsere temporaeren Werte entfernen
    Reset_Registry_Keys

    # Dann - falls vorhanden - den Originalzustand zurueckspielen
    if ($Global:RegBackupFile -and (Test-Path $Global:RegBackupFile)) {
        try {
            & reg.exe import "$RegBackupFile" | Out-Null
            $Message = "Original-Registry aus Sicherung wiederhergestellt: $RegBackupFile"
            Write-ADTLogEntry -Message $Message -Source "Restore_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
        catch {
            Write-ADTLogEntry -Message "Fehler beim Wiederherstellen der Registry: $($_.Exception.Message)" -Source "Restore_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Warning
        }
    }
}

#-------------------------------------------------------------------------------
# Temporaere Registry-Werte SETZEN (AdminCommandLine fuer TVSU)
#-------------------------------------------------------------------------------
Function Set_Registry_Keys {
    # Policy-Schluessel anlegen
    New-Item "HKLM:\Software\Policies\Lenovo" -Force | Out-Null
    New-Item "HKLM:\Software\Policies\Lenovo\System Update" -Force | Out-Null
    New-Item "HKLM:\Software\Policies\Lenovo\System Update\UserSettings" -Force | Out-Null
    New-Item "HKLM:\Software\Policies\Lenovo\System Update\UserSettings\General" -Force | Out-Null

    # AdminCommandLine: TVSU scannt das LOKALE Repository und installiert nur
    # anwendbare Pakete. -noreboot verhindert selbstaendige Reboots durch TVSU,
    # soweit moeglich (Typ 1/4/5 koennen dennoch neu starten). -exporttowmi
    # schreibt das Ergebnis nach root\lenovo -> Basis unserer Erfolgsauswertung.
    $Value = "/CM -search A -action INSTALL -includerebootpackages 1,3,4,5 -noreboot -noicon -repository `"$DriverRepository`" -nolicense -exporttowmi"
    $Message = "Parameter fuer den Aufruf des Lenovo System Updater (TVSU.exe): $Value"
    Write-ADTLogEntry -Message $Message -Source "Set_Registry_Keys" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

    New-ItemProperty -Type String -Path "HKLM:\Software\Policies\Lenovo\System Update\UserSettings\General" -Name "AdminCommandLine" -Value $Value | Out-Null

    # Weitere Schluessel: automatische Updates, Message-Boxen etc. deaktivieren
    $Sched = "HKLM:\SOFTWARE\Wow6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler"
    $Gen   = "HKLM:\SOFTWARE\Wow6432Node\Lenovo\System Update\Preferences\UserSettings\General"
    Set-ItemProperty -Path $Sched -Name "SchedulerAbility"        -Value "NO"  -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "DebugEnable"             -Value "YES" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "DisplayInformationScreen" -Value "YES" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "DisplayLicenseNotice"    -Value "NO"  -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "DisplayLicenseNoticeSU"  -Value "NO"  -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "IgnoreLocalLicense"      -Value "YES" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "AskBeforeClosing"        -Value "NO"  -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $Gen   -Name "EULAAccepted"            -Value "YES" -ErrorAction SilentlyContinue

    # Standard-Scheduler-Task deaktivieren
    Disable-ScheduledTask -TaskName "TVT\TVSUUpdateTask_UserLogOn" -ErrorAction SilentlyContinue | Out-Null
}

#-------------------------------------------------------------------------------
# Lenovo Treiber / BIOS / Firmware ueber TVSU installieren
# Gibt den Prozess-Exit-Code zurueck (wird zusaetzlich zur WMI-Auswertung
# protokolliert). Der Aufrufer wertet primaer die WMI-Daten aus.
#-------------------------------------------------------------------------------
Function Install_Lenovo_Drivers {
    # Argumente fuer den Lenovo System Updater
    $ProgramFile_tvsu = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"
    $Arguments_tvsu   = "/CM"
    $Message = "Aufruf des Lenovo System Updater: $ProgramFile_tvsu $Arguments_tvsu"
    Write-ADTLogEntry -Message $Message -Source "Install_Lenovo_Drivers" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

    # Pruefen, ob der Lenovo System Updater installiert ist
    if (!(Test-Path $ProgramFile_tvsu)) {
        $Message = "Fehler: Der Lenovo System Updater wurde nicht gefunden ($ProgramFile_tvsu)."
        Write-ADTLogEntry -Message $Message -Source "Install_Lenovo_Drivers" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
        # KEIN hartes Exit hier: sauberer Rueckgabewert, damit das finally im
        # Hauptprogramm (BitLocker/Registry-Restore) trotzdem laeuft.
        $Global:TVSU_ExitCode = 55555
        return 55555
    }

    # TVSU starten und Exit-Code ERFASSEN (-PassThru).
    $tvsuResult = Start-ADTProcess -FilePath $ProgramFile_tvsu -ArgumentList $Arguments_tvsu `
        -WaitForChildProcesses -Timeout 03:30:00 -WaitForMsiExec -PassThru -IgnoreExitCodes '*'

    $Global:TVSU_ExitCode = $tvsuResult.ExitCode
    $Message = "TVSU beendet. Prozess-Exit-Code: $($Global:TVSU_ExitCode)"
    Write-ADTLogEntry -Message $Message -Source "Install_Lenovo_Drivers" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

    return $Global:TVSU_ExitCode
}

#-------------------------------------------------------------------------------
# Ergebnis aus den WMI-Daten (root\lenovo\Lenovo_Updates) auswerten
# Da tvsu.exe keine dokumentierten Exit-Codes hat, ist die WMI-Historie die
# verlaessliche Quelle. Rueckgabe: Hashtable mit Erfolg/Fehler/Reboot/Details.
#-------------------------------------------------------------------------------
Function Get_Installation_Result {
    $Result = @{
        HasFailures   = $false
        RebootNeeded  = $false
        Installed     = @()
        Failed        = @()
        Summary       = ""
    }

    try {
        $Updates = Get-CimInstance -Namespace "root\lenovo" -ClassName "Lenovo_Updates" -ErrorAction Stop
    }
    catch {
        # WMI nicht gefuellt -> als Fehler behandeln (kein blindes "Erfolg")
        $Result.HasFailures = $true
        $Result.Summary = "WMI-Klasse Lenovo_Updates nicht lesbar: $($_.Exception.Message)"
        Write-ADTLogEntry -Message $Result.Summary -Source "Get_Installation_Result" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
        return $Result
    }

    # Erfolgreich installierte Pakete
    $Success = $Updates | Where-Object { $_.Status -eq "InstallSuccess" }
    $Result.Installed = @($Success | ForEach-Object { $_.Title })

    # Abgebrochene / uebersprungene Pakete, die im Repository lagen (also anwendbar waren)
    $Canceled = $Updates | Where-Object { $_.Status -eq "Canceled" }
    foreach ($c in $Canceled) {
        if (Test-Path "$DriverRepository\$($c.PackageID)") {
            $Result.Failed += $c.Title
        }
    }

    # Reboot-Bedarf: erfolgreiche Pakete mit Reboot-Typ 1,3,4,5
    # (1=Reboot erzwungen, 3=Reboot erforderlich, 4=Shutdown, 5=Reboot in 5 Min)
    $RebootPackages = $Success | Where-Object {
        $_.RebootType -in 1,3,4,5 -or $_.Reboot -in 1,3,4,5
    }
    if ($RebootPackages) { $Result.RebootNeeded = $true }

    if ($Result.Failed.Count -gt 0) { $Result.HasFailures = $true }

    $Result.Summary = "Installiert: $($Result.Installed.Count), Fehlgeschlagen: $($Result.Failed.Count), Reboot noetig: $($Result.RebootNeeded)"
    Write-ADTLogEntry -Message $Result.Summary -Source "Get_Installation_Result" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

    return $Result
}

#-------------------------------------------------------------------------------
# Ergebnismeldung anzeigen und protokollieren
#-------------------------------------------------------------------------------
Function Show_Installation_Message {
    param($InstallResult)

    if ($InstallResult.Failed.Count -gt 0) {
        $Canceled_Installs = ($InstallResult.Failed -join "; ")
        $Message = "Fehler: Folgende Updates wurden uebersprungen und nicht installiert: $Canceled_Installs"
        Show-ADTInstallationPrompt -Message $Message -ButtonRightText "OK"
        Write-ADTLogEntry -Message $Message -Source "Show_Installation_Message" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    }

    if ($InstallResult.Installed.Count -eq 0) {
        $Message = "Information: Es wurden keine weiteren Updates installiert."
        Write-ADTLogEntry -Message $Message -Source "Show_Installation_Message" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    }
    else {
        $Message = "Information: Es wurden Updates installiert. Siehe ggf. Log-Datei -> C:\Logs\Lenovo_Install_Drivers."
        Write-ADTLogEntry -Message $Message -Source "Show_Installation_Message" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    }
}

#===============================================================================
# HAUPTPROGRAMM
#===============================================================================

#--- Grundeinstellungen -------------------------------------------------------
$LogFilePath = "C:\Logs"
$LogFile     = "Lenovo_Install_Drivers.log"
$Version     = "14-09-2026"

# Zuverlaessiger Skript-Pfad (NICHT $pwd - unter SCCM/SYSTEM zeigt das oft auf
# System32). $adtSession.DirFiles bevorzugt, sonst $PSScriptRoot als Fallback.
if ($adtSession -and $adtSession.DirFiles) {
    $Current_Path = $adtSession.DirFiles
}
else {
    $Current_Path = $PSScriptRoot
}

# Globale Zustands-Variablen (fuer finally-Cleanup)
$Global:BitLockerWasSuspended = $false
$Global:TVSU_ExitCode         = $null
$Global:RegBackupFile         = $null

# Detection-/Compliance-Schluessel fuer SCCM (NICHT nur Log-Datei als Nachweis!)
$RegPath = "HKLM:\SOFTWARE\Lenovo_Deployment"

$Message = "Der Lenovo System Updater wird gestartet.... (Skript-Version: $Version)"
Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

#--- Angemeldeten Benutzer ermitteln (nur fuer Protokoll) ---------------------
$LoggedOnUser_FQDN = (Get-Process -IncludeUserName -Name explorer -ErrorAction SilentlyContinue | Select-Object UserName -Unique).UserName
if ($LoggedOnUser_FQDN) {
    $LoggedOnUser = $LoggedOnUser_FQDN.Split("\")[-1]
}
else {
    $LoggedOnUser = "SYSTEM"
}
$Message = "Der Name des angemeldeten Benutzers lautet: $LoggedOnUser"
Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

#--- Hersteller pruefen (nur Lenovo) ------------------------------------------
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
if ($Manufacturer -notlike "*LENOVO*") {
    $Message = "Fehler: Kein Lenovo-Geraet erkannt (Hersteller: $Manufacturer). Skript wird beendet."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    Close-ADTSession -ExitCode 55510
    return
}

#--- Maschinentyp / Modell zuverlaessig ermitteln -----------------------------
# Bei Lenovo enthaelt Win32_ComputerSystemProduct.Name die vollstaendige MTM
# (z. B. 20YRS7PD00). Win32_ComputerSystem.Model ist NICHT zuverlaessig.
$MTM         = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).Name
$SystemModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$Message = "Erkannte MTM: $MTM | Model: $SystemModel"
Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace

# Maschinentyp = erste 4 Zeichen der MTM (z. B. 20YR, 11T4, 11TB, 330B)
if ($MTM.Length -ge 4) {
    $MachineType = $MTM.Substring(0,4)
}
else {
    $MachineType = $MTM
}

#--- Passendes lokales Repository automatisch finden ---------------------------
$RepoRoot = Join-Path $Current_Path "Lenovo_Repository"

# Zuerst exakte MTM-Uebereinstimmung, dann 4-Zeichen-Maschinentyp als Fallback
$Matches = @(Get-ChildItem -Path $RepoRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$MTM*_W11" })
if ($Matches.Count -eq 0) {
    $Matches = @(Get-ChildItem -Path $RepoRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$MachineType*_W11" })
}

# Mehrdeutigkeit vermeiden: bei mehreren Treffern NICHT raten -> abbrechen
if ($Matches.Count -gt 1) {
    $Message = "Fehler: Mehrere passende Repositories gefunden ($($Matches.Name -join ', ')). Abbruch zur Sicherheit."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    Close-ADTSession -ExitCode 55512
    return
}

$DriverRepository = ($Matches | Select-Object -First 1).FullName

if ($DriverRepository -and (Test-Path -Path $DriverRepository)) {
    $Message = "Das Lenovo Treiber Repository liegt unter: $DriverRepository"
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
}
else {
    $Message = "Fehler: Kein Repository fuer MTM '$MTM' / Typ '$MachineType' gefunden. TVSU wird nicht gestartet."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    Close-ADTSession -ExitCode 55511
    return
}

#--- Netzteil pruefen (Pflicht fuer BIOS-/Firmware-Flash) ---------------------
# Kein Akku (Desktop/VM) -> automatisch bestanden. Laptop im Akkubetrieb -> Abbruch.
$Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
if ($Battery) {
    Add-Type -AssemblyName System.Windows.Forms
    $PowerLine = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
    if ($PowerLine -eq 'Offline') {
        $Message = "Fehler: BIOS-/Firmware-Update abgebrochen. Geraet laeuft im Akkubetrieb. Bitte Netzteil anschliessen und erneut ausfuehren."
        Show-ADTInstallationPrompt -Message $Message -ButtonRightText 'OK'
        Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
        Close-ADTSession -ExitCode 55556
        return
    }
    # Hinweis: PowerLineStatus 'Unknown' wird toleriert (manche Geraete melden das
    # trotz angeschlossenem Netzteil). TVSU fuehrt zusaetzlich eigene AC-Pruefung durch.
}

#--- Pending-Reboot pruefen (vor BIOS-Flash kein anstehender Reboot) -----------
$PendingReboot = $false
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $PendingReboot = $true }
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $PendingReboot = $true }
if ($PendingReboot) {
    $Message = "Ein Windows-Neustart steht noch aus. BIOS-/Firmware-Flash wird verschoben. Exit 3010 an SCCM."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Warning
    Close-ADTSession -ExitCode 3010
    return
}

#===============================================================================
# INSTALLATION mit garantiertem Cleanup (try/finally)
#===============================================================================
Show-ADTInstallationProgress

try {
    #--- 1. Registry sichern, dann BitLocker aussetzen ------------------------
    Backup_Registry_Keys
    Suspend_Bitlocker

    #--- 2. Temporaere Registry-Werte setzen (AdminCommandLine) ---------------
    Set_Registry_Keys

    #--- 3. NVIDIA Control Panel (nur wenn NVIDIA-Hardware vorhanden) ----------
    Install_Nvidia_Control_Panel

    #--- 4. TVSU ausfuehren ---------------------------------------------------
    Install_Lenovo_Drivers | Out-Null

    #--- 5. Ergebnis aus WMI auswerten (nicht aus dem Exit-Code!) -------------
    $InstallResult = Get_Installation_Result
    Show_Installation_Message -InstallResult $InstallResult
}
finally {
    #--- CLEANUP - laeuft IMMER, auch bei Fehler ------------------------------
    # Registry-Originalzustand wiederherstellen
    Restore_Registry_Keys

    # BitLocker-Behandlung:
    # Wenn ein Reboot ansteht (BIOS/Firmware), BitLocker NICHT jetzt fortsetzen -
    # der Schutz wird durch -RebootCount 1 nach dem naechsten Neustart automatisch
    # reaktiviert. Nur wenn KEIN Reboot ansteht, jetzt sauber fortsetzen.
    if ($Global:BitLockerWasSuspended) {
        if ($InstallResult -and $InstallResult.RebootNeeded) {
            $Message = "Reboot steht an - BitLocker bleibt bis zum Neustart ausgesetzt (automatische Reaktivierung nach Boot)."
            Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
        else {
            Resume-BitLocker -MountPoint "C:" -ErrorAction SilentlyContinue
            $Message = "Kein Reboot noetig - BitLocker-Schutz wurde wieder aktiviert."
            Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
        }
    }
}

#===============================================================================
# AUSWERTUNG & FINALE SCCM-RUECKGABE (mit Detection-Writeback)
#===============================================================================

# Detection-Schluessel anlegen, falls nicht vorhanden
if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }

if ($InstallResult.HasFailures) {
    #--- Fehler: Compliance = Failed, Fehler-Exit an SCCM ---------------------
    New-ItemProperty -Path $RegPath -Name "ComplianceState" -Value "Failed" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "Model"           -Value $MTM     -PropertyType String -Force | Out-Null
    Set-ItemProperty -Path $RegPath -Name "LastRun"         -Value (Get-Date -Format "yyyy-MM-dd HH:mm")

    $Message = "Installation mit Fehlern beendet (Exit-Code TVSU: $($Global:TVSU_ExitCode)). Siehe Log. Exit 1 an SCCM."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace -Severity Error
    Close-ADTSession -ExitCode 1
}
elseif ($InstallResult.RebootNeeded) {
    #--- Erfolg, aber Reboot noetig (BIOS/Firmware wird beim Boot geflasht) ----
    # WICHTIG: BIOS ist hier "staged/pending reboot", NICHT verifiziert geflasht.
    New-ItemProperty -Path $RegPath -Name "ComplianceState" -Value "Installed" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "Model"           -Value $MTM        -PropertyType String -Force | Out-Null
    Set-ItemProperty -Path $RegPath -Name "LastRun"         -Value (Get-Date -Format "yyyy-MM-dd HH:mm")

    $Message = "Updates installiert. Neustart erforderlich (BIOS/Firmware wird beim Boot angewendet). Exit 3010 an SCCM."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    Close-ADTSession -ExitCode 3010
}
else {
    #--- Erfolg, kein Reboot --------------------------------------------------
    New-ItemProperty -Path $RegPath -Name "ComplianceState" -Value "Installed" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "Model"           -Value $MTM        -PropertyType String -Force | Out-Null
    Set-ItemProperty -Path $RegPath -Name "LastRun"         -Value (Get-Date -Format "yyyy-MM-dd HH:mm")

    $Message = "Installation erfolgreich abgeschlossen, kein Reboot noetig. Exit 0 an SCCM."
    Write-ADTLogEntry -Message $Message -Source "Hauptprogramm" -LogFileDirectory $LogFilePath -LogFileName $LogFile -LogType CMTrace
    Close-ADTSession -ExitCode 0
}
