<#
.SYNOPSIS
    System Administration module (v2.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Local machine administration tasks - no AD/domain dependency, so these
    work on any Windows machine (unlike Modules\ActiveDirectory). Same
    conventions: structured returns, logging, try/catch.
#>

function Get-DiskUsageReport {
    <#
    .SYNOPSIS
        Reports disk usage for all local fixed drives.
    .DESCRIPTION
        Flags drives over 90% used - the threshold most monitoring tools
        (and most enterprises) alert on for "disk getting critical."
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Generating disk usage report" -Level INFO -Module System

        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

        $result = foreach ($drive in $drives) {
            $usedGB    = [math]::Round(($drive.Size - $drive.FreeSpace) / 1GB, 1)
            $freeGB    = [math]::Round($drive.FreeSpace / 1GB, 1)
            $totalGB   = [math]::Round($drive.Size / 1GB, 1)
            $pctUsed   = if ($drive.Size -gt 0) { [math]::Round((($drive.Size - $drive.FreeSpace) / $drive.Size) * 100, 1) } else { 0 }

            [PSCustomObject]@{
                Drive       = $drive.DeviceID
                TotalGB     = $totalGB
                UsedGB      = $usedGB
                FreeGB      = $freeGB
                PercentUsed = $pctUsed
                Status      = if ($pctUsed -ge 90) { "CRITICAL" } elseif ($pctUsed -ge 75) { "WARNING" } else { "OK" }
            }
        }

        $critical = $result | Where-Object { $_.Status -eq "CRITICAL" }
        $level = if ($critical) { "WARN" } else { "SUCCESS" }
        Write-ToolkitLog -Message "Disk usage report generated - $($critical.Count) drive(s) critical" -Level $level -Module System

        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to generate disk usage report: $($_.Exception.Message)" -Level ERROR -Module System
        throw
    }
}

function Restart-ServiceCustom {
    <#
    .SYNOPSIS
        Restarts a Windows service by name.
    .PARAMETER ServiceName
        Name (not display name) of the service, e.g. "Spooler".
    .EXAMPLE
        Restart-ServiceCustom -ServiceName "Spooler"
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
    }
    catch {
        Write-ToolkitLog -Message "Service '$ServiceName' not found: $($_.Exception.Message)" -Level ERROR -Module System
        throw
    }

    if ($PSCmdlet.ShouldProcess($service.DisplayName, "Restart service")) {
        try {
            Write-ToolkitLog -Message "Restarting service '$ServiceName' ($($service.DisplayName))" -Level WARN -Module System
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop

            $updated = Get-Service -Name $ServiceName
            Write-ToolkitLog -Message "Service '$ServiceName' restarted - status: $($updated.Status)" -Level SUCCESS -Module System

            return [PSCustomObject]@{
                ServiceName = $ServiceName
                DisplayName = $updated.DisplayName
                Status      = $updated.Status
            }
        }
        catch {
            Write-ToolkitLog -Message "Failed to restart service '$ServiceName': $($_.Exception.Message)" -Level ERROR -Module System
            throw
        }
    }
}

function Get-RunningServicesReport {
    <#
    .SYNOPSIS
        Lists all currently running Windows services.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Retrieving running services" -Level INFO -Module System

        $result = Get-Service -ErrorAction Stop |
            Where-Object { $_.Status -eq "Running" } |
            Select-Object Name, DisplayName, StartType |
            Sort-Object DisplayName

        Write-ToolkitLog -Message "Found $($result.Count) running service(s)" -Level SUCCESS -Module System
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to retrieve running services: $($_.Exception.Message)" -Level ERROR -Module System
        throw
    }
}

function Get-InstalledSoftwareReport {
    <#
    .SYNOPSIS
        Reports installed software from the registry (32-bit and 64-bit views).
    .DESCRIPTION
        Reads the Uninstall registry keys directly rather than using
        Win32_Product (WMI) - Win32_Product is well known to be slow and to
        trigger a repair/reconfigure of every MSI package it touches, which
        is a real (if obscure) production incident risk. This is exactly the
        kind of "gotcha" worth remembering for interviews and for real work.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Generating installed software report" -Level INFO -Module System

        $paths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $result = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
            Sort-Object DisplayName -Unique

        Write-ToolkitLog -Message "Installed software report generated - $($result.Count) entries" -Level SUCCESS -Module System
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to generate installed software report: $($_.Exception.Message)" -Level ERROR -Module System
        throw
    }
}

function Get-SystemInfoReport {
    <#
    .SYNOPSIS
        Reports key system information: OS, hardware, uptime.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-ToolkitLog -Message "Generating system information report" -Level INFO -Module System

        $os  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cs  = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1

        $uptime = (Get-Date) - $os.LastBootUpTime

        $result = [PSCustomObject]@{
            ComputerName   = $cs.Name
            OS             = $os.Caption
            OSVersion      = $os.Version
            Manufacturer   = $cs.Manufacturer
            Model          = $cs.Model
            CPU            = $cpu.Name
            TotalRAMGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            LastBoot       = $os.LastBootUpTime
            UptimeDays     = [math]::Round($uptime.TotalDays, 1)
        }

        Write-ToolkitLog -Message "System information report generated" -Level SUCCESS -Module System
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to generate system information report: $($_.Exception.Message)" -Level ERROR -Module System
        throw
    }
}

Export-ModuleMember -Function *
