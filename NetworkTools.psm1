<#
.SYNOPSIS
    Network Troubleshooting Toolkit (v1.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Each function here maps to one feature from the v1.0 roadmap.
    Design principles applied throughout:
      - Functions return PowerShell objects (not just text) so results can
        later be piped into Modules\Reports (v4.0) or bound to a GUI grid (v5.0).
      - Every action is logged via Write-ToolkitLog (audit trail).
      - Actions requiring elevation check Test-IsAdmin first and fail clearly
        instead of throwing a raw access-denied exception.
      - try/catch around every external call (netsh, Test-Connection, etc.)
        so one failed check doesn't crash the whole session.
#>

function Get-FullIPConfig {
    <#
    .SYNOPSIS
        Displays full IP configuration for all active network adapters.
    .EXAMPLE
        Get-FullIPConfig
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Retrieving full IP configuration" -Level INFO -Module Network

        $adapters = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" }

        $result = foreach ($adapter in $adapters) {
            [PSCustomObject]@{
                InterfaceAlias = $adapter.InterfaceAlias
                IPv4Address    = ($adapter.IPv4Address.IPAddress -join ", ")
                IPv4Gateway    = $adapter.IPv4DefaultGateway.NextHop
                DNSServers     = ($adapter.DNSServer.ServerAddresses -join ", ")
                MACAddress     = (Get-NetAdapter -InterfaceAlias $adapter.InterfaceAlias).MacAddress
            }
        }

        Write-ToolkitLog -Message "IP configuration retrieved for $($result.Count) adapter(s)" -Level SUCCESS -Module Network
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to retrieve IP configuration: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
        Tests internet connectivity against reliable, well-known hosts.
    .DESCRIPTION
        Tests both public DNS (1.1.1.1, 8.8.8.8) and DNS resolution, so you can
        immediately tell "no internet" apart from "internet OK, DNS broken" -
        two very different fixes.
    #>
    [CmdletBinding()]
    param()

    $targets = @(
        @{ Name = "Cloudflare DNS"; Target = "1.1.1.1" },
        @{ Name = "Google DNS";     Target = "8.8.8.8" }
    )

    $results = foreach ($t in $targets) {
        try {
            $ping = Test-Connection -ComputerName $t.Target -Count 2 -ErrorAction Stop
            [PSCustomObject]@{
                Target       = "$($t.Name) ($($t.Target))"
                Reachable    = $true
                AvgLatencyMs = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
            }
        }
        catch {
            [PSCustomObject]@{
                Target       = "$($t.Name) ($($t.Target))"
                Reachable    = $false
                AvgLatencyMs = $null
            }
        }
    }

    $allUp = -not ($results.Reachable -contains $false)
    $level = if ($allUp) { "SUCCESS" } else { "WARN" }
    Write-ToolkitLog -Message "Internet connectivity test - Reachable: $allUp" -Level $level -Module Network

    return $results
}

function Invoke-CustomPing {
    <#
    .SYNOPSIS
        Pings a user-specified host.
    .PARAMETER TargetHost
        Hostname or IP address to ping.
    .PARAMETER Count
        Number of pings to send. Default 4.
    .EXAMPLE
        Invoke-CustomPing -TargetHost "google.com" -Count 4
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetHost,

        [Parameter()]
        [int]$Count = 4
    )

    try {
        Write-ToolkitLog -Message "Pinging $TargetHost ($Count packets)" -Level INFO -Module Network
        $result = Test-Connection -ComputerName $TargetHost -Count $Count -ErrorAction Stop |
            Select-Object Address, ResponseTime, StatusCode

        Write-ToolkitLog -Message "Ping to $TargetHost completed successfully" -Level SUCCESS -Module Network
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Ping to $TargetHost failed: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Invoke-CustomTraceroute {
    <#
    .SYNOPSIS
        Runs a traceroute (tracert) to a target host.
    .PARAMETER TargetHost
        Hostname or IP address to trace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetHost
    )

    try {
        Write-ToolkitLog -Message "Running traceroute to $TargetHost" -Level INFO -Module Network
        # Test-NetConnection -TraceRoute returns structured hop data, unlike raw tracert.exe
        $result = Test-NetConnection -ComputerName $TargetHost -TraceRoute -ErrorAction Stop
        Write-ToolkitLog -Message "Traceroute to $TargetHost completed" -Level SUCCESS -Module Network
        return $result | Select-Object ComputerName, RemoteAddress, TraceRoute
    }
    catch {
        Write-ToolkitLog -Message "Traceroute to $TargetHost failed: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Clear-DNSCacheCustom {
    <#
    .SYNOPSIS
        Flushes the local DNS resolver cache.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Flushing DNS cache" -Level INFO -Module Network
        Clear-DnsClientCache -ErrorAction Stop
        Write-ToolkitLog -Message "DNS cache flushed successfully" -Level SUCCESS -Module Network
        return [PSCustomObject]@{ Action = "Flush DNS Cache"; Status = "Success" }
    }
    catch {
        Write-ToolkitLog -Message "Failed to flush DNS cache: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Reset-IPAddress {
    <#
    .SYNOPSIS
        Releases and renews the IP address on all adapters (ipconfig /release + /renew).
    .DESCRIPTION
        Requires elevation. Equivalent to running ipconfig /release then /renew,
        but wrapped with admin-check, logging, and error handling.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not (Test-IsAdmin)) {
        Write-ToolkitLog -Message "Reset-IPAddress requires administrator privileges - aborted" -Level ERROR -Module Network
        Write-Warning "This action requires an elevated (Run as Administrator) PowerShell session."
        return
    }

    if ($PSCmdlet.ShouldProcess("All network adapters", "Release and renew IP address")) {
        try {
            Write-ToolkitLog -Message "Releasing IP address" -Level INFO -Module Network
            & ipconfig /release | Out-Null

            Write-ToolkitLog -Message "Renewing IP address" -Level INFO -Module Network
            & ipconfig /renew | Out-Null

            Write-ToolkitLog -Message "IP address released and renewed successfully" -Level SUCCESS -Module Network
            return [PSCustomObject]@{ Action = "Release/Renew IP"; Status = "Success" }
        }
        catch {
            Write-ToolkitLog -Message "Release/Renew IP failed: $($_.Exception.Message)" -Level ERROR -Module Network
            throw
        }
    }
}

function Reset-WinsockCatalog {
    <#
    .SYNOPSIS
        Resets the Winsock catalog (netsh winsock reset).
    .DESCRIPTION
        Requires elevation and a reboot to take effect. Use when a machine has
        broken sockets after malware removal or a bad VPN client uninstall.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not (Test-IsAdmin)) {
        Write-ToolkitLog -Message "Reset-WinsockCatalog requires administrator privileges - aborted" -Level ERROR -Module Network
        Write-Warning "This action requires an elevated (Run as Administrator) PowerShell session."
        return
    }

    if ($PSCmdlet.ShouldProcess("Winsock catalog", "Reset")) {
        try {
            Write-ToolkitLog -Message "Resetting Winsock catalog" -Level INFO -Module Network
            & netsh winsock reset | Out-Null
            Write-ToolkitLog -Message "Winsock reset completed - reboot required" -Level SUCCESS -Module Network
            Write-Warning "Winsock reset complete. A reboot is required for changes to take effect."
            return [PSCustomObject]@{ Action = "Reset Winsock"; Status = "Success - Reboot Required" }
        }
        catch {
            Write-ToolkitLog -Message "Winsock reset failed: $($_.Exception.Message)" -Level ERROR -Module Network
            throw
        }
    }
}

