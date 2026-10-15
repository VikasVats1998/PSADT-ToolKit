#==============================================
# UCM Wartungs-Tool
# Getaktete Verbindung (Ethernet) auf "Aus" setzen
#==============================================

Add-Type -AssemblyName System.DirectoryServices.AccountManagement


#----------------------------------------------
# 1. EINSTELLUNGEN (hier anpassen)
#----------------------------------------------
$Titel            = 'IT Help Desk - Wartung'
$Untertitel       = 'Getaktete Verbindung (Ethernet)'
$CsvDatei         = 'C:\PSADT-Stuff\Getaktete-Verbindung-Maintainence-App\SupportFiles\Getaktet_Status.csv'
$BerichtOrdner    = 'C:\Temp'
$NeustartWarnzeit = 300     # Sekunden bis zum Neustart (300 = 5 Minuten)
$NeustartPause    = 10      # Sekunden Pause zwischen zwei Neustarts

# WinRM: höchstens 15 Sekunden auf ein Gerät warten
$WinRMOptionen = New-PSSessionOption -OpenTimeout 15000

# Grundeinstellungen für alle Dialogfenster
$Dialog = @{
    Title           = $Titel
    Subtitle        = $Untertitel
    NoExitOnTimeout = $true
}


#----------------------------------------------
# 2. FUNKTIONEN
#----------------------------------------------

# Fortschrittsfenster mit eigenem Titel und eigenem Hinweistext anzeigen
function Show-Fortschritt {
    param($Text, $Hinweis)

    Show-ADTInstallationProgress -Title $Titel -Subtitle $Untertitel -StatusMessage $Text -StatusMessageDetail $Hinweis
}


# Domänennummer in Domänennamen umwandeln
function Get-Domaene {
    param($Nummer)

    switch ($Nummer) {
        '1'     { return 'ezifa' }
        '2'     { return 'domain2' }
        '3'     { return 'domain3' }
        '4'     { return 'domain4' }
        default { return $null }
    }
}


# Den eingegebenen Text aus einem Dialogfenster lesen
function Get-Eingabe {
    param($Ergebnis)

    if ($Ergebnis -eq $null)    { return $null }
    if ($Ergebnis -is [string]) { return $Ergebnis }
    return $Ergebnis.Text
}


# Benutzername und Kennwort gegen die Domäne prüfen
# Rückgabe: $true = richtig, $false = falsch
function Test-Anmeldung {
    param($Domaene, $Benutzer, $Kennwort)

    try {
        $kontext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $Domaene)
        return $kontext.ValidateCredentials($Benutzer, $Kennwort)
    }
    catch {
        return $false
    }
}


# Betroffene Geräte aus der CSV-Datei lesen
# Es werden nur Zeilen mit Status "Betroffen" übernommen
function Get-GeraeteAusCsv {
    param($Pfad)

    $geraete = @()

    if (-not (Test-Path $Pfad)) {
        return $geraete
    }

    # Datei lesen (funktioniert mit allen Zeilenenden)
    $text    = [System.IO.File]::ReadAllText($Pfad)
    $zeilen  = $text -split "`r`n|`r|`n"
    $tabelle = $zeilen | ConvertFrom-Csv -Delimiter ';'

    foreach ($zeile in $tabelle) {
        if ($zeile.Status -eq 'Betroffen' -and $zeile.Geraetname) {
            $geraete += $zeile.Geraetname.Trim()
        }
    }

    return $geraete
}


