<#
App-specific configuration for: .NET Framework 3.5. Nothing in here is
PSADT logic — only values. DependencyUpdateLogic.ps1 (generic, do not edit
per app) reads these.
#>

$adtSession = @{
    AppVendor         = 'Microsoft Corporation'
    AppName           = '.NET Framework 3.5'
    AppVersion        = '3.5.1'
    AppArch           = 'x86'
    AppLang           = 'EN'
    AppRevision       = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes  = @(1641, 3010)
    AppProcessesToClose = @()   # do not set this; use $DependentApps below instead
    RequireAdmin        = $true

    InstallName  = 'DotNetFx35'
    InstallTitle = '.NET Framework 3.5 Dependency Update'
    LogName      = 'DotNetFx35.log'
}

$InstallerFile = 'dotNetFx35setup.exe'
$InstallerType = 'EXE'            # 'MSI' or 'EXE'
$InstallArgs   = '/q /norestart'  # Microsoft's own documented silent-install switches

# .NET Framework 3.5 is a Windows feature, not a normal MSI app — it never
# creates an Add/Remove Programs entry, so detect via the registry instead.
$DetectionMethod              = 'Registry'   # 'Registry' or 'Application'
$DependencyRegPath            = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5'
$DependencyRegInstalledValueName = 'Install'
$DependencyRegVersionValueName   = 'Version'

# Not used when $DetectionMethod = 'Registry', kept here so both packages
# share the same config shape.
$DetectName      = $null
$DetectNameMatch = $null
$SimulatedAvailableVersion = $null

# Windows has no API for "which apps depend on this" — maintain this list
# from your own app inventory / vendor documentation. Notepad and Notepad++
# are stand-ins you can actually open to test the close-prompt against.
$DependentApps = @(
    @{ Name = 'notepad'; Description = 'Notepad (example dependent app)' }
    @{ Name = 'notepad++'; Description = 'Notepad++ (example dependent app)' }
)

# .NET Framework 3.5 is already installed on most dev machines, which would
# otherwise make this skip straight to "already satisfied." Forces the full
# flow to run anyway so the UI can actually be exercised; set to $false to
# see the realistic "skip if already satisfied" behavior instead.
$ForcePracticeRun = $true

# .NET Framework 3.5 is a Windows feature — removing it needs DISM
# (Disable-WindowsOptionalFeature), a different and more invasive operation
# that can break other software still relying on it. Not supported here.
$SupportsUninstall = $false
