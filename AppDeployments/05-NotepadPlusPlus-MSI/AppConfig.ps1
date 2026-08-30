<#
App-specific configuration for: Notepad++ (MSI build). Nothing in here is
PSADT logic — only values. InstallLogic.ps1 (generic, do not edit per app)
reads these.
#>

$adtSession = @{
    AppVendor         = 'Notepad++ team (MSI installer)'
    AppName           = 'Notepad++'
    AppVersion        = '8.9.8'
    AppArch           = 'x64'
    AppLang           = 'EN'
    AppRevision       = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes  = @(1641, 3010)
    AppProcessesToClose = @()   # do not set this; use $ProcessToWatch below instead
    RequireAdmin        = $true

    InstallName  = 'NotepadPlusPlusMSI'
    InstallTitle = 'Notepad++ 8.9.8 (MSI)'
    LogName      = 'NotepadPlusPlus-MSI.log'
}

$InstallerFile   = 'npp.8.9.8.Installer.x64.msi'
$InstallerType   = 'MSI'          # 'MSI' or 'EXE'
$InstallArgs     = $null          # EXE only; MSI silence comes from Config\config.psd1
$DetectName      = 'Notepad++'
$DetectNameMatch = 'Contains'     # Contains | Exact | Wildcard | Regex
$ProcessToWatch  = @{ Name = 'notepad++'; Description = 'Notepad++' }
$BlockExecution  = $true
