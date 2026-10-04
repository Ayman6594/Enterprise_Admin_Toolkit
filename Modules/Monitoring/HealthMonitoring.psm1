<#
.SYNOPSIS
    Health Monitoring module (v4.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Every function accepts -ComputerName (default: local machine) and uses
    Get-CimInstance rather than Get-Counter. This is a deliberate choice:
    Get-Counter's remoting story is inconsistent and slow (it relies on the
    performance counter subsystem, which behaves differently over WinRM);
    Get-CimInstance -ComputerName works identically whether the target is
    local or remote, using the same WMI/CIM classes either way. One code
    path for both cases, rather than branching logic for local vs remote.

.NOTES
    Local checks (this machine) work immediately. Checks against -ComputerName
    pointing at another machine require WinRM enabled on that target
    (Enable-PSRemoting) and appropriate firewall/permissions - same class of
    requirement as RSAT for the ActiveDirectory module, just a different
    subsystem.
#>

function Get-CPUUtilization {
    <#
    .SYNOPSIS
        Reports current CPU utilization percentage.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Checking CPU utilization on $ComputerName" -Level INFO -Module Monitoring
        # Only pass -ComputerName to Get-CimInstance when the target is NOT
        # this machine. Passing -ComputerName at all - even your own hostname -
        # forces a remote CIM session over WinRM, which isn't enabled by
        # default on a standard Windows install. Omitting it entirely uses
        # the fast local path with no WinRM dependency.
        $cimParams = @{ ClassName = "Win32_Processor"; ErrorAction = "Stop" }
        if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $cimParams["ComputerName"] = $ComputerName }
        $cpu = Get-CimInstance @cimParams

        # A multi-core/multi-socket system returns one instance per logical
        # processor - average LoadPercentage across all of them for one
        # overall figure.
        $avgLoad = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average, 1)

        $result = [PSCustomObject]@{
            ComputerName   = $ComputerName
            CPUName        = ($cpu | Select-Object -First 1).Name
            LogicalCores   = $cpu.Count
            LoadPercentage = $avgLoad
            Status         = if ($avgLoad -ge 90) { "CRITICAL" } elseif ($avgLoad -ge 75) { "WARNING" } else { "OK" }
        }

        $level = if ($avgLoad -ge 90) { "WARN" } else { "SUCCESS" }
        Write-ToolkitLog -Message "CPU check on $ComputerName - $avgLoad% load" -Level $level -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check CPU on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-MemoryUsage {
    <#
    .SYNOPSIS
        Reports current memory usage.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Checking memory usage on $ComputerName" -Level INFO -Module Monitoring
        $cimParams = @{ ClassName = "Win32_OperatingSystem"; ErrorAction = "Stop" }
        if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $cimParams["ComputerName"] = $ComputerName }
        $os = Get-CimInstance @cimParams

        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedGB  = [math]::Round($totalGB - $freeGB, 1)
        $pctUsed = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            TotalGB      = $totalGB
            UsedGB       = $usedGB
            FreeGB       = $freeGB
            PercentUsed  = $pctUsed
            Status       = if ($pctUsed -ge 90) { "CRITICAL" } elseif ($pctUsed -ge 75) { "WARNING" } else { "OK" }
        }

        $level = if ($pctUsed -ge 90) { "WARN" } else { "SUCCESS" }
        Write-ToolkitLog -Message "Memory check on $ComputerName - $pctUsed% used" -Level $level -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check memory on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-RemoteDiskUsage {
    <#
    .SYNOPSIS
        Reports disk usage for all fixed drives on a target machine.
    .DESCRIPTION
        Same purpose as v2.0's Get-DiskUsageReport in Modules\System, but
        with -ComputerName support for remote targets - kept as a separate
        function rather than modifying the v2.0 one, so the already-tested
        local-only version stays untouched and low-risk.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Checking disk usage on $ComputerName" -Level INFO -Module Monitoring
        $cimParams = @{ ClassName = "Win32_LogicalDisk"; Filter = "DriveType=3"; ErrorAction = "Stop" }
        if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $cimParams["ComputerName"] = $ComputerName }
        $drives = Get-CimInstance @cimParams

        $result = foreach ($drive in $drives) {
            $usedGB  = [math]::Round(($drive.Size - $drive.FreeSpace) / 1GB, 1)
            $freeGB  = [math]::Round($drive.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($drive.Size / 1GB, 1)
            $pctUsed = if ($drive.Size -gt 0) { [math]::Round((($drive.Size - $drive.FreeSpace) / $drive.Size) * 100, 1) } else { 0 }

            [PSCustomObject]@{
                ComputerName = $ComputerName
                Drive        = $drive.DeviceID
                TotalGB      = $totalGB
                UsedGB       = $usedGB
                FreeGB       = $freeGB
                PercentUsed  = $pctUsed
                Status       = if ($pctUsed -ge 90) { "CRITICAL" } elseif ($pctUsed -ge 75) { "WARNING" } else { "OK" }
            }
        }

        $critical = $result | Where-Object { $_.Status -eq "CRITICAL" }
        $level = if ($critical) { "WARN" } else { "SUCCESS" }
        Write-ToolkitLog -Message "Disk check on $ComputerName - $($critical.Count) drive(s) critical" -Level $level -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check disk usage on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-UptimeStatus {
    <#
    .SYNOPSIS
        Reports system uptime and last boot time for a target machine.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Checking uptime on $ComputerName" -Level INFO -Module Monitoring
        $cimParams = @{ ClassName = "Win32_OperatingSystem"; ErrorAction = "Stop" }
        if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $cimParams["ComputerName"] = $ComputerName }
        $os = Get-CimInstance @cimParams
        $uptime = (Get-Date) - $os.LastBootUpTime

        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            LastBoot     = $os.LastBootUpTime
            UptimeDays   = [math]::Round($uptime.TotalDays, 1)
            UptimeHours  = [math]::Round($uptime.TotalHours, 1)
        }

        Write-ToolkitLog -Message "Uptime check on $ComputerName - $($result.UptimeDays) day(s)" -Level SUCCESS -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check uptime on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-ServiceHealthCheck {
    <#
    .SYNOPSIS
        Checks the status of one or more named services on a target machine.
    .PARAMETER ServiceName
        One or more service names to check.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    .EXAMPLE
        Get-ServiceHealthCheck -ServiceName "Spooler","WinDefend"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string[]]$ServiceName,
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Checking service health on $ComputerName - $($ServiceName -join ',')" -Level INFO -Module Monitoring

        $result = foreach ($name in $ServiceName) {
            try {
                $cimParams = @{ ClassName = "Win32_Service"; Filter = "Name='$name'"; ErrorAction = "Stop" }
                if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $cimParams["ComputerName"] = $ComputerName }
                $svc = Get-CimInstance @cimParams
                if ($svc) {
                    [PSCustomObject]@{
                        ComputerName = $ComputerName
                        ServiceName  = $svc.Name
                        DisplayName  = $svc.DisplayName
                        State        = $svc.State
                        StartMode    = $svc.StartMode
                        Status       = if ($svc.State -eq "Running") { "OK" } else { "DOWN" }
                    }
                } else {
                    [PSCustomObject]@{
                        ComputerName = $ComputerName; ServiceName = $name; DisplayName = "N/A"
                        State = "Not Found"; StartMode = "N/A"; Status = "NOT FOUND"
                    }
                }
            }
            catch {
                [PSCustomObject]@{
                    ComputerName = $ComputerName; ServiceName = $name; DisplayName = "N/A"
                    State = "Error"; StartMode = "N/A"; Status = "ERROR"
                }
            }
        }

        $down = $result | Where-Object { $_.Status -ne "OK" }
        $level = if ($down) { "WARN" } else { "SUCCESS" }
        Write-ToolkitLog -Message "Service health check on $ComputerName - $($down.Count) service(s) not running" -Level $level -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check service health on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Test-NetworkConnectivityHealth {
    <#
    .SYNOPSIS
        Checks whether a target machine is reachable and responding.
    .DESCRIPTION
        Distinct from v1.0's Test-InternetConnectivity (which checks THIS
        machine's path to the internet) - this checks reachability TO a
        specific server, the natural question when monitoring infrastructure
        rather than troubleshooting a workstation's own connection.
    .PARAMETER ComputerName
        Target machine to check.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ComputerName
    )

    try {
        Write-ToolkitLog -Message "Checking network connectivity to $ComputerName" -Level INFO -Module Monitoring
        $ping = Test-Connection -ComputerName $ComputerName -Count 4 -ErrorAction Stop

        $received = $ping.Count
        $avgLatency = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)

        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            Reachable    = $received -gt 0
            PacketsSent  = 4
            PacketsGot   = $received
            AvgLatencyMs = $avgLatency
        }

        $level = if ($result.Reachable) { "SUCCESS" } else { "WARN" }
        Write-ToolkitLog -Message "Connectivity check to $ComputerName - Reachable: $($result.Reachable)" -Level $level -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "$ComputerName unreachable: $($_.Exception.Message)" -Level WARN -Module Monitoring
        return [PSCustomObject]@{ ComputerName = $ComputerName; Reachable = $false; PacketsSent = 4; PacketsGot = 0; AvgLatencyMs = $null }
    }
}

Export-ModuleMember -Function Get-CPUUtilization, Get-MemoryUsage, Get-RemoteDiskUsage, Get-UptimeStatus, Get-ServiceHealthCheck, Test-NetworkConnectivityHealth
