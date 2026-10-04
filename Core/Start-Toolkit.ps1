<#
.SYNOPSIS
    Enterprise Admin Toolkit - Main Entry Point (v4.0)
#>

$RootPath = Split-Path -Path $PSScriptRoot -Parent

Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Prerequisites.psm1") -Force

Import-Module (Join-Path $RootPath "Modules\Network\NetworkTools.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\System\SystemTools.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Security\EventLogMonitoring.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Security\SecurityAuditing.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Security\IncidentResponse.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Monitoring\HealthMonitoring.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Monitoring\InfrastructureMonitoring.psm1") -Force
Import-Module (Join-Path $RootPath "Modules\Reports\ReportGeneration.psm1") -Force

$Script:ADAvailable = Test-ADModuleAvailable
if ($Script:ADAvailable) {
    Import-Module ActiveDirectory -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $RootPath "Modules\ActiveDirectory\ADTools.psm1") -Force
}

function Show-MainMenu {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "        ENTERPRISE ADMIN TOOLKIT - v4.0" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    $adminStatus = if (Test-IsAdmin) { "Yes" } else { "No (some actions disabled)" }
    Write-Host " Running as Administrator : $adminStatus"
    $adStatus = if ($Script:ADAvailable) { "Available" } else { "Not available (RSAT missing)" }
    Write-Host " Active Directory module  : $adStatus"
    if (-not (Test-IsAdmin)) {
        Write-Host " Note: Security log requires elevation - relaunch as Administrator for Security Operations`n" -ForegroundColor DarkYellow
    } else {
        Write-Host ""
    }

    Write-Host " 1. Network Troubleshooting"
    Write-Host " 2. Active Directory$(if (-not $Script:ADAvailable) { '  [Unavailable]' })"
    Write-Host " 3. System Administration"
    Write-Host " 4. Security Operations$(if (-not (Test-IsAdmin)) { '  [Needs Admin]' })"
    Write-Host " 5. Monitoring & Reporting"
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
#  SECURITY OPERATIONS SUBMENU (v3.0)
# ============================================================
function Show-SecurityMenu {
    Clear-Host
    Write-Host "---------------- SECURITY OPERATIONS ----------------" -ForegroundColor Cyan
    Write-Host " -- Event Log Monitoring --"
    Write-Host " 1.  Failed Logons (4625)"
    Write-Host " 2.  Successful Logons (4624)"
    Write-Host " 3.  Privileged Logons (4672)"
    Write-Host " 4.  User Creation Events (4720)"
    Write-Host " 5.  User Deletion Events (4726)"
    Write-Host " 6.  Group Membership Changes (4728/4729/4732/4733)"
    Write-Host " -- Security Auditing --"
    Write-Host " 7.  Domain Admin Audit                  [AD]"
    Write-Host " 8.  Account Lockout Audit                [AD]"
    Write-Host " 9.  Disabled Accounts Report             [AD]"
    Write-Host " 10. Password Policy Review               [AD]"
    Write-Host " 11. Local Administrators Audit"
    Write-Host " -- Incident Response --"
    Write-Host " 12. Search Event Logs"
    Write-Host " 13. Investigate User Activity"
    Write-Host " 14. Generate Security Timeline"
    Write-Host " 0.  Back to Main Menu"
    Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
}

function Start-SecurityLoop {
    do {
        Show-SecurityMenu
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            "1" {
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-FailedLogonEvents -Hours $hours | Format-Table -AutoSize -Property TimeCreated, TargetUserName, WorkstationName, IpAddress, FailureReason
            }
            "2" {
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-SuccessfulLogonEvents -Hours $hours | Format-Table -AutoSize -Property TimeCreated, TargetUserName, WorkstationName, IpAddress
            }
            "3" {
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-PrivilegedLogonEvents -Hours $hours | Format-Table -AutoSize -Property TimeCreated, SubjectUserName, PrivilegeList
            }
            "4" {
                if (-not $Script:ADAvailable) { Write-Warning "Requires AD module / run against a Domain Controller for meaningful results." }
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-UserCreationEvents -Hours $hours | Format-Table -AutoSize
            }
            "5" {
                if (-not $Script:ADAvailable) { Write-Warning "Requires AD module / run against a Domain Controller for meaningful results." }
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-UserDeletionEvents -Hours $hours | Format-Table -AutoSize
            }
            "6" {
                if (-not $Script:ADAvailable) { Write-Warning "Requires AD module / run against a Domain Controller for meaningful results." }
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-GroupMembershipChangeEvents -Hours $hours | Format-Table -AutoSize
            }
            "7" {
                if ($Script:ADAvailable) { Get-DomainAdminAudit | Format-Table -AutoSize } else { Write-Warning "Requires ActiveDirectory module (RSAT)." }
            }
            "8" {
                if ($Script:ADAvailable) { Get-AccountLockoutAudit | Format-Table -AutoSize } else { Write-Warning "Requires ActiveDirectory module (RSAT)." }
            }
            "9" {
                if ($Script:ADAvailable) { Get-DisabledAccountsReport | Format-Table -AutoSize } else { Write-Warning "Requires ActiveDirectory module (RSAT)." }
            }
            "10" {
                if ($Script:ADAvailable) { Get-PasswordPolicyReview | Format-List } else { Write-Warning "Requires ActiveDirectory module (RSAT)." }
            }
            "11" { Get-LocalAdministratorsAudit | Format-Table -AutoSize }
            "12" {
                $kw = Read-Host "Keyword to search for (Enter to skip)"
                $h  = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                if ([string]::IsNullOrWhiteSpace($kw)) {
                    Search-SecurityEventLogs -Hours $hours | Format-Table -AutoSize
                } else {
                    Search-SecurityEventLogs -Keyword $kw -Hours $hours | Format-Table -AutoSize
                }
            }
            "13" {
                $user = Read-Host "Username (SamAccountName) to investigate"
                $h    = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                Get-UserActivityInvestigation -UserName $user -Hours $hours | Format-Table -AutoSize
            }
            "14" {
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                New-SecurityTimeline -Hours $hours | Format-Table -AutoSize
            }
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
#  MONITORING & REPORTING SUBMENU (v4.0)
# ============================================================
function Show-MonitoringMenu {
    Clear-Host
    Write-Host "---------------- MONITORING & REPORTING ----------------" -ForegroundColor Cyan
    Write-Host " -- Health Monitoring --"
    Write-Host " 1.  CPU Utilization"
    Write-Host " 2.  Memory Usage"
    Write-Host " 3.  Disk Usage (remote-capable)"
    Write-Host " 4.  Uptime"
    Write-Host " 5.  Service Health Check"
    Write-Host " 6.  Network Connectivity Health"
    Write-Host " -- Infrastructure Monitoring --"
    Write-Host " 7.  Windows Server Monitoring (consolidated)"
    Write-Host " 8.  Linux Server Monitoring (SSH)        [Posh-SSH]"
    Write-Host " 9.  Process Monitoring"
    Write-Host " 10. Critical Service Sweep"
    Write-Host " -- Reporting --"
    Write-Host " 11. Daily Health Report"
    Write-Host " 12. Security Report"
    Write-Host " 13. Server Audit Report"
    Write-Host " 14. Generate HTML Dashboard"
    Write-Host " 0.  Back to Main Menu"
    Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
}

function Start-MonitoringLoop {
    do {
        Show-MonitoringMenu
        $choice = Read-Host "`nSelect an option"

        switch ($choice) {
            "1" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-CPUUtilization | Format-List } else { Get-CPUUtilization -ComputerName $cn | Format-List }
            }
            "2" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-MemoryUsage | Format-List } else { Get-MemoryUsage -ComputerName $cn | Format-List }
            }
            "3" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-RemoteDiskUsage | Format-Table -AutoSize } else { Get-RemoteDiskUsage -ComputerName $cn | Format-Table -AutoSize }
            }
            "4" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-UptimeStatus | Format-List } else { Get-UptimeStatus -ComputerName $cn | Format-List }
            }
            "5" {
                $svc = Read-Host "Service name(s), comma-separated (e.g. Spooler,WinDefend)"
                $cn  = Read-Host "Computer name (Enter for local machine)"
                $names = $svc -split "," | ForEach-Object { $_.Trim() }
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-ServiceHealthCheck -ServiceName $names | Format-Table -AutoSize } else { Get-ServiceHealthCheck -ServiceName $names -ComputerName $cn | Format-Table -AutoSize }
            }
            "6" {
                $cn = Read-Host "Computer name to check"
                Test-NetworkConnectivityHealth -ComputerName $cn | Format-Table -AutoSize
            }
            "7" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-WindowsServerHealth | Format-List } else { Get-WindowsServerHealth -ComputerName $cn | Format-List }
            }
            "8" {
                $hn   = Read-Host "Linux hostname/IP"
                $cred = Get-Credential -Message "SSH credential for $hn"
                Get-LinuxServerHealth -HostName $hn -Credential $cred | Format-List
            }
            "9" {
                $sortOpt = Read-Host "Sort by CPU or Memory (default CPU, Enter to accept)"
                $sort = if ([string]::IsNullOrWhiteSpace($sortOpt)) { "CPU" } else { $sortOpt }
                Get-ProcessMonitor -SortBy $sort | Format-Table -AutoSize
            }
            "10" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { Get-CriticalServiceStatus | Format-Table -AutoSize } else { Get-CriticalServiceStatus -ComputerName $cn | Format-Table -AutoSize }
            }
            "11" {
                $cn = Read-Host "Computer name (Enter for local machine)"
                if ([string]::IsNullOrWhiteSpace($cn)) { New-DailyHealthReport | Format-List } else { New-DailyHealthReport -ComputerName $cn | Format-List }
            }
            "12" {
                $h = Read-Host "Lookback window in hours (default 24, Enter to accept)"
                $hours = if ([string]::IsNullOrWhiteSpace($h)) { 24 } else { [int]$h }
                New-SecurityReportSummary -Hours $hours | Format-List
            }
            "13" { New-ServerAuditReport | Format-List }
            "14" {
                $path = Read-Host "Output path (Enter for default: Documentation\dashboard.html)"
                if ([string]::IsNullOrWhiteSpace($path)) { New-HTMLDashboard | Format-List } else { New-HTMLDashboard -OutputPath $path | Format-List }
            }
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
            "4" {
                if (Test-IsAdmin) {
                    Start-SecurityLoop
                } else {
                    Write-Warning "Security log requires Administrator privileges. Relaunch PowerShell as Administrator."
                    Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
                    Read-Host | Out-Null
                }
            }
            "5" { Start-MonitoringLoop }
            "0" { Write-ToolkitLog -Message "Toolkit session ended by user" -Level INFO -Module Core }
            default { Write-Warning "Invalid option." }
        }
    } while ($choice -ne "0")
}

Write-ToolkitLog -Message "Toolkit session started" -Level INFO -Module Core
Start-ToolkitLoop
