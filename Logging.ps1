<#
.SYNOPSIS
    Centralized logging for the Enterprise Admin Toolkit.

.DESCRIPTION
    Every module dot-sources this file and calls Write-ToolkitLog instead of
    Write-Host, so every action taken by the toolkit (network reset, AD change,
    security query...) leaves an audit trail in Logs\toolkit.log.

    This matters for two reasons beyond convenience:
      1. Traceability  - if a destructive action (Disable-User, Reset-TCPIP...)
         causes an incident, you need to know who ran what, when.
      2. Portfolio value - a real logging strategy is one of the first things
         a reviewer looks for when they open an "admin toolkit" repo.
#>

$Script:LogPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Logs\toolkit.log"

function Write-ToolkitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",

        [Parameter()]
        [string]$Module = "Core"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $user      = $env:USERNAME
    $logLine   = "[$timestamp] [$Level] [$Module] [$user] $Message"

    # Write to file - never let a logging failure crash the toolkit
    try {
        $logDir = Split-Path -Path $Script:LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $Script:LogPath -Value $logLine -ErrorAction Stop
    }
    catch {
        # Fall back to console only - logging must never break the calling function
        Write-Warning "Could not write to log file: $($_.Exception.Message)"
    }

    # Also echo to console with color coding, so the operator gets live feedback
    switch ($Level) {
        "INFO"    { Write-Host $logLine -ForegroundColor Gray }
        "WARN"    { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logLine -ForegroundColor Red }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if the current PowerShell session is running elevated.
    .DESCRIPTION
        Several v1.0 actions (Reset-Winsock, Reset-TCPIP, Release/Renew IP)
        require local admin rights. Rather than let them fail with a cryptic
        access-denied error, we check up front and warn clearly.
    #>
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
