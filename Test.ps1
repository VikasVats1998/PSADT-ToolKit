#==============================================
# MARK: UCM Maintenance Wizard - Getaktete Verbindung (Ethernet) Fix
#==============================================

Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# ---- Konfiguration: HIER ANPASSEN ----
$UCMTitle              = 'IT Help Desk - Maintenance'

# Standardpfad zur CSV-Datei (kann im Assistenten geändert werden)
# Läuft das Skript über PSADT, wird der SupportFiles-Ordner des Pakets genutzt
$UCMCsvPath = if ($adtSession -and $adtSession.DirSupportFiles) {
    Join-Path $adtSession.DirSupportFiles 'Getaktet_Status.csv'
} else {
    'C:\PSADT-Stuff\Getaktete-Verbindung-Maintainence-App\SupportFiles\Getaktet_Status.csv'
}

$UCMCsvDelimiter       = ';'          # Trennzeichen der CSV-Datei
$UCMReportFolder       = 'C:\Temp'    # Ordner für Bericht und Wiederholungsliste
$UCMRebootDelaySeconds = 300          # Vorwarnzeit für den Benutzer vor dem Neustart (300 = 5 Min.)
$UCMRebootPauseSeconds = 10           # Pause zwischen zwei Neustart-Befehlen

# WinRM-Timeouts: 15 Sek. für den Verbindungsaufbau, 2 Min. für die Ausführung
$script:UCMSessionOption = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000


#==============================================
# Hilfsfunktionen
#==============================================

# Domänennummer in Domänennamen umwandeln
function Resolve-UCMDomain {
    param([string]$Number)
    switch ($Number) {
        '1'     { 'ezifa' }
        '2'     { 'domain2' }
        '3'     { 'domain3' }
        '4'     { 'domain4' }
        default { $null }
    }
}

# Eingegebenen Text aus einem Eingabedialog lesen (funktioniert mit verschiedenen PSADT-Versionen)
function Get-UCMInputText {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    foreach ($p in 'Text','Input','InputText','Value','Response','SelectedItem') {
        $prop = $Result.PSObject.Properties[$p]
        if ($prop -and $null -ne $prop.Value) {
            # Kennwortfeld (SecureString) in Klartext umwandeln
            if ($prop.Value -is [securestring]) {
                return (New-Object System.Management.Automation.PSCredential 'x', $prop.Value).GetNetworkCredential().Password
            }
            return [string]$prop.Value
        }
    }
    # Kein Text gefunden -> leer zurückgeben (nicht das ganze Objekt)
    return $null
}

# Ermitteln, welche Schaltfläche im Eingabedialog geklickt wurde
function Get-UCMButton {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    foreach ($p in 'Result','Button','ButtonText') {
        $prop = $Result.PSObject.Properties[$p]
        if ($prop -and $prop.Value) { return [string]$prop.Value }
    }
    return $null
}


#==============================================
# Backend-Funktionen
#==============================================

# Benutzername und Kennwort gegen die Domäne prüfen
function Test-UCMCredential {
    param([string]$DomainFqdn,[string]$User,[string]$PlainPw)
    try {
        # Nur den Benutzernamen herausziehen: DOMAIN\user -> user, user@domain -> user
        $sam = if ($User -match '\\') { ($User -split '\\')[-1] }
               elseif ($User -match '@') { ($User -split '@')[0] }
               else { $User }

        $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                   [System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainFqdn)
        $ok = $ctx.ValidateCredentials($sam, $PlainPw)

        if ($ok) { [pscustomobject]@{ Success=$true;  Message="Authenticated against $DomainFqdn" } }
        else     { [pscustomobject]@{ Success=$false; Message='Invalid username or password.' } }
    } catch {
        [pscustomobject]@{ Success=$false; Message="Domain not reachable: $($_.Exception.Message)" }
    }
}

