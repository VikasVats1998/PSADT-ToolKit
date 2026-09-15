##================================================
## MARK: UCM Maintenance Wizard (PSADT-native UI)
##================================================

Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# ---- Config: EDIT THESE ----
function Resolve-UCMDomain {
    param([string]$Number)
    switch ($Number) {
        '1'     { 'dom1.example.local' }
        '2'     { 'dom2.example.local' }
        '3'     { 'dom3.example.local' }
        '4'     { 'dom4.example.local' }
        default { $null }
    }
}
# Hive: 'HKEY_LOCAL_MACHINE' or 'HKEY_USERS'. Name='' means delete the whole KEY (recursive); otherwise delete that VALUE.
$script:UCMTargets = @(
    [pscustomobject]@{ Index=1; Label='Example App Cache';   Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp\Cache';   Name='' }
    [pscustomobject]@{ Index=2; Label='Broken Policy Value';  Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp';         Name='BadPolicy' }
    [pscustomobject]@{ Index=3; Label='Stale Profile Key';    Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\ExampleApp\Profiles'; Name='' }
    [pscustomobject]@{ Index=4; Label='Legacy Add-in';        Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Vendor\Addin';       Name='' }
    [pscustomobject]@{ Index=5; Label='User Autostart Value'; Hive='HKEY_USERS';         Path='<SID>\SOFTWARE\Example';      Name='Runonce' }
)

$UCMTitle = 'IT Help Desk - LZFD Karlsruhe Maintenance'

# ---- Extract typed text from an InputDialogResult (defensive across builds) ----
function Get-UCMInputText {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    if ($Result -is [securestring]) { return (New-Object System.Management.Automation.PSCredential 'x', $Result).GetNetworkCredential().Password }
    foreach ($p in 'Text','Input','InputText','Value','Response','SelectedItem') {
        $prop = $Result.PSObject.Properties[$p]
        if ($prop -and $null -ne $prop.Value) {
            if ($prop.Value -is [securestring]) { return (New-Object System.Management.Automation.PSCredential 'x', $prop.Value).GetNetworkCredential().Password }
            return [string]$prop.Value
        }
    }
    return [string]$Result
}

# ---- Backend (returns Success/Message objects) ----
function Test-UCMCredential {
    param([string]$DomainFqdn,[string]$User,[string]$PlainPw)
    try {
        $sam = if ($User -match '[\\@]') { ($User -split '[\\@]')[-1] } else { $User }
        $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                    [System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainFqdn)
        $ok = $ctx.ValidateCredentials($sam, $PlainPw)
        if ($ok) { [pscustomobject]@{ Success=$true;  Message="Authenticated against $DomainFqdn" } }
        else     { [pscustomobject]@{ Success=$false; Message='Invalid username or password.' } }
    } catch { [pscustomobject]@{ Success=$false; Message="Domain not reachable: $($_.Exception.Message)" } }
}
function Test-UCMConnection {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        $n = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
        [pscustomobject]@{ Success=$true; Message="Connected to $n" }
    } catch { [pscustomobject]@{ Success=$false; Message="Cannot reach $ComputerName over WinRM: $($_.Exception.Message)" } }
}
function Get-UCMRegistryData {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        $data = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ArgumentList (,$script:UCMTargets) -ScriptBlock {
            param($Targets)
            foreach ($t in $Targets) {
                $full = "Registry::$($t.Hive)\$($t.Path)"; $exists=$false; $val=$null
                if ([string]::IsNullOrWhiteSpace($t.Name)) { $exists = Test-Path -LiteralPath $full }
                else { try { $val = Get-ItemPropertyValue -LiteralPath $full -Name $t.Name -ErrorAction Stop; $exists=$true } catch { $exists=$false } }
                [pscustomobject]@{ Index=$t.Index; Label=$t.Label; Exists=$exists; Value=$val }
            }
        }
        foreach ($r in $data) { Write-ADTLogEntry -Message ("READ [{0}] {1} Exists={2} Value={3}" -f $r.Index,$r.Label,$r.Exists,$r.Value) -Source 'UCM' }
        [pscustomobject]@{ Success=$true; Message='Read complete'; Items=($data | Sort-Object Index) }
    } catch { [pscustomobject]@{ Success=$false; Message="Read failed: $($_.Exception.Message)"; Items=@() } }
}
function ConvertTo-UCMIndexList {
    param([string]$Selection)
    $valid = $script:UCMTargets.Index
    ($Selection -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $n=0; if ([int]::TryParse($_.Trim(),[ref]$n)) { $n } else { -1 } }) |
        Where-Object { $_ -in $valid } | Sort-Object -Unique
}
function Remove-UCMRegistryData {
    param([string]$ComputerName,[pscredential]$Credential,[int[]]$Indices)
    $chosen = $script:UCMTargets | Where-Object { $_.Index -in $Indices }
    try {
        $res = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ArgumentList (,$chosen) -ScriptBlock {
            param($Targets)
            foreach ($t in $Targets) {
                $full = "Registry::$($t.Hive)\$($t.Path)"; $ok=$false; $msg=''
                try {
                    if ([string]::IsNullOrWhiteSpace($t.Name)) {
                        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop; $ok=$true; $msg='Key deleted' }
                        else { $ok=$true; $msg='Already absent' }
                    } else { Remove-ItemProperty -LiteralPath $full -Name $t.Name -Force -ErrorAction Stop; $ok=$true; $msg='Value deleted' }
                } catch { $ok=$false; $msg=$_.Exception.Message }
                [pscustomobject]@{ Index=$t.Index; Label=$t.Label; Success=$ok; Message=$msg }
            }
        }
        foreach ($r in $res) { Write-ADTLogEntry -Message ("DELETE [{0}] {1} -> {2} ({3})" -f $r.Index,$r.Label,$r.Success,$r.Message) -Severity $(if($r.Success){1}else{3}) -Source 'UCM' }
        $all = ($res | Where-Object { -not $_.Success }).Count -eq 0
        [pscustomobject]@{ Success=$all; Message=$(if($all){'All selected items deleted.'}else{'One or more deletions failed.'}); Results=$res }
    } catch { [pscustomobject]@{ Success=$false; Message="Delete failed: $($_.Exception.Message)"; Results=@() } }
}
function Restart-UCMComputer {
    param([string]$ComputerName,[pscredential]$Credential)
    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            shutdown.exe /r /t 60 /c 'IT maintenance complete. This PC will restart shortly.'
        }
        [pscustomobject]@{ Success=$true; Message="Reboot triggered on $ComputerName." }
    } catch { [pscustomobject]@{ Success=$false; Message="Reboot failed: $($_.Exception.Message)" } }
}