function Reset-TCPIPStack {
    <#
    .SYNOPSIS
        Resets the TCP/IP stack (netsh int ip reset).
    .DESCRIPTION
        Requires elevation and a reboot. Use for persistent connectivity issues
        that survive a Winsock reset.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not (Test-IsAdmin)) {
        Write-ToolkitLog -Message "Reset-TCPIPStack requires administrator privileges - aborted" -Level ERROR -Module Network
        Write-Warning "This action requires an elevated (Run as Administrator) PowerShell session."
        return
    }

    if ($PSCmdlet.ShouldProcess("TCP/IP stack", "Reset")) {
        try {
            Write-ToolkitLog -Message "Resetting TCP/IP stack" -Level INFO -Module Network
            & netsh int ip reset | Out-Null
            Write-ToolkitLog -Message "TCP/IP stack reset completed - reboot required" -Level SUCCESS -Module Network
            Write-Warning "TCP/IP stack reset complete. A reboot is required for changes to take effect."
            return [PSCustomObject]@{ Action = "Reset TCP/IP Stack"; Status = "Success - Reboot Required" }
        }
        catch {
            Write-ToolkitLog -Message "TCP/IP stack reset failed: $($_.Exception.Message)" -Level ERROR -Module Network
            throw
        }
    }
}