# Geräteliste aus der CSV-Datei lesen
function Import-UCMDeviceList {
    param([string]$Path)

    # Gibt es die Datei?
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Success=$false; Message="CSV file not found: $Path"; Devices=@() }
    }

    try {
        # ReadAllText entfernt das unsichtbare BOM-Zeichen am Dateianfang,
        # der Split funktioniert mit Windows-, Mac- und Linux-Zeilenenden
        $text  = [System.IO.File]::ReadAllText($Path)
        $lines = @($text -split "`r`n|`r|`n" | Where-Object { $_.Trim() -ne '' })
        $rows  = @($lines | ConvertFrom-Csv -Delimiter $UCMCsvDelimiter)

        if ($rows.Count -eq 0) {
            return [pscustomobject]@{ Success=$false; Message='CSV file is empty.'; Devices=@() }
        }

        # Spalten suchen (ignoriert BOM, Anführungszeichen, Leerzeichen und Groß-/Kleinschreibung)
        $col = $null; $statusCol = $null
        foreach ($c in $rows[0].PSObject.Properties.Name) {
            $clean = ($c -replace '[\uFEFF"]','').Trim()
            if (-not $col -and $clean -in 'Name','Geraetename','Device') { $col = $c }
            if ($clean -eq 'Status') { $statusCol = $c }
        }
        if (-not $col) {
            return [pscustomobject]@{ Success=$false; Message="No device column found. Columns: $($rows[0].PSObject.Properties.Name -join ', ')"; Devices=@() }
        }

        # CSV aus dem Scan-Skript: nur Geräte mit Status "Betroffen" übernehmen
        if ($statusCol) {
            $rows = @($rows | Where-Object { "$($_.$statusCol)".Trim() -eq 'Betroffen' })
        }

        # Gerätenamen säubern, leere Zeilen und Doppelte entfernen
        $devices = @($rows | ForEach-Object { "$($_.$col)".Trim() } | Where-Object { $_ } | Sort-Object -Unique)

        if ($devices.Count -eq 0) {
            return [pscustomobject]@{ Success=$false; Message='No affected devices found in the CSV file.'; Devices=@() }
        }
        [pscustomobject]@{ Success=$true; Message="$($devices.Count) devices imported."; Devices=$devices }
    } catch {
        [pscustomobject]@{ Success=$false; Message="CSV import failed: $($_.Exception.Message)"; Devices=@() }
    }
}

# ---- Dieser Block läuft AUF dem Zielgerät ----
# Liest UserCost aller Ethernet-Adapter, setzt Werte ungleich 0 auf 0 und prüft danach nochmal
$script:UCMFixBlock = {
    $pc       = Get-CimInstance Win32_ComputerSystem
    $adapter  = @(Get-NetAdapter -Physical | Where-Object PhysicalMediaType -eq '802.3')   # 802.3 = Ethernet
    $before   = @()
    $after    = @()
    $changed  = $false
    $verifyOk = $true

    foreach ($a in $adapter) {
        $path = "HKLM:\SOFTWARE\Microsoft\DusmSvc\Profiles\$($a.InterfaceGuid)\*"

        # Kein Schlüssel = Standardwert (Aus) -> nichts zu tun
        if (-not (Test-Path -LiteralPath $path)) { $before += "$($a.Name)=no key"; continue }

        $value = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).UserCost
        $before += "$($a.Name)=$value"

        # Wert ungleich 0 -> Getaktete Verbindung ist Ein -> auf 0 setzen
        if ($value -and $value -ne 0) {
            Set-ItemProperty -LiteralPath $path -Name UserCost -Value 0 -ErrorAction Stop
            $changed = $true
        }
    }

    if ($changed) {
        # Dienst neu starten, damit Windows den neuen Wert übernimmt
        Restart-Service DusmSvc -Force -ErrorAction Stop

        # Kontrolle: Wert nochmal lesen
        foreach ($a in $adapter) {
            $path = "HKLM:\SOFTWARE\Microsoft\DusmSvc\Profiles\$($a.InterfaceGuid)\*"
            if (Test-Path -LiteralPath $path) {
                $value = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).UserCost
                $after += "$($a.Name)=$value"
                if ($value -and $value -ne 0) { $verifyOk = $false }
            }
        }
    }

    # Ergebnis an den Server zurückgeben
    [pscustomobject]@{
        Manufacturer = $pc.Manufacturer
        Model        = $pc.Model
        HasEthernet  = ($adapter.Count -gt 0)
        Changed      = $changed
        VerifyOk     = $verifyOk
        Before       = $before -join ', '
        After        = $after  -join ', '
    }
}

