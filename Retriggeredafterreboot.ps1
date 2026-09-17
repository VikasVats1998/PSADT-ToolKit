#=========================================================
# Retrigger-PendingApps.ps1
# Auto-clicks "Try again" for PSADT apps not yet fully
# installed. Runs at startup (+5 min) as SYSTEM.
#=========================================================

$base    = 'HKLM:\SOFTWARE\TechKalu\Packaging\Stages'
$logDir  = 'C:\ProgramData\TechKalu\Logs'
$logFile = Join-Path $logDir 'Retrigger-PendingApps.log'

# --- simple logger ---
if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory -Force | Out-Null }
function Write-Log ($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File $logFile -Append -Encoding UTF8
}

Write-Log "===== Retrigger run started ====="

# --- Step 1: find PSADT apps still incomplete (Current < Final) ---
$pendingApps = @()
if (Test-Path $base) {
    Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p -and ($p.CurrentInstallLevel -lt $p.FinalInstallLevel)) {
            $pendingApps += $p.AppName
            Write-Log "Pending: $($p.AppName)  (Level $($p.CurrentInstallLevel)/$($p.FinalInstallLevel))"
        }
    }
}

if (-not $pendingApps) {
    Write-Log "No pending apps. Nothing to do. Exiting."
    Write-Log "===== Retrigger run finished ====="
    return
}

# --- Step 2: match against Software Center apps not yet Installed ---
try {
    $scApps = Get-CimInstance -Namespace 'root\ccm\clientSDK' -ClassName CCM_Application -ErrorAction Stop |
              Where-Object { $_.Name -in $pendingApps -and $_.InstallState -ne 'Installed' }
}
catch {
    Write-Log "ERROR querying CCM_Application: $($_.Exception.Message)"
    Write-Log "===== Retrigger run finished ====="
    return
}

if (-not $scApps) {
    Write-Log "Pending apps found in registry, but none are retriggerable in Software Center right now."
    Write-Log "===== Retrigger run finished ====="
    return
}

# --- Step 3: auto-click "Try again" (Install) on each ---
foreach ($a in $scApps) {
    try {
        $args = @{
            EnforcePreference = [uint32]0      # Immediate
            Id                = $a.Id
            IsMachineTarget   = $a.IsMachineTarget
            IsRebootIfNeeded  = $false
            Priority          = 'High'
            Revision          = $a.Revision
        }
        Invoke-CimMethod -Namespace 'root\ccm\clientSDK' -ClassName CCM_Application `
            -MethodName Install -Arguments $args -ErrorAction Stop | Out-Null
        Write-Log "Triggered install (Try again) for: $($a.Name)  [State was: $($a.InstallState)]"
    }
    catch {
        Write-Log "ERROR triggering $($a.Name): $($_.Exception.Message)"
    }
}

Write-Log "===== Retrigger run finished ====="