# ---- Shared prompt defaults ----
$UCMBase = @{ Title=$UCMTitle; Subtitle='User Configuration Maintenance'; NoExitOnTimeout=$true }

# ---- State machine ----
$script:UCMCred=$null; $script:UCMDomain=$null; $script:UCMUser=$null; $script:UCMPC=$null; $script:UCMRead=$null
$state='Login'; $retryState=$null

while ($state -and $state -ne 'Exit') {
    switch ($state) {

        'Login' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Willkommen bei UCM.`n`nUser Configuration Maintenance - Profil-Reparatur & Wartungs-Workspace." -ButtonLeftText 'Login' -ButtonRightText 'Cancel'
            $state = if ($r -eq 'Login') { 'Domain' } else { 'Exit' }
        }

        'Domain' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -DefaultValue '1' -Message "Choose Domain Number:`n`n1. Domain 1`n2. Domain 2`n3. Domain 3`n4. Domain 4" -ButtonRightText 'Next'
            $num = Get-UCMInputText $r
            $fqdn = Resolve-UCMDomain $num
            if ($fqdn) { $script:UCMDomain=$fqdn; $state='User' }
            else { $retryState='Domain'; $state='Failed' }
        }

        'User' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Domain: $script:UCMDomain`n`nEnter user name:" -ButtonRightText 'Next'
            $script:UCMUser = Get-UCMInputText $r
            $state = if ([string]::IsNullOrWhiteSpace($script:UCMUser)) { 'Login' } else { 'Password' }
        }

        'Password' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Enter password for $script:UCMUser :" -ButtonRightText 'Login'
            $pw = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($pw)) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Analyzing credentials...'
                $auth = Test-UCMCredential -DomainFqdn $script:UCMDomain -User $script:UCMUser -PlainPw $pw
                Close-ADTInstallationProgress
                if ($auth.Success) {
                    $sec = ConvertTo-SecureString $pw -AsPlainText -Force
                    $upn = if ($script:UCMUser -match '[\\@]') { $script:UCMUser } else { "$script:UCMUser@$script:UCMDomain" }
                    $script:UCMCred = [System.Management.Automation.PSCredential]::new($upn, $sec)
                    $pw=$null; $sec=$null
                    $state='EnterPC'
                } else { $retryState='Password'; $script:UCMFailMsg=$auth.Message; $state='Failed' }
            }
        }

        'EnterPC' {
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message 'Successful. Enter PC Name:' -ButtonLeftText 'Connect' -ButtonRightText 'Cancel'
            $script:UCMPC = Get-UCMInputText $r
            if ([string]::IsNullOrWhiteSpace($script:UCMPC)) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage "Connecting to $script:UCMPC ..."
                $conn = Test-UCMConnection -ComputerName $script:UCMPC -Credential $script:UCMCred
                Close-ADTInstallationProgress
                if ($conn.Success) { $state='Read' } else { $retryState='EnterPC'; $script:UCMFailMsg=$conn.Message; $state='Failed' }
            }
        }

        'Read' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Connected to $script:UCMPC.`n`nRead the registry keys?" -ButtonLeftText 'Read' -ButtonRightText 'Cancel'
            if ($r -eq 'Read') {
                Show-ADTInstallationProgress -StatusMessage 'Reading registry...'
                $script:UCMRead = Get-UCMRegistryData -ComputerName $script:UCMPC -Credential $script:UCMCred
                Close-ADTInstallationProgress
                if ($script:UCMRead.Success) { $state='RegList' } else { $retryState='Read'; $script:UCMFailMsg=$script:UCMRead.Message; $state='Failed' }
            } else { $state='Login' }
        }

        'RegList' {
            $list = ($script:UCMRead.Items | ForEach-Object { "{0}. {1} = {2}" -f $_.Index, $_.Label, $(if($_.Exists){'[present]'}else{'[absent]'}) }) -join "`n"
            $r = Show-ADTInstallationPrompt @UCMBase -RequestInput -Message "Read successful:`n`n$list`n`nSelect the numbers to delete (e.g. 2,4,5):" -ButtonLeftText 'Delete' -ButtonRightText 'Cancel'
            $sel = Get-UCMInputText $r
            $idx = ConvertTo-UCMIndexList $sel
            if (-not $idx) { $state='Login' }
            else {
                Show-ADTInstallationProgress -StatusMessage 'Deleting selected keys...'
                $del = Remove-UCMRegistryData -ComputerName $script:UCMPC -Credential $script:UCMCred -Indices $idx
                Close-ADTInstallationProgress
                if ($del.Success) { $state='Reboot' } else { $retryState='RegList'; $script:UCMFailMsg=$del.Message; $state='Failed' }
            }
        }

        'Reboot' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message 'Successful. Trigger reboot?' -ButtonLeftText 'Reboot' -ButtonRightText 'Close'
            if ($r -eq 'Reboot') {
                $rb = Restart-UCMComputer -ComputerName $script:UCMPC -Credential $script:UCMCred
                if ($rb.Success) { $state='Done' } else { $retryState='Reboot'; $script:UCMFailMsg=$rb.Message; $state='Failed' }
            } else { $state='Done' }
        }

        'Done' {
            $r = Show-ADTInstallationPrompt @UCMBase -Message "Maintenance successful for PC {$script:UCMPC}." -ButtonLeftText 'Start New' -ButtonRightText 'Close'
            $state = if ($r -eq 'Start New') { 'EnterPC' } else { 'Exit' }
        }

        'Failed' {
            $msg = if ($script:UCMFailMsg) { "Failed:`n`n$script:UCMFailMsg" } else { 'Failed.' }
            $r = Show-ADTInstallationPrompt @UCMBase -Message $msg -ButtonLeftText 'Try Again' -ButtonRightText 'Cancel'
            $script:UCMFailMsg=$null
            $state = if ($r -eq 'Try Again') { $retryState } else { 'Login' }
        }
    }
}
