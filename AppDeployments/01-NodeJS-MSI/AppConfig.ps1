<#
App-specific configuration for: Node.js. Nothing in here is PSADT logic —
only values. InstallLogic.ps1 (generic, do not edit per app) reads these.
#>

$adtSession = @{
    AppVendor         = 'OpenJS Foundation'
    AppName           = 'Node.js'
    AppVersion        = '24.14.1'
    AppArch           = 'x64'
    AppLang           = 'EN'
    AppRevision       = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes  = @(1641, 3010)
    AppProcessesToClose = @()   # do not set this; use $ProcessToWatch below instead
    RequireAdmin        = $true

    InstallName  = 'NodeJS'
    InstallTitle = 'Node.js 24.14.1'
    LogName      = 'NodeJS.log'
}

$InstallerFile   = 'node-v24.14.1-x64.msi'
$InstallerType   = 'MSI'          # 'MSI' or 'EXE'
$InstallArgs     = $null          # EXE only; MSI silence comes from Config\config.psd1
$DetectName      = 'Node.js'
$DetectNameMatch = 'Contains'     # Contains | Exact | Wildcard | Regex
$ProcessToWatch  = $null          # $null, or @{ Name = '...'; Description = '...' }
$BlockExecution  = $false
