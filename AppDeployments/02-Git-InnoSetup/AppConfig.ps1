<#
App-specific configuration for: Git for Windows. Nothing in here is PSADT
logic — only values. InstallLogic.ps1 (generic, do not edit per app) reads
these.
#>

$adtSession = @{
    AppVendor         = 'Git for Windows'
    AppName           = 'Git'
    AppVersion        = '2.45.2'
    AppArch           = 'x64'
    AppLang           = 'EN'
    AppRevision       = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes  = @(1641, 3010)
    AppProcessesToClose = @()   # do not set this; use $ProcessToWatch below instead
    RequireAdmin        = $true

    InstallName  = 'Git'
    InstallTitle = 'Git for Windows 2.45.2'
    LogName      = 'Git.log'
}

$InstallerFile   = 'Git-2.45.2-64-bit.exe'
$InstallerType   = 'EXE'          # 'MSI' or 'EXE'
# Confirmed via binary signature scan: this installer is built with Inno Setup.
$InstallArgs     = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-'
$DetectName      = 'Git'
$DetectNameMatch = 'Contains'     # Inno's default DisplayName is "Git version 2.45.2" — verify and tighten to Exact if needed
$ProcessToWatch  = @{ Name = 'git-bash'; Description = 'Git Bash' }
$BlockExecution  = $false