# Ein Gerät über WinRM prüfen und ggf. korrigieren
function Invoke-UCMMeteredFix {
    param([string]$ComputerName,[pscredential]$Credential)

    # Ergebniszeile für dieses Gerät
    $out = [pscustomobject]@{
        Device=$ComputerName; Status=''; Manufacturer=''; Model=''; Before=''; After=''; Message=''; Reboot=''
    }

    try {
        $r = Invoke-Command -ComputerName $ComputerName -Credential $Credential `
                -SessionOption $script:UCMSessionOption -ErrorAction Stop -ScriptBlock $script:UCMFixBlock

        $out.Manufacturer = $r.Manufacturer
        $out.Model        = $r.Model
        $out.Before       = $r.Before
        $out.After        = $r.After

        # Status festlegen
        if     (-not $r.HasEthernet)        { $out.Status = 'No Ethernet' }
        elseif ($r.Changed -and $r.VerifyOk) { $out.Status = 'Fixed' }
        elseif ($r.Changed)                  { $out.Status = 'Error'; $out.Message = 'Value still not 0 after change.' }
        else                                 { $out.Status = 'Already Off' }
    } catch {
        # Verbindungsfehler = Offline, alles andere = Fehler
        $out.Status  = if ($_.Exception -is [System.Management.Automation.Remoting.PSRemotingTransportException]) { 'Offline' } else { 'Error' }
        $out.Message = $_.Exception.Message
    }
    $out
}

# Neustart auf einem Gerät auslösen (mit Vorwarnung für den Benutzer)
function Restart-UCMComputer {
    param([string]$ComputerName,[pscredential]$Credential,[int]$DelaySeconds = 300)
    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -SessionOption $script:UCMSessionOption `
            -ErrorAction Stop -ArgumentList $DelaySeconds -ScriptBlock {
                param($Delay)
                $min = [math]::Ceiling($Delay / 60)
                shutdown.exe /r /t $Delay /c "IT maintenance: a network setting was corrected. This PC will restart in $min minutes. Please save your work."
                if ($LASTEXITCODE -ne 0) { throw "shutdown.exe returned exit code $LASTEXITCODE" }
            }
        [pscustomobject]@{ Success=$true;  Message="Reboot triggered on $ComputerName." }
    } catch {
        [pscustomobject]@{ Success=$false; Message="Reboot failed: $($_.Exception.Message)" }
    }
}

# Bericht und Wiederholungsliste als CSV speichern
function Export-UCMReport {
    if (-not (Test-Path -LiteralPath $UCMReportFolder)) {
        New-Item -ItemType Directory -Path $UCMReportFolder -Force | Out-Null
    }

    # Vollständiger Bericht (eine Zeile pro Gerät)
    $report = Join-Path $UCMReportFolder "MeteredFix_Report_$($script:UCMRunStamp).csv"
    $script:UCMResults | Export-Csv $report -NoTypeInformation -Delimiter ';' -Encoding UTF8

    # Offline-/Fehler-Geräte als eigene CSV, die direkt wieder importiert werden kann
    $retry = @($script:UCMResults | Where-Object { $_.Status -in 'Offline','Error' })
    $script:UCMRetryPath = $null
    if ($retry.Count -gt 0) {
        $script:UCMRetryPath = Join-Path $UCMReportFolder "MeteredFix_Retry_$($script:UCMRunStamp).csv"
        $retry | Select-Object @{ n='Name'; e={ $_.Device } } |
            Export-Csv $script:UCMRetryPath -NoTypeInformation -Delimiter ';' -Encoding UTF8
    }
    $script:UCMReportPath = $report
}


#==============================================
# Gemeinsame Einstellungen für alle Dialoge
#==============================================
$UCMBase = @{ Title=$UCMTitle; Subtitle='Metered Ethernet Fix'; NoExitOnTimeout=$true }


#==============================================
# Ablaufsteuerung (State Machine)
#==============================================
$script:UCMCred=$null; $script:UCMDomain=$null; $script:UCMUser=$null
$script:UCMDevices=@(); $script:UCMResults=$null; $script:UCMFailMsg=$null
$state='Login'; $retryState=$null