# Auf einem Gerät UserCost prüfen und bei Bedarf auf 0 setzen
function Set-UserCostAus {
    param($Computer, $Anmeldung)

    try {
        $antwort = Invoke-Command -ComputerName $Computer -Credential $Anmeldung -SessionOption $WinRMOptionen -ErrorAction Stop -ScriptBlock {

            # --- Ab hier läuft alles auf dem Zielgerät ---

            $status = 'Bereits Aus'
            $vorher = ''

            # Alle Ethernet-Adapter holen (802.3 = Ethernet)
            $adapterListe = Get-NetAdapter -Physical | Where-Object PhysicalMediaType -eq '802.3'

            if (-not $adapterListe) {
                $status = 'Kein Ethernet'
            }

            foreach ($adapter in $adapterListe) {
                $pfad = "HKLM:\SOFTWARE\Microsoft\DusmSvc\Profiles\$($adapter.InterfaceGuid)\*"

                # Gibt es den Registry-Schlüssel?
                if (Test-Path -LiteralPath $pfad) {
                    $wert   = (Get-ItemProperty -LiteralPath $pfad).UserCost
                    $vorher = $vorher + $adapter.Name + '=' + $wert + ' '

                    # Wert ist nicht 0 -> Getaktete Verbindung ist Ein -> auf 0 setzen
                    if ($wert -and $wert -ne 0) {
                        Set-ItemProperty -LiteralPath $pfad -Name UserCost -Value 0
                        $status = 'Korrigiert'
                    }
                }
            }

            # Dienst neu starten, damit Windows den neuen Wert übernimmt
            if ($status -eq 'Korrigiert') {
                Restart-Service DusmSvc -Force
            }

            # Hersteller und Modell lesen
            $pc = Get-CimInstance Win32_ComputerSystem

            # Ergebnis zurückgeben
            [pscustomobject]@{
                Status     = $status
                Vorher     = $vorher
                Hersteller = $pc.Manufacturer
                Modell     = $pc.Model
            }
        }

        return $antwort
    }
    catch {
        # Gerät hat nicht geantwortet
        return [pscustomobject]@{
            Status     = 'Nicht erreichbar'
            Vorher     = ''
            Hersteller = ''
            Modell     = ''
        }
    }
}


# Neustart auf einem Gerät auslösen (mit Vorwarnung für den Benutzer)
function Start-Neustart {
    param($Computer, $Anmeldung)

    try {
        Invoke-Command -ComputerName $Computer -Credential $Anmeldung -SessionOption $WinRMOptionen -ErrorAction Stop -ArgumentList $NeustartWarnzeit -ScriptBlock {
            param($Sekunden)
            $minuten = [math]::Ceiling($Sekunden / 60)
            shutdown.exe /r /t $Sekunden /c "IT-Wartung: Eine Netzwerkeinstellung wurde korrigiert. Ihr PC wird in $minuten Minuten neu gestartet. Bitte speichern Sie Ihre Arbeit."
        }
        return 'Ausgelöst'
    }
    catch {
        return 'Fehlgeschlagen'
    }
}


# Liste als CSV-Datei speichern
function Save-Bericht {
    param($Liste, $Datei)

    if (-not (Test-Path $BerichtOrdner)) {
        New-Item -ItemType Directory -Path $BerichtOrdner | Out-Null
    }

    $Liste | Export-Csv $Datei -NoTypeInformation -Delimiter ';' -Encoding UTF8
}


#----------------------------------------------
# 3. ABLAUF (Schritt für Schritt)
#----------------------------------------------
$state         = 'Start'
$zurueckZu     = $null
$Fehlermeldung = ''

