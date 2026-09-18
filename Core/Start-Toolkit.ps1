<#
.SYNOPSIS
    Enterprise Admin Toolkit - Main Entry Point (v2.0)

.DESCRIPTION
    Console menu that dot-sources Core\*.ps1 and imports available modules.
    This file is intentionally "dumb" - it just presents menus and calls
    functions from the modules. All real logic lives in Modules\*.psm1, so
    when v5.0 adds a WPF GUI, that GUI can call the exact same functions
    without any logic duplication.

    v2.0 restructures the single flat menu into a category menu (Network /
    Active Directory / System Administration), since a flat list stops
    scaling past one module.

.NOTES
    Run as Administrator to use actions that modify network configuration.
    ActiveDirectory menu requires RSAT-AD-PowerShell and a domain-joined
    machine - the toolkit detects this and disables that menu if unavailable.
#>

# --- Bootstrap: resolve paths relative to this script, not the caller's CWD ---
$RootPath = Split-Path -Path $PSScriptRoot -Parent

# Logging and Prerequisites must be Import-Module'd, not dot-sourced. Dot-sourcing
# only makes functions visible in THIS script's own scope - it does not share them
# with other modules (NetworkTools.psm1, ADTools.psm1, SystemTools.psm1) which run
# in their own isolated module scope. Import-Module registers functions globally
# in the session, so every other module can call Write-ToolkitLog / Test-IsAdmin /
# Test-ADModuleAvailable regardless of which file defines them.
Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Prerequisites.psm1") -Force

Import-Module (Join-Path $RootPath "Modules\Network\NetworkTools.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\System\SystemTools.psm1") -Force

$Script:ADAvailable = Test-ADModuleAvailable
if ($Script:ADAvailable) {
    Import-Module ActiveDirectory -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $RootPath "Modules\ActiveDirectory\ADTools.psm1") -Force
}

# ============================================================
#  MAIN MENU
# ============================================================
function Show-MainMenu {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        ENTERPRISE ADMIN TOOLKIT - v2.0" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    $adminStatus = if (Test-IsAdmin) { "Yes" } else { "No (some actions disabled)" }
    Write-Host " Running as Administrator : $adminStatus"
    $adStatus = if ($Script:ADAvailable) { "Available" } else { "Not available (RSAT missing)" }
    Write-Host " Active Directory module  : $adStatus`n"

    Write-Host " 1. Network Troubleshooting"
    Write-Host " 2. Active Directory$(if (-not $Script:ADAvailable) { '  [Unavailable]' })"
    Write-Host " 3. System Administration"
    Write-Host " 0. Exit"
    Write-Host "==================================================" -ForegroundColor Cyan
}

# ============================================================
#  NETWORK SUBMENU (v1.0)
# ============================================================
function Show-NetworkMenu {
    Clear-Host
    Write-Host "---------------- NETWORK TROUBLESHOOTING ----------------" -ForegroundColor Cyan
    Write-Host " 1.  Display Full IP Configuration"
    Write-Host " 2.  Test Internet Connectivity"
    Write-Host " 3.  Ping a Custom Host"
    Write-Host " 4.  Traceroute"
    Write-Host " 5.  Flush DNS Cache"
    Write-Host " 6.  Release/Renew IP Address           [Admin]"
    Write-Host " 7.  Reset Winsock                       [Admin]"
    Write-Host " 8.  Reset TCP/IP Stack                  [Admin]"
    Write-Host " 9.  Open Device Manager"
    Write-Host " 10. Open Network Settings"
    Write-Host " 11. Open Network Troubleshooter"
    Write-Host " 12. DNS Resolution Test"
    Write-Host " 13. Port Connectivity Test"
    Write-Host " 14. Extended Ping Statistics (loss/latency/jitter)"
    Write-Host " 15. Restart Windows Explorer             [Confirm]"
    Write-Host " 0.  Back to Main Menu"
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
}

function Start-NetworkLoop {
    do {
        Show-NetworkMenu
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            "1"  { Get-FullIPConfig | Format-Table -AutoSize }
            "2"  { Test-InternetConnectivity | Format-Table -AutoSize }
            "3"  {
                $target = Read-Host "Enter hostname or IP to ping"
                Invoke-CustomPing -TargetHost $target | Format-Table -AutoSize
            }
            "4"  {
                $target = Read-Host "Enter hostname or IP to trace"
                Invoke-CustomTraceroute -TargetHost $target
            }
            "5"  { Clear-DNSCacheCustom | Format-Table -AutoSize }
            "6"  { Reset-IPAddress -Confirm:$false }
            "7"  { Reset-WinsockCatalog -Confirm:$false }
            "8"  { Reset-TCPIPStack -Confirm:$false }
            "9"  { Open-DeviceManagerTool }
            "10" { Open-NetworkSettingsTool }
            "11" { Open-NetworkTroubleshooterTool }
            "12" {
                $target = Read-Host "Enter hostname to resolve"
                Test-DNSResolution -TargetHost $target | Format-Table -AutoSize
            }
            "13" {
                $target = Read-Host "Enter hostname or IP"
                $port   = Read-Host "Enter TCP port"
                Test-PortConnectivity -TargetHost $target -Port ([int]$port) | Format-Table -AutoSize
            }
            "14" {
                $target = Read-Host "Enter hostname or IP"
                $count  = Read-Host "Number of packets (default 20, Enter to accept)"
                if ([string]::IsNullOrWhiteSpace($count)) {
                    Get-PingStatistics -TargetHost $target | Format-List
                } else {
                    Get-PingStatistics -TargetHost $target -Count ([int]$count) | Format-List
                }
            }
            "15" { Restart-ExplorerShell }
            "0"  { }
            default { Write-Warning "Invalid option." }
        }

        if ($choice -ne "0") {
            Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
            Read-Host | Out-Null
        }
    } while ($choice -ne "0")
}