while ($state -and $state -ne 'exit') {
    switch ($state) {

        # ---- Startbildschirm ----
        'Login' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Willkommen bei UCM.`n`nGetaktete Verbindung (Ethernet) - check, fix and reboot affected devices." -ButtonLeftText 'Login' -ButtonRightText 'Exit'
            $state = if ($r -eq 'Login') { 'Domain' } else { 'exit' }
        }

        # ---- Domäne auswählen ----
        'Domain' {
            $r    = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue '1' -Message "Choose Domain Number:`n`n1. ezifa`n2. Domain 2`n3. Domain 3`n4. Domain 4" -ButtonRightText 'Next'
            $num  = Get-UCMInputText $r
            $fqdn = Resolve-UCMDomain $num
            if ($fqdn) { $script:UCMDomain = $fqdn; $state = 'User' }
            else { $retryState = 'Domain'; $script:UCMFailMsg = "Invalid domain number: $num"; $state = 'Failed' }
        }

        # ---- Benutzername eingeben ----
        'User' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Domain: $($script:UCMDomain)`n`nEnter user name:" -ButtonRightText 'Next'
            $script:UCMUser = Get-UCMInputText $r
            $state = if ([string]::IsNullOrWhiteSpace($script:UCMUser)) { 'Login' } else { 'Password' }
        }

        # ---- Kennwort eingeben und prüfen ----
        'Password' {
            $r  = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Enter password for $($script:UCMUser):" -ButtonRightText 'Login'
            $pw = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($pw)) { $state = 'Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Analyzing credentials...'
                $auth = Test-UCMCredential -DomainFqdn $script:UCMDomain -User $script:UCMUser -PlainPw $pw
                Close-ADTInstallationProgress

                if ($auth.Success) {
                    # Anmeldedaten im Format DOMAIN\user für WinRM speichern
                    $sec     = ConvertTo-SecureString $pw -AsPlainText -Force
                    $account = if ($script:UCMUser -match '[\\@]') { $script:UCMUser } else { "$($script:UCMDomain)\$($script:UCMUser)" }
                    $script:UCMCred = [System.Management.Automation.PSCredential]::new($account, $sec)
                    $pw = $null; $sec = $null
                    $state = 'ImportCsv'
                } else {
                    $retryState = 'Password'; $script:UCMFailMsg = $auth.Message; $state = 'Failed'
                }
            }
        }

        # ---- CSV-Datei importieren ----
        'ImportCsv' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue $UCMCsvPath -Message "Logged in as $($script:UCMCred.UserName).`n`nPath to the CSV file with the affected devices:" -ButtonLeftText 'Import' -ButtonRightText 'Cancel'

            if ((Get-UCMButton $r) -eq 'Cancel') { $state = 'Login' }
            else {
                $path = Get-UCMInputText $r
                if ([string]::IsNullOrWhiteSpace($path)) { $path = $UCMCsvPath }   # leeres Feld -> Standardpfad
                $path = $path.Trim().Trim('"')                                      # Anführungszeichen von "Als Pfad kopieren" entfernen

                $imp = Import-UCMDeviceList -Path $path
                Write-ADTLogEntry -Message "IMPORT $path -> $($imp.Message)" -Source 'UCM'

                if ($imp.Success) { $UCMCsvPath = $path; $script:UCMDevices = $imp.Devices; $state = 'Confirm' }
                else { $retryState = 'ImportCsv'; $script:UCMFailMsg = $imp.Message; $state = 'Failed' }
            }
        }

        # ---- Geräteliste anzeigen und Start bestätigen ----
        'Confirm' {
            $count   = $script:UCMDevices.Count
            $preview = ($script:UCMDevices | Select-Object -First 10) -join "`n"
            if ($count -gt 10) { $preview += "`n... and $($count - 10) more" }

            $r = Show-ADTInstallationPrompt @UCMBase -Message "$count devices imported:`n`n$preview`n`nStart check and fix?" -ButtonLeftText 'Start' -ButtonRightText 'Cancel'
            $state = if ($r -eq 'Start') { 'Fix' } else { 'ImportCsv' }
        }

        # ---- Alle Geräte nacheinander prüfen und korrigieren ----
        'Fix' {
            $script:UCMRunStamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
            $script:UCMResults  = [System.Collections.Generic.List[object]]::new()
            $script:UCMCount    = [ordered]@{ 'Fixed'=0; 'Already Off'=0; 'No Ethernet'=0; 'Offline'=0; 'Error'=0 }
            $total = $script:UCMDevices.Count
            $i = 0

            foreach ($pcName in $script:UCMDevices) {
                $i++
                $c = $script:UCMCount

                # Fortschritt anzeigen
                Show-ADTInstallationProgress -StatusMessage ("Checking device {0} of {1}: {2}`n`nFixed: {3}  |  Already Off: {4}  |  Offline: {5}  |  Error: {6}" -f `
                    $i, $total, $pcName, $c['Fixed'], $c['Already Off'], $c['Offline'], $c['Error'])

                # Gerät prüfen und ggf. korrigieren
                $res = Invoke-UCMMeteredFix -ComputerName $pcName -Credential $script:UCMCred
                $script:UCMResults.Add($res)
                $script:UCMCount[$res.Status]++

                # Ins PSADT-Log schreiben (1 = Info, 2 = Warnung, 3 = Fehler)
                $sev = if ($res.Status -eq 'Error') { 3 } elseif ($res.Status -eq 'Offline') { 2 } else { 1 }
                Write-ADTLogEntry -Message ("FIX [{0}/{1}] {2}: {3} | Before: {4} | After: {5} {6}" -f $i, $total, $pcName, $res.Status, $res.Before, $res.After, $res.Message) -Severity $sev -Source 'UCM'
            }

            Close-ADTInstallationProgress
            Export-UCMReport
            $state = 'Summary'
        }

        # ---- Zusammenfassung und Neustart-Frage ----
        'Summary' {
            $c     = $script:UCMCount
            $fixed = @($script:UCMResults | Where-Object Status -eq 'Fixed')
            $msg   = "Check complete.`n`n" +
                     "Devices: $($script:UCMResults.Count)`n" +
                     "Fixed (UserCost -> 0): $($c['Fixed'])`n" +
                     "Already Off: $($c['Already Off'])`n" +
                     "No Ethernet adapter: $($c['No Ethernet'])`n" +
                     "Offline: $($c['Offline'])`n" +
                     "Error: $($c['Error'])`n`n" +
                     "Report: $($script:UCMReportPath)"

            if ($fixed.Count -gt 0) {
                $r = Show-ADTInstallationPrompt @UCMBase -Message "$msg`n`nRestart the $($fixed.Count) fixed devices one by one now?" -ButtonLeftText 'Reboot' -ButtonRightText 'Skip'
                $state = if ($r -eq 'Reboot') { 'Reboot' } else { 'Done' }
            } else {
                Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonRightText 'OK' | Out-Null
                $state = 'Done'
            }
        }

        # ---- Korrigierte Geräte nacheinander neu starten ----
        'Reboot' {
            $fixed = @($script:UCMResults | Where-Object Status -eq 'Fixed')
            $okCount = 0; $failCount = 0

            for ($j = 0; $j -lt $fixed.Count; $j++) {
                $dev = $fixed[$j]
                Show-ADTInstallationProgress -StatusMessage ("Reboot {0} of {1}: {2}`n`nTriggered: {3}  |  Failed: {4}" -f ($j + 1), $fixed.Count, $dev.Device, $okCount, $failCount)

                $rb = Restart-UCMComputer -ComputerName $dev.Device -Credential $script:UCMCred -DelaySeconds $UCMRebootDelaySeconds
                if ($rb.Success) { $dev.Reboot = 'Triggered'; $okCount++ } else { $dev.Reboot = $rb.Message; $failCount++ }
                Write-ADTLogEntry -Message "REBOOT $($dev.Device): $($rb.Message)" -Severity $(if ($rb.Success) { 1 } else { 3 }) -Source 'UCM'

                # Pause vor dem nächsten Gerät
                if ($j -lt $fixed.Count - 1) { Start-Sleep -Seconds $UCMRebootPauseSeconds }
            }

            Close-ADTInstallationProgress
            Export-UCMReport   # Bericht erneut speichern, jetzt mit Neustart-Spalte
            $state = 'Done'
        }

        # ---- Abschluss ----
        'Done' {
            $msg = "Maintenance finished.`n`nReport: $($script:UCMReportPath)"
            if ($script:UCMRetryPath) { $msg += "`n`nOffline/Error devices for a new run:`n$($script:UCMRetryPath)" }

            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Start New' -ButtonRightText 'Close'
            $state = if ($r -eq 'Start New') { 'ImportCsv' } else { 'exit' }
        }

        # ---- Fehleranzeige mit Wiederholen ----
        'Failed' {
            $msg = if ($script:UCMFailMsg) { "Failed:`n`n$($script:UCMFailMsg)" } else { 'Failed.' }
            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Try Again' -ButtonRightText 'Cancel'
            $script:UCMFailMsg = $null
            $state = if ($r -eq 'Try Again' -and $retryState) { $retryState } else { 'Login' }
        }
    }
}
