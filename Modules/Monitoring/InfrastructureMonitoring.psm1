<#
.SYNOPSIS
    Infrastructure Monitoring module (v4.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Get-WindowsServerHealth and Get-CriticalServiceStatus COMPOSE the
    HealthMonitoring functions (same reuse pattern as v3.0's IncidentResponse
    composing EventLogMonitoring) - the individual metric logic lives in one
    place only.

.NOTES
    Get-LinuxServerHealth requires the Posh-SSH module (Install-Module
    Posh-SSH) and SSH access to a Linux host - NOT built into Windows or
    this toolkit. Untested without an actual Linux target; treat it the same
    way as the AD-dependent v3.0 functions: built, but unverified until you
    have something to point it at.
#>

function Get-WindowsServerHealth {
    <#
    .SYNOPSIS
        Consolidated health check for a Windows machine - CPU, memory, disk,
        uptime, and a set of critical services, in one call.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    .PARAMETER CriticalServices
        Services to check as part of this health check. Defaults to a
        reasonable baseline (Spooler, WinDefend, EventLog, Dnscache).
    .EXAMPLE
        Get-WindowsServerHealth -ComputerName "SRV-FILE01"
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME,
        [Parameter()] [string[]]$CriticalServices = @("Spooler", "WinDefend", "EventLog", "Dnscache")
    )

    Write-ToolkitLog -Message "Running consolidated Windows server health check on $ComputerName" -Level INFO -Module Monitoring

    $cpu      = Get-CPUUtilization -ComputerName $ComputerName
    $memory   = Get-MemoryUsage -ComputerName $ComputerName
    $disks    = Get-RemoteDiskUsage -ComputerName $ComputerName
    $uptime   = Get-UptimeStatus -ComputerName $ComputerName
    $services = Get-ServiceHealthCheck -ServiceName $CriticalServices -ComputerName $ComputerName

    $issues = @()
    if ($cpu.Status -ne "OK") { $issues += "CPU: $($cpu.Status)" }
    if ($memory.Status -ne "OK") { $issues += "Memory: $($memory.Status)" }
    $issues += ($disks | Where-Object { $_.Status -ne "OK" } | ForEach-Object { "Disk $($_.Drive): $($_.Status)" })
    $issues += ($services | Where-Object { $_.Status -ne "OK" } | ForEach-Object { "Service $($_.ServiceName): $($_.Status)" })

    $overallStatus = if ($issues.Count -eq 0) { "HEALTHY" } else { "ATTENTION NEEDED" }

    $result = [PSCustomObject]@{
        ComputerName   = $ComputerName
        OverallStatus  = $overallStatus
        CPULoad        = $cpu.LoadPercentage
        MemoryPercent  = $memory.PercentUsed
        UptimeDays     = $uptime.UptimeDays
        Disks          = $disks
        Services       = $services
        Issues         = $issues
    }

    $level = if ($overallStatus -eq "HEALTHY") { "SUCCESS" } else { "WARN" }
    Write-ToolkitLog -Message "Windows server health check on $ComputerName complete - $overallStatus ($($issues.Count) issue(s))" -Level $level -Module Monitoring
    return $result
}

