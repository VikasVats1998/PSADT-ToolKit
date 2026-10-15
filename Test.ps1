#==============================================
# MARK: UCM Maintenance Wizard - Metered Ethernet Fix
#==============================================

Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# ---- Config: EDIT THESE ----
$UCMTitle              = 'IT Help Desk - Maintenance'
$UCMCsvPath            = 'C:\Temp\Geraete.csv'   # default path, can be changed in the wizard
$UCMCsvDelimiter       = ';'
$UCMReportFolder       = 'C:\Temp'
$UCMRebootDelaySeconds = 300    # warning time for the user before restart (300 = 5 min)
$UCMRebootPauseSeconds = 10     # pause between two reboot commands
$script:UCMSessionOption = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

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

# ---- Extract typed text from an InputDialogResult (defensive across builds) ----
function Get-UCMInputText {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    foreach ($p in 'Text','Input','InputText','Value','Response','SelectedItem') {
        $prop = $Result.PSObject.Properties[$p]
        if ($prop -and $null -ne $prop.Value) {
            if ($prop.Value -is [securestring]) { return (New-Object System.Management.Automation.PSCredential 'x', $prop.Value).GetNetworkCredential().Password }
            return [string]$prop.Value
        }
    }
    return [string]$Result
}

# ---- Which button was clicked on an input prompt ----
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

# ---- Backend ----
function Test-UCMCredential {
    param([string]$DomainFqdn,[string]$User,[string]$PlainPw)
    try {
        # DOMAIN\user -> user, user@domain -> user
        $sam = if ($User -match '\\') { ($User -split '\\')[-1] }
               elseif ($User -match '@') { ($User -split '@')[0] }
               else { $User }
        $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                   [System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainFqdn)
        $ok = $ctx.ValidateCredentials($sam, $PlainPw)
        if ($ok) { [pscustomobject]@{ Success=$true;  Message="Authenticated against $DomainFqdn" } }
        else     { [pscustomobject]@{ Success=$false; Message='Invalid username or password.' } }
    } catch { [pscustomobject]@{ Success=$false; Message="Domain not reachable: $($_.Exception.Message)" } }
}

function Import-UCMDeviceList {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Success=$false; Message="CSV file not found: $Path"; Devices=@() }
    }
    try {
        # Get-Content handles Windows, Mac and Linux line endings
        $rows = @(Get-Content -LiteralPath $Path -ErrorAction Stop | ConvertFrom-Csv -Delimiter $UCMCsvDelimiter)
        if ($rows.Count -eq 0) {
            return [pscustomobject]@{ Success=$false; Message='CSV file is empty.'; Devices=@() }
        }
        $cols = $rows[0].PSObject.Properties.Name
        $col  = @('Name','Geraetename','Device') | Where-Object { $cols -contains $_ } | Select-Object -First 1
        if (-not $col) {
            return [pscustomobject]@{ Success=$false; Message="No column 'Name' found. Columns: $($cols -join ', ')"; Devices=@() }
        }
        # CSV from the scan script: take only affected devices
        if ($cols -contains 'Status') { $rows = @($rows | Where-Object { $_.Status -eq 'Betroffen' }) }

        $devices = @($rows | ForEach-Object { "$($_.$col)".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        if ($devices.Count -eq 0) {
            return [pscustomobject]@{ Success=$false; Message='No device names found in the CSV file.'; Devices=@() }
        }
        [pscustomobject]@{ Success=$true; Message="$($devices.Count) devices imported."; Devices=$devices }
    } catch {
        [pscustomobject]@{ Success=$false; Message="CSV import failed: $($_.Exception.Message)"; Devices=@() }
    }
}

# ---- Runs ON the target device: read UserCost, set to 0 if needed, verify ----
$script:UCMFixBlock = {
    $pc        = Get-CimInstance Win32_ComputerSystem
    $adapter   = @(Get-NetAdapter -Physical | Where-Object PhysicalMediaType -eq '802.3')
    $before    = @()
    $after     = @()
    $changed   = $false
    $verifyOk  = $true

    foreach ($a in $adapter) {
        $path = "HKLM:\SOFTWARE\Microsoft\DusmSvc\Profiles\$($a.InterfaceGuid)\*"
        if (-not (Test-Path -LiteralPath $path)) { $before += "$($a.Name)=no key"; continue }

        $value = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).UserCost
        $before += "$($a.Name)=$value"

        if ($value -and $value -ne 0) {
            Set-ItemProperty -LiteralPath $path -Name UserCost -Value 0 -ErrorAction Stop
            $changed = $true
        }
    }

    if ($changed) {
        Restart-Service DusmSvc -Force -ErrorAction Stop
        # Read again to verify
        foreach ($a in $adapter) {
            $path = "HKLM:\SOFTWARE\Microsoft\DusmSvc\Profiles\$($a.InterfaceGuid)\*"
            if (Test-Path -LiteralPath $path) {
                $value = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).UserCost
                $after += "$($a.Name)=$value"
                if ($value -and $value -ne 0) { $verifyOk = $false }
            }
        }
    }

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

