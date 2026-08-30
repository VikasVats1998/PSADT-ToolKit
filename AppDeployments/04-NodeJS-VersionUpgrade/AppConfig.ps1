<#
App-specific configuration for: Node.js (version-upgrade scenario). Nothing
in here is PSADT logic — only values. DependencyUpdateLogic.ps1 (generic,
do not edit per app) reads these.
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
    AppProcessesToClose = @()   # do not set this; use $DependentApps below instead
    RequireAdmin        = $true

    InstallName  = 'NodeJSUpgrade'
    InstallTitle = 'Node.js Version Upgrade'
    LogName      = 'NodeJSUpgrade.log'
}

$InstallerFile = 'node-v24.14.1-x64.msi'
$InstallerType = 'MSI'   # 'MSI' or 'EXE'
$InstallArgs   = $null   # EXE only; MSI silence comes from Config\config.psd1

# Node.js is a normal MSI app, so detect via Get-ADTApplication.
$DetectionMethod = 'Application'   # 'Registry' or 'Application'
$DetectName      = 'Node.js'
$DetectNameMatch = 'Contains'

# Not used when $DetectionMethod = 'Application', kept here so both packages
# share the same config shape.
$DependencyRegPath = $null
$DependencyRegInstalledValueName = $null
$DependencyRegVersionValueName   = $null

# SIMULATED: there's only one real Node.js MSI available (24.14.1), so
# there's no genuinely newer build to install. This hardcoded value exists
# purely to exercise the version-comparison decision logic — a real
# dependency-update package would read this from a live source (a manifest
# file, a vendor API, your patch-management tool's update feed).
$SimulatedAvailableVersion = '24.15.0'

# Windows has no API for "which apps depend on this" — maintain this list
# from your own app inventory. VS Code is a genuinely plausible real
# dependent (many extensions rely on a Node.js runtime).
$DependentApps = @(
    @{ Name = 'Code'; Description = 'Visual Studio Code (example dependent app)' }
    @{ Name = 'notepad'; Description = 'Notepad (example dependent app)' }
)

# Forces the full flow to run for practice even if the version comparison
# says no update is due. Set to $false to see the realistic "already up to
# date" behavior instead.
$ForcePracticeRun = $true

$SupportsUninstall = $true