function Get-LinuxServerHealth {
    <#
    .SYNOPSIS
        Consolidated health check for a Linux machine via SSH.
    .DESCRIPTION
        REQUIRES the Posh-SSH module (Install-Module -Name Posh-SSH) and SSH
        access to the target. Runs standard Linux commands (uptime, df, free)
        over an SSH session and parses their output - this is fundamentally
        different from the Windows functions above, which use CIM/WMI.
        There is no CIM equivalent on Linux, so remote command execution +
        text parsing is the standard approach here.
    .PARAMETER HostName
        Linux host to connect to.
    .PARAMETER Credential
        SSH credential (username + password or key-based, per Posh-SSH).
    .NOTES
        UNTESTED - no Linux target available during development. Verify
        against a real Linux host before relying on this in production; the
        command output parsing in particular is the most likely thing to
        need adjustment for a specific distro's exact output format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$HostName,
        [Parameter(Mandatory = $true)] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        Write-ToolkitLog -Message "Posh-SSH module not installed - cannot check Linux host $HostName" -Level ERROR -Module Monitoring
        Write-Warning "Requires the Posh-SSH module. Install with: Install-Module -Name Posh-SSH -Scope CurrentUser"
        return
    }

    Import-Module Posh-SSH -ErrorAction SilentlyContinue

    try {
        Write-ToolkitLog -Message "Connecting via SSH to $HostName" -Level INFO -Module Monitoring
        $session = New-SSHSession -ComputerName $HostName -Credential $Credential -AcceptKey -ErrorAction Stop

        $uptimeRaw = (Invoke-SSHCommand -SSHSession $session -Command "uptime -p").Output
        $memRaw    = (Invoke-SSHCommand -SSHSession $session -Command "free -m | grep Mem").Output
        $diskRaw   = (Invoke-SSHCommand -SSHSession $session -Command "df -h --output=source,pcent,target -x tmpfs -x devtmpfs").Output

        Remove-SSHSession -SSHSession $session | Out-Null

        # free -m "Mem:" line format: Mem: total used free shared buff/cache available
        $memParts = ($memRaw -split '\s+') | Where-Object { $_ -ne "" }
        $memTotalMB = [int]$memParts[1]
        $memUsedMB  = [int]$memParts[2]
        $memPercent = if ($memTotalMB -gt 0) { [math]::Round(($memUsedMB / $memTotalMB) * 100, 1) } else { 0 }

        $result = [PSCustomObject]@{
            HostName      = $HostName
            Uptime        = $uptimeRaw
            MemoryPercent = $memPercent
            DiskUsageRaw  = $diskRaw
        }

        Write-ToolkitLog -Message "Linux health check on $HostName complete" -Level SUCCESS -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to check Linux host $HostName via SSH: $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-ProcessMonitor {
    <#
    .SYNOPSIS
        Lists the top processes by CPU or memory usage.
    .PARAMETER SortBy
        "CPU" or "Memory". Default "CPU".
    .PARAMETER Top
        Number of processes to return. Default 10.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [ValidateSet("CPU", "Memory")] [string]$SortBy = "CPU",
        [Parameter()] [int]$Top = 10,
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    try {
        Write-ToolkitLog -Message "Retrieving top $Top processes by $SortBy on $ComputerName" -Level INFO -Module Monitoring

        if ($ComputerName -eq $env:COMPUTERNAME) {
            $processes = Get-Process
        } else {
            # Get-Process doesn't support -ComputerName directly (removed in
            # PS6+) - CIM is the cross-version-compatible way to get remote
            # process data, same reasoning as the CIM choice in HealthMonitoring.
            $processes = Get-CimInstance -ClassName Win32_Process -ComputerName $ComputerName -ErrorAction Stop |
                Select-Object Name, @{N = "CPU"; E = { $_.UserModeTime } }, @{N = "WorkingSet"; E = { $_.WorkingSetSize } }
        }

        $sorted = if ($SortBy -eq "CPU") {
            $processes | Sort-Object CPU -Descending
        } else {
            $processes | Sort-Object WorkingSet -Descending
        }

        $result = $sorted | Select-Object -First $Top -Property Name,
            @{N = "CPU"; E = { [math]::Round($_.CPU, 1) } },
            @{N = "MemoryMB"; E = { [math]::Round($_.WorkingSet / 1MB, 1) } }

        Write-ToolkitLog -Message "Process monitor on $ComputerName - top $Top by $SortBy retrieved" -Level SUCCESS -Module Monitoring
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to retrieve process list on $ComputerName - $($_.Exception.Message)" -Level ERROR -Module Monitoring
        throw
    }
}

function Get-CriticalServiceStatus {
    <#
    .SYNOPSIS
        Checks a standard baseline of critical Windows services and flags any
        that are not running.
    .DESCRIPTION
        Composes Get-ServiceHealthCheck with a fixed, opinionated list of
        services that matter on nearly any Windows server/workstation -
        distinct from Get-ServiceHealthCheck itself, which checks whatever
        services you name. This is the "quick alert sweep" version.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    $criticalList = @("Dnscache", "Dhcp", "EventLog", "RpcSs", "LanmanServer", "LanmanWorkstation", "WinDefend")

    Write-ToolkitLog -Message "Running critical service sweep on $ComputerName" -Level INFO -Module Monitoring
    $result = Get-ServiceHealthCheck -ServiceName $criticalList -ComputerName $ComputerName

    $down = $result | Where-Object { $_.Status -ne "OK" }
    $level = if ($down) { "WARN" } else { "SUCCESS" }
    Write-ToolkitLog -Message "Critical service sweep on $ComputerName - $($down.Count) of $($criticalList.Count) not running" -Level $level -Module Monitoring
    return $result
}

Export-ModuleMember -Function Get-WindowsServerHealth, Get-LinuxServerHealth, Get-ProcessMonitor, Get-CriticalServiceStatus