function Invoke-UCMMeteredFix {
    param([string]$ComputerName,[pscredential]$Credential)
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
        if     (-not $r.HasEthernet)        { $out.Status = 'No Ethernet' }
        elseif ($r.Changed -and $r.VerifyOk) { $out.Status = 'Fixed' }
        elseif ($r.Changed)                  { $out.Status = 'Error'; $out.Message = 'Value still not 0 after change.' }
        else                                 { $out.Status = 'Already Off' }
    } catch {
        $out.Status  = if ($_.Exception -is [System.Management.Automation.Remoting.PSRemotingTransportException]) { 'Offline' } else { 'Error' }
        $out.Message = $_.Exception.Message
    }
    $out
}

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
    } catch { [pscustomobject]@{ Success=$false; Message="Reboot failed: $($_.Exception.Message)" } }
}

function Export-UCMReport {
    if (-not (Test-Path -LiteralPath $UCMReportFolder)) { New-Item -ItemType Directory -Path $UCMReportFolder -Force | Out-Null }
    $report = Join-Path $UCMReportFolder "MeteredFix_Report_$($script:UCMRunStamp).csv"
    $script:UCMResults | Export-Csv $report -NoTypeInformation -Delimiter ';' -Encoding UTF8

    # Offline/Error devices as a new CSV that can be imported again directly
    $retry = @($script:UCMResults | Where-Object { $_.Status -in 'Offline','Error' })
    $script:UCMRetryPath = $null
    if ($retry.Count -gt 0) {
        $script:UCMRetryPath = Join-Path $UCMReportFolder "MeteredFix_Retry_$($script:UCMRunStamp).csv"
        $retry | Select-Object @{ n='Name'; e={ $_.Device } } |
            Export-Csv $script:UCMRetryPath -NoTypeInformation -Delimiter ';' -Encoding UTF8
    }
    $script:UCMReportPath = $report
}

# ---- Shared prompt defaults ----
$UCMBase = @{ Title=$UCMTitle; Subtitle='Metered Ethernet Fix'; NoExitOnTimeout=$true }

# ---- State machine ----
$script:UCMCred=$null; $script:UCMDomain=$null; $script:UCMUser=$null
$script:UCMDevices=@(); $script:UCMResults=$null; $script:UCMFailMsg=$null
$state='Login'; $retryState=$null

