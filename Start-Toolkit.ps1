<#
.SYNOPSIS
    Enterprise Admin Toolkit - Main Entry Point (v1.0 - Network Troubleshooting)

.DESCRIPTION
    Console menu that dot-sources Logging.ps1 and imports the Network module.
    This file is intentionally "dumb" - it just presents a menu and calls
    functions from the modules. All real logic lives in Modules\*.psm1, so
    when v5.0 adds a WPF GUI, that GUI can call the exact same functions
    without any logic duplication.

.NOTES
    Run as Administrator to use actions that modify network configuration
    (Reset-IPAddress, Reset-WinsockCatalog, Reset-TCPIPStack).
#>

# --- Bootstrap: resolve paths relative to this script, not the caller's CWD ---
$RootPath = Split-Path -Path $PSScriptRoot -Parent

. (Join-Path $PSScriptRoot "Logging.ps1")
Import-Module (Join-Path $RootPath "Modules\Network\NetworkTools.psm1") -Force

function Show-MainMenu {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "   ENTERPRISE ADMIN TOOLKIT - v1.0 (Network)" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    $adminStatus = if (Test-IsAdmin) { "Yes" } else { "No (some actions disabled)" }
    Write-Host " Running as Administrator: $adminStatus`n"

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
    Write-Host " 0.  Exit"
    Write-Host "==================================================" -ForegroundColor Cyan
}

function Start-ToolkitLoop {
    do {
        Show-MainMenu
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
            "0"  { Write-ToolkitLog -Message "Toolkit session ended by user" -Level INFO -Module Core }
            default { Write-Warning "Invalid option." }
        }

        if ($choice -ne "0") {
            Write-Host "`nPress Enter to continue..." -ForegroundColor DarkGray
            Read-Host | Out-Null
        }
    } while ($choice -ne "0")
}

Write-ToolkitLog -Message "Toolkit session started" -Level INFO -Module Core
Start-ToolkitLoop