while ($state -ne 'Ende') {

    switch ($state) {

        # ---- Startbildschirm ----
        'Start' {
            $r = Show-ADTInstallationPrompt @Dialog -Message "Willkommen bei UCM.`n`nMit diesem Tool wird die getaktete Verbindung auf Ethernet geprüft, korrigiert und die Geräte werden bei Bedarf neu gestartet." -ButtonLeftText 'Anmelden' -ButtonRightText 'Beenden'

            if ($r -eq 'Anmelden') { $state = 'Domaene' }
            else                   { $state = 'Ende' }
        }

        # ---- Domäne wählen ----
        'Domaene' {
            $r       = Show-ADTInstallationPrompt @Dialog -RequestInput -DefaultValue '1' -Message "Bitte die Nummer der Domäne eingeben:`n`n1. ezifa`n2. Domäne 2`n3. Domäne 3`n4. Domäne 4" -ButtonRightText 'Weiter'
            $nummer  = Get-Eingabe $r
            $Domaene = Get-Domaene $nummer

            if ($Domaene) {
                $state = 'Benutzer'
            }
            else {
                $Fehlermeldung = "Ungültige Domänennummer: $nummer"
                $zurueckZu     = 'Domaene'
                $state         = 'Fehler'
            }
        }

        # ---- Benutzername ----
        'Benutzer' {
            $r = Show-ADTInstallationPrompt @Dialog -RequestInput -Message "Domäne: $Domaene`n`nBitte den Benutzernamen eingeben:" -ButtonRightText 'Weiter'
            $Benutzer = Get-Eingabe $r

            if ($Benutzer) {
                # Falls "DOMAIN\name" eingegeben wurde, nur den Namen behalten
                $Benutzer = $Benutzer.Split('\')[-1].Trim()
                $state    = 'Kennwort'
            }
            else {
                $state = 'Start'
            }
        }

        # ---- Kennwort ----
        'Kennwort' {
            $r = Show-ADTInstallationPrompt @Dialog -RequestInput -Message "Bitte das Kennwort für $Benutzer eingeben:" -ButtonRightText 'Anmelden'
            $kennwort = Get-Eingabe $r

            if (-not $kennwort) {
                $state = 'Start'
            }
            else {
                Show-Fortschritt -Text 'Anmeldedaten werden geprüft...' -Hinweis 'Bitte warten.'
                $richtig = Test-Anmeldung -Domaene $Domaene -Benutzer $Benutzer -Kennwort $kennwort
                Close-ADTInstallationProgress

                if ($richtig) {
                    # Anmeldedaten für WinRM speichern (Format: DOMAIN\Benutzer)
                    $sicheresKennwort = ConvertTo-SecureString $kennwort -AsPlainText -Force
                    $Anmeldung = New-Object System.Management.Automation.PSCredential("$Domaene\$Benutzer", $sicheresKennwort)
                    $kennwort  = $null
                    $state     = 'CsvImport'
                }
                else {
                    $Fehlermeldung = 'Benutzername oder Kennwort ist falsch, oder die Domäne ist nicht erreichbar.'
                    $zurueckZu     = 'Kennwort'
                    $state         = 'Fehler'
                }
            }
        }

        # ---- CSV-Datei importieren ----
        'CsvImport' {
            $r = Show-ADTInstallationPrompt @Dialog -RequestInput -DefaultValue $CsvDatei -Message "Angemeldet als $Domaene\$Benutzer`n`nPfad zur CSV-Datei mit den betroffenen Geräten:" -ButtonLeftText 'Importieren' -ButtonRightText 'Abbrechen'

            if ($r.Result -eq 'Abbrechen') {
                $state = 'Start'
            }
            else {
                $pfad = Get-Eingabe $r
                if (-not $pfad) { $pfad = $CsvDatei }     # leeres Feld -> Standardpfad
                $pfad = $pfad.Trim('"', ' ')              # Anführungszeichen entfernen

                $Geraete = @(Get-GeraeteAusCsv -Pfad $pfad)

                if ($Geraete.Count -gt 0) {
                    $CsvDatei = $pfad
                    $state    = 'Bestaetigen'
                }
                else {
                    $Fehlermeldung = "In dieser Datei wurden keine betroffenen Geräte gefunden:`n$pfad"
                    $zurueckZu     = 'CsvImport'
                    $state         = 'Fehler'
                }
            }
        }

        # ---- Start bestätigen ----
        'Bestaetigen' {
            $liste = $Geraete -join "`n"
            if ($Geraete.Count -gt 10) {
                $liste = ($Geraete[0..9] -join "`n") + "`n... und $($Geraete.Count - 10) weitere"
            }

            $r = Show-ADTInstallationPrompt @Dialog -Message "$($Geraete.Count) betroffene Geräte importiert:`n`n$liste`n`nPrüfung und Korrektur jetzt starten?" -ButtonLeftText 'Starten' -ButtonRightText 'Abbrechen'

            if ($r -eq 'Starten') { $state = 'Pruefen' }
            else                  { $state = 'CsvImport' }
        }

        # ---- Alle Geräte nacheinander prüfen und korrigieren ----
        'Pruefen' {
            $Ergebnisse       = @()
            $gesamt           = $Geraete.Count
            $nr               = 0
            $anzahlKorrigiert = 0
            $anzahlAus        = 0
            $anzahlOffline    = 0
            $anzahlOhne       = 0

            foreach ($geraet in $Geraete) {
                $nr++

                # Fortschritt anzeigen
                $text = "Gerät $nr von $gesamt wird geprüft: $geraet`n`n"
                $text = $text + "Korrigiert: $anzahlKorrigiert  |  Bereits Aus: $anzahlAus  |  Nicht erreichbar: $anzahlOffline"
                Show-Fortschritt -Text $text -Hinweis 'Bitte warten, die Geräte werden nacheinander geprüft.'

                # Gerät prüfen und ggf. korrigieren
                $antwort = Set-UserCostAus -Computer $geraet -Anmeldung $Anmeldung

                # Zähler erhöhen
                if ($antwort.Status -eq 'Korrigiert')       { $anzahlKorrigiert++ }
                if ($antwort.Status -eq 'Bereits Aus')      { $anzahlAus++ }
                if ($antwort.Status -eq 'Nicht erreichbar') { $anzahlOffline++ }
                if ($antwort.Status -eq 'Kein Ethernet')    { $anzahlOhne++ }

                # Ergebnis merken
                $Ergebnisse += [pscustomobject]@{
                    Geraetname = $geraet
                    Status     = $antwort.Status
                    Vorher     = $antwort.Vorher
                    Hersteller = $antwort.Hersteller
                    Modell     = $antwort.Modell
                    Neustart   = ''
                }

                Write-ADTLogEntry -Message "$geraet : $($antwort.Status) $($antwort.Vorher)" -Source 'UCM'
            }

            Close-ADTInstallationProgress

            # Bericht speichern
            $zeit    = Get-Date -Format 'yyyy-MM-dd_HHmm'
            $Bericht = "$BerichtOrdner\GetaktetFix_Bericht_$zeit.csv"
            Save-Bericht -Liste $Ergebnisse -Datei $Bericht

            # Nicht erreichbare Geräte als neue CSV speichern (kann später wieder importiert werden)
            $Wiederholen  = ''
            $offlineListe = @()
            foreach ($e in $Ergebnisse) {
                if ($e.Status -eq 'Nicht erreichbar') {
                    $offlineListe += [pscustomobject]@{ Geraetname = $e.Geraetname; Status = 'Betroffen' }
                }
            }
            if ($offlineListe.Count -gt 0) {
                $Wiederholen = "$BerichtOrdner\GetaktetFix_Wiederholen_$zeit.csv"
                Save-Bericht -Liste $offlineListe -Datei $Wiederholen
            }

            $state = 'Zusammenfassung'
        }

        # ---- Zusammenfassung ----
        'Zusammenfassung' {
            $text = "Prüfung abgeschlossen.`n`n"
            $text = $text + "Geräte gesamt: $gesamt`n"
            $text = $text + "Korrigiert (UserCost -> 0): $anzahlKorrigiert`n"
            $text = $text + "Bereits Aus: $anzahlAus`n"
            $text = $text + "Kein Ethernet-Adapter: $anzahlOhne`n"
            $text = $text + "Nicht erreichbar: $anzahlOffline`n`n"
            $text = $text + "Bericht: $Bericht"

            if ($anzahlKorrigiert -gt 0) {
                $r = Show-ADTInstallationPrompt @Dialog -Message "$text`n`nSollen die $anzahlKorrigiert korrigierten Geräte jetzt nacheinander neu gestartet werden?" -ButtonLeftText 'Neustart' -ButtonRightText 'Überspringen'

                if ($r -eq 'Neustart') { $state = 'Neustart' }
                else                   { $state = 'Fertig' }
            }
            else {
                Show-ADTInstallationPrompt @Dialog -Message $text -ButtonRightText 'OK' | Out-Null
                $state = 'Fertig'
            }
        }

        # ---- Korrigierte Geräte nacheinander neu starten ----
        'Neustart' {
            $nr = 0

            foreach ($e in $Ergebnisse) {
                if ($e.Status -eq 'Korrigiert') {
                    $nr++
                    Show-Fortschritt -Text "Neustart $nr von $anzahlKorrigiert : $($e.Geraetname)" -Hinweis 'Die Geräte werden nacheinander neu gestartet.'

                    $e.Neustart = Start-Neustart -Computer $e.Geraetname -Anmeldung $Anmeldung
                    Write-ADTLogEntry -Message "Neustart $($e.Geraetname) : $($e.Neustart)" -Source 'UCM'

                    # Kurze Pause vor dem nächsten Gerät
                    Start-Sleep -Seconds $NeustartPause
                }
            }

            Close-ADTInstallationProgress

            # Bericht nochmal speichern, jetzt mit Neustart-Spalte
            Save-Bericht -Liste $Ergebnisse -Datei $Bericht

            $state = 'Fertig'
        }

        # ---- Fertig ----
        'Fertig' {
            $text = "Wartung abgeschlossen.`n`nBericht: $Bericht"
            if ($Wiederholen) {
                $text = $text + "`n`nNicht erreichbare Geräte (später erneut importieren):`n$Wiederholen"
            }

            $r = Show-ADTInstallationPrompt @Dialog -Message $text -ButtonLeftText 'Neuer Durchlauf' -ButtonRightText 'Schließen'

            if ($r -eq 'Neuer Durchlauf') { $state = 'CsvImport' }
            else                          { $state = 'Ende' }
        }

        # ---- Fehler anzeigen ----
        'Fehler' {
            $r = Show-ADTInstallationPrompt @Dialog -Message "Fehler:`n`n$Fehlermeldung" -ButtonLeftText 'Erneut versuchen' -ButtonRightText 'Abbrechen'

            if ($r -eq 'Erneut versuchen' -and $zurueckZu) { $state = $zurueckZu }
            else                                            { $state = 'Start' }
        }
    }
}