while ($state -and $state -ne 'exit') {
    switch ($state) {

        'Login' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Willkommen bei UCM.`n`nGetaktete Verbindung (Ethernet) - check, fix and reboot affected devices." -ButtonLeftText 'Login' -ButtonRightText 'Exit'
            $state = if ($r -eq 'Login') { 'Domain' } else { 'exit' }
        }

        'Domain' {
            $r    = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue '1' -Message "Choose Domain Number:`n`n1. ezifa`n2. Domain 2`n3. Domain 3`n4. Domain 4" -ButtonRightText 'Next'
            $num  = Get-UCMInputText $r
            $fqdn = Resolve-UCMDomain $num
            if ($fqdn) { $script:UCMDomain = $fqdn; $state = 'User' }
            else { $retryState = 'Domain'; $script:UCMFailMsg = "Invalid domain number: $num"; $state = 'Failed' }
        }

        'User' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Domain: $($script:UCMDomain)`n`nEnter user name:" -ButtonRightText 'Next'
            $script:UCMUser = Get-UCMInputText $r
            $state = if ([string]::IsNullOrWhiteSpace($script:UCMUser)) { 'Login' } else { 'Password' }
        }

        'Password' {
            $r  = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Enter password for $($script:UCMUser):" -ButtonRightText 'Login'
            $pw = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($pw)) { $state = 'Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Analyzing credentials...'
                $auth = Test-UCMCredential -DomainFqdn $script:UCMDomain -User $script:UCMUser -PlainPw $pw
                Close-ADTInstallationProgress
                if ($auth.Success) {
                    $sec     = ConvertTo-SecureString $pw -AsPlainText -Force
                    $account = if ($script:UCMUser -match '[\\@]') { $script:UCMUser } else { "$($script:UCMDomain)\$($script:UCMUser)" }
                    $script:UCMCred = [System.Management.Automation.PSCredential]::new($account, $sec)
                    $pw = $null; $sec = $null
                    $state = 'ImportCsv'
                } else { $retryState = 'Password'; $script:UCMFailMsg = $auth.Message; $state = 'Failed' }
            }
        }

        'ImportCsv' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue $UCMCsvPath -Message "Logged in as $($script:UCMCred.UserName).`n`nPath to the CSV file with the affected devices:" -ButtonLeftText 'Import' -ButtonRightText 'Cancel'
            if ((Get-UCMButton $r) -eq 'Cancel') { $state = 'Login' }
            else {
                $path = Get-UCMInputText $r
                $imp  = Import-UCMDeviceList -Path $path
                Write-ADTLogEntry -Message "IMPORT $path -> $($imp.Message)" -Source 'UCM'
                if ($imp.Success) { $UCMCsvPath = $path; $script:UCMDevices = $imp.Devices; $state = 'Confirm' }
                else { $retryState = 'ImportCsv'; $script:UCMFailMsg = $imp.Message; $state = 'Failed' }
            }
        }

        'Confirm' {
            $count   = $script:UCMDevices.Count
            $preview = ($script:UCMDevices | Select-Object -First 10) -join "`n"
            if ($count -gt 10) { $preview += "`n... and $($count - 10) more" }
            $r = Show-ADTInstallationPrompt @UCMBase -Message "$count devices imported:`n`n$preview`n`nStart check and fix?" -ButtonLeftText 'Start' -ButtonRightText 'Cancel'
            $state = if ($r -eq 'Start') { 'Fix' } else { 'ImportCsv' }
        }

        'Fix' {
            $script:UCMRunStamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
            $script:UCMResults  = [System.Collections.Generic.List[object]]::new()
            $script:UCMCount    = [ordered]@{ 'Fixed'=0; 'Already Off'=0; 'No Ethernet'=0; 'Offline'=0; 'Error'=0 }
            $total = $script:UCMDevices.Count
            $i = 0

            foreach ($pcName in $script:UCMDevices) {
                $i++
                $c = $script:UCMCount
                Show-ADTInstallationProgress -StatusMessage ("Checking device {0} of {1}: {2}`n`nFixed: {3}  |  Already Off: {4}  |  Offline: {5}  |  Error: {6}" -f `
                    $i, $total, $pcName, $c['Fixed'], $c['Already Off'], $c['Offline'], $c['Error'])

                $res = Invoke-UCMMeteredFix -ComputerName $pcName -Credential $script:UCMCred
                $script:UCMResults.Add($res)
                $script:UCMCount[$res.Status]++

                $sev = if ($res.Status -eq 'Error') { 3 } elseif ($res.Status -eq 'Offline') { 2 } else { 1 }
                Write-ADTLogEntry -Message ("FIX [{0}/{1}] {2}: {3} | Before: {4} | After: {5} {6}" -f $i, $total, $pcName, $res.Status, $res.Before, $res.After, $res.Message) -Severity $sev -Source 'UCM'
            }

            Close-ADTInstallationProgress
            Export-UCMReport
            $state = 'Summary'
        }

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

        'Reboot' {
            $fixed = @($script:UCMResults | Where-Object Status -eq 'Fixed')
            $okCount = 0; $failCount = 0
            for ($j = 0; $j -lt $fixed.Count; $j++) {
                $dev = $fixed[$j]
                Show-ADTInstallationProgress -StatusMessage ("Reboot {0} of {1}: {2}`n`nTriggered: {3}  |  Failed: {4}" -f ($j + 1), $fixed.Count, $dev.Device, $okCount, $failCount)

                $rb = Restart-UCMComputer -ComputerName $dev.Device -Credential $script:UCMCred -DelaySeconds $UCMRebootDelaySeconds
                if ($rb.Success) { $dev.Reboot = 'Triggered'; $okCount++ } else { $dev.Reboot = $rb.Message; $failCount++ }
                Write-ADTLogEntry -Message "REBOOT $($dev.Device): $($rb.Message)" -Severity $(if ($rb.Success) { 1 } else { 3 }) -Source 'UCM'

                if ($j -lt $fixed.Count - 1) { Start-Sleep -Seconds $UCMRebootPauseSeconds }
            }
            Close-ADTInstallationProgress
            Export-UCMReport   # write report again, now with the Reboot column
            $state = 'Done'
        }

        'Done' {
            $msg = "Maintenance finished.`n`nReport: $($script:UCMReportPath)"
            if ($script:UCMRetryPath) { $msg += "`n`nOffline/Error devices for a new run:`n$($script:UCMRetryPath)" }
            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Start New' -ButtonRightText 'Close'
            $state = if ($r -eq 'Start New') { 'ImportCsv' } else { 'exit' }
        }

        'Failed' {
            $msg = if ($script:UCMFailMsg) { "Failed:`n`n$($script:UCMFailMsg)" } else { 'Failed.' }
            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Try Again' -ButtonRightText 'Cancel'
            $script:UCMFailMsg = $null
            $state = if ($r -eq 'Try Again' -and $retryState) { $retryState } else { 'Login' }
        }
    }
}
