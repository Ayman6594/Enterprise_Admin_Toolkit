<#
.SYNOPSIS
    Reporting module (v4.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Composes functions from THREE other modules - System (v2.0), Security
    (v3.0), and Monitoring (v4.0) - into consolidated reports. This is the
    clearest payoff yet of the "functions return objects, never just print
    text" rule that's been followed since v1.0: none of this would be
    possible if earlier functions had just Write-Host'd their output instead
    of returning structured data.

.NOTES
    Requires the System, Security, and Monitoring modules to already be
    imported into the session (Start-Toolkit.ps1 handles the import order).
#>

function New-DailyHealthReport {
    <#
    .SYNOPSIS
        Generates a daily health snapshot for a machine.
    .PARAMETER ComputerName
        Target machine. Defaults to the local machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ComputerName = $env:COMPUTERNAME
    )

    Write-ToolkitLog -Message "Generating daily health report for $ComputerName" -Level INFO -Module Reports
    $health = Get-WindowsServerHealth -ComputerName $ComputerName

    $result = [PSCustomObject]@{
        ReportType    = "Daily Health Report"
        GeneratedAt   = Get-Date
        ComputerName  = $ComputerName
        OverallStatus = $health.OverallStatus
        CPULoad       = $health.CPULoad
        MemoryPercent = $health.MemoryPercent
        UptimeDays    = $health.UptimeDays
        DiskSummary   = $health.Disks | ForEach-Object { "$($_.Drive) $($_.PercentUsed)% ($($_.Status))" }
        Issues        = $health.Issues
    }

    Write-ToolkitLog -Message "Daily health report for $ComputerName generated - $($health.OverallStatus)" -Level SUCCESS -Module Reports
    return $result
}

function New-SecurityReportSummary {
    <#
    .SYNOPSIS
        Generates a security summary for the specified lookback window.
    .DESCRIPTION
        Wraps v3.0's Security module - specifically New-SecurityTimeline and
        Get-FailedLogonEvents - into a condensed report suitable for a daily
        or weekly summary, rather than the raw event lists those functions
        return directly.
    .PARAMETER Hours
        Lookback window in hours. Default 24.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [int]$Hours = 24
    )

    Write-ToolkitLog -Message "Generating security report summary (last $Hours hour(s))" -Level INFO -Module Reports

    $failed   = Get-FailedLogonEvents -Hours $Hours -MaxEvents 500
    $timeline = New-SecurityTimeline -Hours $Hours

    $byCategory = $timeline | Group-Object Category | Select-Object Name, Count

    $result = [PSCustomObject]@{
        ReportType         = "Security Report"
        GeneratedAt         = Get-Date
        WindowHours         = $Hours
        TotalEvents         = $timeline.Count
        FailedLogonCount    = $failed.Count
        EventsByCategory    = $byCategory
        MostRecentFailure   = $failed | Sort-Object TimeCreated -Descending | Select-Object -First 1
    }

    $level = if ($failed.Count -gt 5) { "WARN" } else { "SUCCESS" }
    Write-ToolkitLog -Message "Security report generated - $($failed.Count) failed logon(s) in window" -Level $level -Module Reports
    return $result
}

function New-ServerAuditReport {
    <#
    .SYNOPSIS
        Generates a full audit snapshot combining system info, installed
        software, local administrators, and disk usage.
    .PARAMETER ComputerName
        Target machine. Currently local-only (System module's underlying
        functions - Get-SystemInfoReport, Get-InstalledSoftwareReport - don't
        support remote targets yet; that would be a natural next extension).
    #>
    [CmdletBinding()]
    param()

    Write-ToolkitLog -Message "Generating server audit report" -Level INFO -Module Reports

    $sysInfo  = Get-SystemInfoReport
    $software = Get-InstalledSoftwareReport
    $localAdmins = Get-LocalAdministratorsAudit
    $disks    = Get-RemoteDiskUsage

    $result = [PSCustomObject]@{
        ReportType         = "Server Audit Report"
        GeneratedAt         = Get-Date
        SystemInfo          = $sysInfo
        InstalledSoftwareCount = $software.Count
        LocalAdministrators = $localAdmins
        Disks               = $disks
    }

    Write-ToolkitLog -Message "Server audit report generated - $($software.Count) software entries, $($localAdmins.Count) local admin(s)" -Level SUCCESS -Module Reports
    return $result
}