# ============================================================
#  ACTIVE DIRECTORY SUBMENU (v2.0)
# ============================================================
function Show-ADMenu {
    Clear-Host
    Write-Host "---------------- ACTIVE DIRECTORY ----------------" -ForegroundColor Cyan
    Write-Host " 1. Create User"
    Write-Host " 2. Disable User                         [Confirm]"
    Write-Host " 3. Enable User                           [Confirm]"
    Write-Host " 4. Unlock User                           [Confirm]"
    Write-Host " 5. Reset Password                        [Confirm]"
    Write-Host " 6. Add User To Group                     [Confirm]"
    Write-Host " 7. Remove User From Group                [Confirm]"
    Write-Host " 8. List Disabled Users"
    Write-Host " 9. List Locked Users"
    Write-Host " 0. Back to Main Menu"
    Write-Host "-----------------------------------------------------" -ForegroundColor Cyan
}

function Start-ADLoop {
    do {
        Show-ADMenu
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            "1" {
                $given = Read-Host "Given name"
                $sur   = Read-Host "Surname"
                $sam   = Read-Host "SamAccountName (logon name)"
                $ou    = Read-Host "OU distinguished name (Enter to skip, uses default container)"
                if ([string]::IsNullOrWhiteSpace($ou)) {
                    New-ADUserAccount -GivenName $given -Surname $sur -SamAccountName $sam -Confirm:$false | Format-List
                } else {
                    New-ADUserAccount -GivenName $given -Surname $sur -SamAccountName $sam -OUPath $ou -Confirm:$false | Format-List
                }
            }
            "2" {
                $sam = Read-Host "SamAccountName to disable"
                Disable-ADUserAccount -SamAccountName $sam -Confirm:$false | Format-List
            }
            "3" {
                $sam = Read-Host "SamAccountName to enable"
                Enable-ADUserAccount -SamAccountName $sam -Confirm:$false | Format-List
            }
            "4" {
                $sam = Read-Host "SamAccountName to unlock"
                Unlock-ADUserAccount -SamAccountName $sam -Confirm:$false | Format-List
            }
            "5" {
                $sam = Read-Host "SamAccountName"
                Reset-ADUserPassword -SamAccountName $sam -Confirm:$false | Format-List
            }
            "6" {
                $sam   = Read-Host "SamAccountName"
                $group = Read-Host "Group name"
                Add-ADUserToGroupCustom -SamAccountName $sam -GroupName $group -Confirm:$false | Format-List
            }
            "7" {
                $sam   = Read-Host "SamAccountName"
                $group = Read-Host "Group name"
                Remove-ADUserFromGroupCustom -SamAccountName $sam -GroupName $group -Confirm:$false | Format-List
            }
            "8" { Get-DisabledADUsers | Format-Table -AutoSize }
            "9" { Get-LockedADUsers | Format-Table -AutoSize }
            "0" { }
            default { Write-Warning "Invalid option." }
        }

        if ($choice -ne "0") {
            Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
            Read-Host | Out-Null
        }
    } while ($choice -ne "0")
}

# ============================================================
#  SYSTEM ADMINISTRATION SUBMENU (v2.0)
# ============================================================
function Show-SystemMenu {
    Clear-Host
    Write-Host "---------------- SYSTEM ADMINISTRATION ----------------" -ForegroundColor Cyan
    Write-Host " 1. Check Disk Usage"
    Write-Host " 2. Restart a Service                     [Confirm]"
    Write-Host " 3. View Running Services"
    Write-Host " 4. Installed Software Report"
    Write-Host " 5. System Information Report"
    Write-Host " 0. Back to Main Menu"
    Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
}

function Start-SystemLoop {
    do {
        Show-SystemMenu
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            "1" { Get-DiskUsageReport | Format-Table -AutoSize }
            "2" {
                $svc = Read-Host "Service name (e.g. Spooler)"
                Restart-ServiceCustom -ServiceName $svc -Confirm:$false | Format-List
            }
            "3" { Get-RunningServicesReport | Format-Table -AutoSize }
            "4" { Get-InstalledSoftwareReport | Format-Table -AutoSize }
            "5" { Get-SystemInfoReport | Format-List }
            "0" { }
            default { Write-Warning "Invalid option." }
        }

        if ($choice -ne "0") {
            Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
            Read-Host | Out-Null
        }
    } while ($choice -ne "0")
}

# ============================================================
#  MAIN LOOP
# ============================================================
function Start-ToolkitLoop {
    do {
        Show-MainMenu
        $choice = Read-Host "`nSelect a category"

        switch ($choice) {
            "1" { Start-NetworkLoop }
            "2" {
                if ($Script:ADAvailable) {
                    Start-ADLoop
                } else {
                    Write-Warning "ActiveDirectory module not available. Install RSAT-AD-PowerShell and relaunch."
                    Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
                    Read-Host | Out-Null
                }
            }
            "3" { Start-SystemLoop }
            "0" { Write-ToolkitLog -Message "Toolkit session ended by user" -Level INFO -Module Core }
            default { Write-Warning "Invalid option." }
        }
    } while ($choice -ne "0")
}

Write-ToolkitLog -Message "Toolkit session started" -Level INFO -Module Core
Start-ToolkitLoop
