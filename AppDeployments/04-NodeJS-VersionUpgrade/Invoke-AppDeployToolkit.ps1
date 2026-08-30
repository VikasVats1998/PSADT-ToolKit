<#

.SYNOPSIS
Node.js — PSADT dependency version-upgrade.

.DESCRIPTION
This launcher stays close to the stock PSADT template. Per-app values are
in AppConfig.ps1; the shared-dependency update logic is in
DependencyUpdateLogic.ps1 (generic, not app-specific). Both are dot-sourced
below. See README.md for test instructions.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Interactive (shows dialogs), Silent (no dialogs), NonInteractive, or Auto.

.EXAMPLE
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

.EXAMPLE
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Interactive

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# AppConfig.ps1 = what changes per app (edit this for a new app).
# DependencyUpdateLogic.ps1 = the standard dependency-update pattern (generic).
. "$PSScriptRoot\AppConfig.ps1"
. "$PSScriptRoot\DependencyUpdateLogic.ps1"

# Script-invocation metadata can only be resolved here (not inside the
# dot-sourced files), so it's appended to $adtSession after dot-sourcing.
$adtSession.AppScriptVersion         = '1.0.0'
$adtSession.AppScriptDate            = '2026-08-29'
$adtSession.AppScriptAuthor          = '<author name>'
$adtSession.DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
$adtSession.DeployAppScriptParameters   = $PSBoundParameters
$adtSession.DeployAppScriptVersion      = '4.1.8'


##================================================
## MARK: Initialization
##================================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

try
{
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

try
{
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3
    Close-ADTSession -ExitCode 60001
}