function Get-StatusBadgeHtml {
    <#
    .SYNOPSIS
        (Private helper, not exported) Returns a colored HTML badge for a
        status string, so every section uses identical badge styling
        instead of each repeating its own color logic.
    #>
    param([string]$Status)

    $cssClass = switch -Regex ($Status) {
        "OK|HEALTHY|Running"               { "badge-ok" }
        "WARNING|ATTENTION"                 { "badge-warn" }
        "CRITICAL|DOWN|NOT FOUND|ERROR"      { "badge-crit" }
        default                              { "badge-warn" }
    }
    return "<span class='badge $cssClass'>$Status</span>"
}

function Get-UsageBarHtml {
    <#
    .SYNOPSIS
        (Private helper, not exported) Returns an HTML progress bar for a
        percentage value, colored by the same OK/WARNING/CRITICAL thresholds
        used throughout Health Monitoring (v4.0).
    #>
    param([double]$Percent)

    $color = if ($Percent -ge 90) { "#f85149" } elseif ($Percent -ge 75) { "#d29922" } else { "#3fb950" }
    $pct = [math]::Min([math]::Max($Percent, 0), 100)
    return "<div class='bar-container'><div class='bar-fill' style='width:$pct%;background:$color;'></div></div> $Percent%"
}

function New-HTMLDashboard {
    <#
    .SYNOPSIS
        Generates a detailed HTML dashboard combining Health, Security, and
        Audit data, styled to match the toolkit's own console theme.
    .DESCRIPTION
        Unlike the console menu (fixed-width text, one report at a time),
        HTML has no such constraint - this pulls full detail from each
        module directly (per-drive usage bars, a real recent-events
        timeline instead of just category counts, named local administrators,
        a critical-service sweep, and top processes) rather than the
        condensed single-line summaries the console-facing report functions
        return.
    .PARAMETER OutputPath
        Where to write the HTML file. Defaults to Documentation\dashboard.html
        relative to the toolkit root.
    .PARAMETER Hours
        Lookback window in hours for the security section. Default 24.
    .PARAMETER RecentEventCount
        Number of most-recent security events to list individually. Default 15.
    .EXAMPLE
        New-HTMLDashboard -OutputPath "C:\Reports\dashboard.html"
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$OutputPath,
        [Parameter()] [int]$Hours = 24,
        [Parameter()] [int]$RecentEventCount = 15
    )

    if (-not $OutputPath) {
        $rootPath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $OutputPath = Join-Path $rootPath "Documentation\dashboard.html"
    }

    Write-ToolkitLog -Message "Generating HTML dashboard at $OutputPath" -Level INFO -Module Reports

    try {
        # Pull full detail directly from each module, rather than the
        # condensed report functions, so the dashboard can show per-drive
        # bars, named admins, and individual recent events.
        $healthRaw        = Get-WindowsServerHealth
        $securityTimeline = New-SecurityTimeline -Hours $Hours
        $securitySummary  = New-SecurityReportSummary -Hours $Hours
        $audit            = New-ServerAuditReport
        $criticalServices = Get-CriticalServiceStatus
        $topProcesses     = Get-ProcessMonitor -SortBy CPU -Top 5

        # --- Health section ---
        $cpuBar    = Get-UsageBarHtml -Percent $healthRaw.CPULoad
        $memBar    = Get-UsageBarHtml -Percent $healthRaw.MemoryPercent
        $statusBadge = Get-StatusBadgeHtml -Status $healthRaw.OverallStatus

        $diskRows = ($healthRaw.Disks | ForEach-Object {
            "<tr><td>$($_.Drive)</td><td>$($_.TotalGB) GB</td><td>$($_.UsedGB) GB</td><td>$($_.FreeGB) GB</td><td>$(Get-UsageBarHtml -Percent $_.PercentUsed)</td><td>$(Get-StatusBadgeHtml -Status $_.Status)</td></tr>"
        }) -join "`n"

        $issueRows = if ($healthRaw.Issues.Count -gt 0) {
            ($healthRaw.Issues | ForEach-Object { "<li>$_</li>" }) -join "`n"
        } else { "<li>No issues detected</li>" }

        # --- Security section ---
        $categoryRows = ($securitySummary.EventsByCategory | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>"
        }) -join "`n"

        $recentEventRows = ($securityTimeline | Sort-Object TimeCreated -Descending | Select-Object -First $RecentEventCount | ForEach-Object {
            "<tr><td>$($_.TimeCreated)</td><td>$($_.Category)</td><td>$($_.Detail)</td></tr>"
        }) -join "`n"
        if (-not $recentEventRows) { $recentEventRows = "<tr><td colspan='3'>No events in this window</td></tr>" }

        # --- Server audit section ---
        $adminRows = ($audit.LocalAdministrators | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.PrincipalSource)</td></tr>"
        }) -join "`n"

        $serviceRows = ($criticalServices | ForEach-Object {
            "<tr><td>$($_.ServiceName)</td><td>$($_.DisplayName)</td><td>$($_.State)</td><td>$(Get-StatusBadgeHtml -Status $_.Status)</td></tr>"
        }) -join "`n"

        $processRows = ($topProcesses | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.CPU)</td><td>$($_.MemoryMB) MB</td></tr>"
        }) -join "`n"

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Enterprise Admin Toolkit - Dashboard</title>
<style>
    body { background:#0d1b2a; color:#c9d1d9; font-family:Consolas,'Courier New',monospace; margin:0; padding:24px; }
    h1 { color:#58a6ff; border-bottom:1px solid #30363d; padding-bottom:8px; }
    h2 { color:#58a6ff; margin-top:32px; }
    h3 { color:#8b949e; margin-top:20px; margin-bottom:6px; }
    .card { background:#161b22; border:1px solid #30363d; border-radius:6px; padding:16px; margin-bottom:16px; }
    table { width:100%; border-collapse:collapse; }
    td, th { text-align:left; padding:6px 10px; border-bottom:1px solid #30363d; }
    .meta { color:#8b949e; font-size:0.9em; }
    .bar-container { background:#0d1b2a; border:1px solid #30363d; border-radius:4px; height:12px; width:140px;
        overflow:hidden; display:inline-block; vertical-align:middle; margin-right:8px; }
    .bar-fill { height:100%; }
    .badge { padding:2px 10px; border-radius:10px; font-size:0.8em; font-weight:bold; }
    .badge-ok   { background:#3fb95033; color:#3fb950; }
    .badge-warn { background:#d2992233; color:#d29922; }
    .badge-crit { background:#f8514933; color:#f85149; }
</style>
</head>
<body>
    <h1>Enterprise Admin Toolkit - Dashboard</h1>
    <p class="meta">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Host: $($healthRaw.ComputerName)</p>

    <h2>Health Overview</h2>
    <div class="card">
        <p>Status: $statusBadge</p>
        <table>
            <tr><th>CPU Load</th><td>$cpuBar</td></tr>
            <tr><th>Memory Used</th><td>$memBar</td></tr>
            <tr><th>Uptime</th><td>$($healthRaw.UptimeDays) day(s)</td></tr>
        </table>
        <h3>Disks</h3>
        <table><tr><th>Drive</th><th>Total</th><th>Used</th><th>Free</th><th>Usage</th><th>Status</th></tr>$diskRows</table>
        <h3>Issues</h3>
        <ul>$issueRows</ul>
    </div>

    <h2>Security Summary (last $Hours hour(s))</h2>
    <div class="card">
        <table>
            <tr><th>Total Events</th><td>$($securitySummary.TotalEvents)</td></tr>
            <tr><th>Failed Logons</th><td>$($securitySummary.FailedLogonCount)</td></tr>
        </table>
        <h3>Events by Category</h3>
        <table><tr><th>Category</th><th>Count</th></tr>$categoryRows</table>
        <h3>Most Recent Events (up to $RecentEventCount)</h3>
        <table><tr><th>Time</th><th>Category</th><th>Detail</th></tr>$recentEventRows</table>
    </div>

    <h2>Server Audit</h2>
    <div class="card">
        <table>
            <tr><th>OS</th><td>$($audit.SystemInfo.OS)</td></tr>
            <tr><th>CPU</th><td>$($audit.SystemInfo.CPU)</td></tr>
            <tr><th>Installed Software</th><td>$($audit.InstalledSoftwareCount) entries</td></tr>
        </table>
        <h3>Local Administrators</h3>
        <table><tr><th>Name</th><th>Source</th></tr>$adminRows</table>
        <h3>Critical Services</h3>
        <table><tr><th>Service</th><th>Display Name</th><th>State</th><th>Status</th></tr>$serviceRows</table>
    </div>

    <h2>Top Processes (by CPU)</h2>
    <div class="card">
        <table><tr><th>Name</th><th>CPU</th><th>Memory</th></tr>$processRows</table>
    </div>
</body>
</html>
"@

        $outDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
        Set-Content -Path $OutputPath -Value $html -Encoding UTF8 -ErrorAction Stop

        Write-ToolkitLog -Message "HTML dashboard written to $OutputPath" -Level SUCCESS -Module Reports
        return [PSCustomObject]@{ Action = "Generate HTML Dashboard"; Path = $OutputPath; Status = "Success" }
    }
    catch {
        Write-ToolkitLog -Message "Failed to generate HTML dashboard: $($_.Exception.Message)" -Level ERROR -Module Reports
        throw
    }
}

Export-ModuleMember -Function New-DailyHealthReport, New-SecurityReportSummary, New-ServerAuditReport, New-HTMLDashboard