function Open-DeviceManagerTool  { Write-ToolkitLog -Message "Opening Device Manager" -Level INFO -Module Network; Start-Process devmgmt.msc }
function Open-NetworkSettingsTool { Write-ToolkitLog -Message "Opening Network Settings" -Level INFO -Module Network; Start-Process ms-settings:network-status }
function Open-NetworkTroubleshooterTool { Write-ToolkitLog -Message "Opening Network Troubleshooter" -Level INFO -Module Network; Start-Process msdt.exe -ArgumentList "/id NetworkDiagnosticsNetworkAdapter" }

function Test-DNSResolution {
    <#
    .SYNOPSIS
        Tests DNS resolution for a given hostname.
    .PARAMETER TargetHost
        Hostname to resolve.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetHost
    )

    try {
        Write-ToolkitLog -Message "Resolving DNS for $TargetHost" -Level INFO -Module Network
        $result = Resolve-DnsName -Name $TargetHost -ErrorAction Stop |
            Select-Object Name, Type, IPAddress

        Write-ToolkitLog -Message "DNS resolution for $TargetHost succeeded" -Level SUCCESS -Module Network
        return $result
    }
    catch {
        Write-ToolkitLog -Message "DNS resolution for $TargetHost failed: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Test-PortConnectivity {
    <#
    .SYNOPSIS
        Tests TCP port connectivity to a target host.
    .PARAMETER TargetHost
        Hostname or IP address.
    .PARAMETER Port
        TCP port number to test.
    .EXAMPLE
        Test-PortConnectivity -TargetHost "smtp.office365.com" -Port 587
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetHost,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        Write-ToolkitLog -Message "Testing TCP port $Port on $TargetHost" -Level INFO -Module Network
        $result = Test-NetConnection -ComputerName $TargetHost -Port $Port -ErrorAction Stop

        $level = if ($result.TcpTestSucceeded) { "SUCCESS" } else { "WARN" }
        Write-ToolkitLog -Message "Port $Port on $TargetHost - Reachable: $($result.TcpTestSucceeded)" -Level $level -Module Network

        return [PSCustomObject]@{
            TargetHost      = $TargetHost
            Port            = $Port
            TcpTestSucceeded = $result.TcpTestSucceeded
            RemoteAddress   = $result.RemoteAddress
        }
    }
    catch {
        Write-ToolkitLog -Message "Port test for $($TargetHost):$Port failed: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Get-PingStatistics {
    <#
    .SYNOPSIS
        Runs an extended ping test and returns loss/latency/jitter statistics.
    .DESCRIPTION
        Replaces the "ping -t" pattern (infinite, blocking, no return value) with
        a bounded, scriptable test. This is the difference between a script you
        can only run interactively and one you can call from a report or a
        monitoring job later (v4.0).

        Jitter (average change in latency between consecutive packets) is
        included because packet loss alone doesn't tell the full story - a link
        with 0% loss but high jitter will still break VoIP calls and feel laggy
        over RDP. This is the kind of metric a NOC/network engineer checks that
        a basic ping test misses.
    .PARAMETER TargetHost
        Hostname or IP address to test.
    .PARAMETER Count
        Number of packets to send (1-100). Default 20.
    .EXAMPLE
        Get-PingStatistics -TargetHost "8.8.8.8" -Count 30
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetHost,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Count = 20
    )

    try {
        Write-ToolkitLog -Message "Running extended ping test to $TargetHost ($Count packets)" -Level INFO -Module Network

        # -ErrorAction SilentlyContinue: a failed packet should not abort the whole
        # test - we need it to show up as loss, not throw.
        $replies  = Test-Connection -ComputerName $TargetHost -Count $Count -ErrorAction SilentlyContinue
        $received = $replies.Count
        $lost     = $Count - $received
        $lossPct  = [math]::Round(($lost / $Count) * 100, 1)

        if ($received -eq 0) {
            Write-ToolkitLog -Message "Extended ping to $TargetHost - 100% packet loss" -Level ERROR -Module Network
            return [PSCustomObject]@{
                TargetHost        = $TargetHost
                Sent              = $Count
                Received          = 0
                PacketLossPercent = 100
                MinMs             = $null
                AvgMs             = $null
                MaxMs             = $null
                JitterMs          = $null
            }
        }

        $times = $replies.ResponseTime
        $minMs = ($times | Measure-Object -Minimum).Minimum
        $maxMs = ($times | Measure-Object -Maximum).Maximum
        $avgMs = [math]::Round(($times | Measure-Object -Average).Average, 1)

        # Jitter = average absolute delta between consecutive replies
        $diffs = for ($i = 1; $i -lt $times.Count; $i++) { [math]::Abs($times[$i] - $times[$i - 1]) }
        $jitterMs = if ($diffs) { [math]::Round(($diffs | Measure-Object -Average).Average, 1) } else { 0 }

        $level = if ($lossPct -eq 0) { "SUCCESS" } elseif ($lossPct -lt 20) { "WARN" } else { "ERROR" }
        Write-ToolkitLog -Message "Extended ping to $TargetHost complete - Loss: $lossPct% Avg: ${avgMs}ms Jitter: ${jitterMs}ms" -Level $level -Module Network

        return [PSCustomObject]@{
            TargetHost        = $TargetHost
            Sent              = $Count
            Received          = $received
            PacketLossPercent = $lossPct
            MinMs             = $minMs
            AvgMs             = $avgMs
            MaxMs             = $maxMs
            JitterMs          = $jitterMs
        }
    }
    catch {
        Write-ToolkitLog -Message "Extended ping test to $TargetHost failed: $($_.Exception.Message)" -Level ERROR -Module Network
        throw
    }
}

function Restart-ExplorerShell {
    <#
    .SYNOPSIS
        Force-restarts the Windows Explorer shell (explorer.exe).
    .DESCRIPTION
        Common fix for a frozen taskbar, unresponsive Start menu, or icons that
        won't refresh. This closes ALL open Explorer windows, which is why it
        implements SupportsShouldProcess - unlike the original .bat version,
        this will not run without an explicit confirmation (or -Confirm:$false
        if called non-interactively from the menu).
    .EXAMPLE
        Restart-ExplorerShell
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess("Windows Explorer (explorer.exe)", "Force restart - closes all open Explorer windows")) {
        try {
            Write-ToolkitLog -Message "Restarting Windows Explorer shell" -Level WARN -Module Network
            Stop-Process -Name explorer -Force -ErrorAction Stop
            Start-Sleep -Seconds 1
            Start-Process explorer.exe
            Write-ToolkitLog -Message "Windows Explorer restarted successfully" -Level SUCCESS -Module Network
            return [PSCustomObject]@{ Action = "Restart Explorer"; Status = "Success" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to restart Explorer: $($_.Exception.Message)" -Level ERROR -Module Network
            throw
        }
    }
}

Export-ModuleMember -Function *
