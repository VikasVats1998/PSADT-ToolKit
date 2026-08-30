<#
App-specific configuration for: Visual Studio Code. Nothing in here is
PSADT logic — only values. InstallLogic.ps1 (generic, do not edit per app)
reads these.
#>

$adtSession = @{
    AppVendor         = 'Microsoft Corporation'
    AppName           = 'Visual Studio Code'
    AppVersion        = '1.114.0'
    AppArch           = 'x64'
    AppLang           = 'EN'
    AppRevision       = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes  = @(1641, 3010)
    AppProcessesToClose = @()   # do not set this; use $ProcessToWatch below instead
    RequireAdmin        = $true

    InstallName  = 'VSCode'
    InstallTitle = 'Visual Studio Code 1.114.0'
    LogName      = 'VSCode.log'
}

$InstallerFile   = 'VSCodeUserSetup-x64-1.114.0.exe'
$InstallerType   = 'EXE'          # 'MSI' or 'EXE'
# Confirmed via binary signature scan: this installer is built with Inno Setup.
$InstallArgs     = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-'
$DetectName      = 'Visual Studio Code'
$DetectNameMatch = 'Contains'     # Contains | Exact | Wildcard | Regex
$ProcessToWatch  = @{ Name = 'Code'; Description = 'Visual Studio Code' }
$BlockExecution  = $true
