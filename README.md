# Enterprise Admin Toolkit

A PowerShell-based administration, monitoring, and security toolkit built to automate common IT Operations, System Administration, Security Monitoring, and Infrastructure Support tasks.

## Purpose

This project simulates a real-world enterprise administration console used by IT Support, System Administrators, NOC Engineers, and Security Analysts.

It evolves through multiple versions, gradually adding advanced enterprise features — from basic network troubleshooting up to a full WPF GUI console with Active Directory, security monitoring, and reporting.

## Status

| Version | Focus | Status |
|---|---|---|
| v1.0 | Network Troubleshooting Toolkit | ✅ Complete |
| v2.0 | System Administration Toolkit (Active Directory) | ✅ Complete |
| v3.0 | Security Operations Toolkit (Blue Team) | ✅ Complete (non-AD portions verified; AD-dependent auditing functions pending lab) |
| v4.0 | Monitoring & Reporting Platform | ✅ Built (local checks verified; remote Windows and Linux/SSH monitoring pending test targets) |
| v5.0 | Enterprise Operations Console (WPF GUI) | 🔜 Planned |

## Getting Started

**Requirements:** Windows 10/11 or Windows Server with PowerShell 5.1+. The Active Directory menu requires the RSAT ActiveDirectory PowerShell module and a domain-joined machine — if it's not installed, the toolkit detects this at launch and disables that menu instead of crashing. The **Security Operations menu requires running PowerShell as Administrator** — reading the Security event log is blocked for standard users by Windows itself, not by this toolkit. **Linux Server Monitoring (v4.0)** additionally requires the `Posh-SSH` module (`Install-Module -Name Posh-SSH`) and SSH access to a Linux host.

**Language/locale:** developed and tested on a French-display-language Windows install. Most of the toolkit is locale-independent by design (e.g. `Get-LocalAdministratorsAudit` queries the built-in Administrators group by its well-known SID, `S-1-5-32-544`, rather than by the English name — which differs per language, e.g. "Administrateurs" on French Windows). The one exception: `Get-FailedLogonEvents`' `FailureReason` field is extracted via a regex matching the English phrase `"Failure Reason:"` in the raw Security log message. This worked during testing because Security log message text was in English even on a French-UI machine, but is not guaranteed on every install — a system with a full French language pack applied to the Security event provider could log this in French instead, which would cause that one field to silently fall back to an unresolved code rather than readable text. **For guaranteed correct behavior, run on a machine where Security log message text is in English** (the default on most installs unless a non-English language pack was explicitly applied).

```powershell
git clone https://github.com/Ayman6594/Enterprise_Admin_Toolkit.git
cd Enterprise_Admin_Toolkit
.\Core\Start-Toolkit.ps1
```

## v1.0 — Network Troubleshooting Toolkit

- Display Full IP Configuration
- Test Internet Connectivity
- Ping Custom Host
- Traceroute
- Flush DNS Cache
- Release/Renew IP Address *(admin)*
- Reset Winsock *(admin)*
- Reset TCP/IP Stack *(admin)*
- Open Device Manager
- Open Network Settings
- Open Network Troubleshooter
- DNS Resolution Test
- Port Connectivity Test
- Extended Ping Statistics (packet loss / min-avg-max latency / jitter)
- Restart Windows Explorer *(confirmation required)*

**Design principles:**
- Every module function returns structured PowerShell objects, not raw console text — so results can later feed into the Reports module (v4.0) or a GUI grid (v5.0) without rewriting logic.
- Every action is logged to `Logs\toolkit.log` via a centralized logging function (`Write-ToolkitLog`) — full audit trail of who ran what, when.
- Destructive/system-changing actions implement `SupportsShouldProcess` (`-WhatIf` / `-Confirm`) and check for administrator privileges before running.

## v2.0 — System Administration Toolkit

**Active Directory** *(requires RSAT-AD-PowerShell + domain-joined machine)*
- Create User · Disable User · Enable User · Unlock User · Reset Password
- Add User To Group · Remove User From Group
- List Disabled Users · List Locked Users

**System Administration** *(local machine, no domain required)*
- Check Disk Usage (flags drives ≥90% used)
- Restart Service
- View Running Services
- Installed Software Report (reads registry directly, not `Win32_Product` — avoids its known MSI-repair side effect)
- System Information Report

**Design notes:**
- Every AD action accepts an optional `-Credential` parameter for least-privilege execution.
- The console menu is category-based (Network / Active Directory / System Administration / Security Operations / Monitoring & Reporting), each with its own submenu.
- Shared utilities (`Write-ToolkitLog`, `Test-IsAdmin`, `Test-ADModuleAvailable`) are implemented as proper PowerShell modules (`.psm1`, `Import-Module`), not dot-sourced scripts — dot-sourcing only shares functions with one script's own scope, which breaks visibility for other imported modules that need to call them.

## v3.0 — Security Operations Toolkit

**Event Log Monitoring:** Failed Logons (4625) · Successful Logons (4624) · Privileged Logons (4672) · User Creation (4720) · User Deletion (4726) · Group Membership Changes (4728/4729/4732/4733)

**Security Auditing:** Domain Admin Audit · Account Lockout Audit · Disabled Accounts Report · Password Policy Review · Local Administrators Audit

**Incident Response:** Search Event Logs · Investigate User Activity (per-user timeline) · Generate Security Timeline (consolidated, all categories)

**Design notes:**
- Uses `Get-WinEvent -FilterHashtable`, not `Get-EventLog` — filters at the query-engine level before events are pulled into PowerShell.
- `FailureReason` is parsed from the event's full message text rather than its indexed property — `Get-WinEvent`'s `.Properties[n]` can return an unresolved message-table reference (e.g. `%%2304`) on this specific field.
- `Get-LocalAdministratorsAudit` queries by the well-known SID (`S-1-5-32-544`), not by the English name "Administrators" — the built-in group is named differently on non-English Windows installs (e.g. "Administrateurs" on French Windows).
- `Get-UserActivityInvestigation` matches usernames by substring, not exact equality — the same account can appear under different logged formats (SamAccountName, UPN, or a full email address for Microsoft-account sign-ins).
- Incident Response functions compose the Event Log Monitoring functions rather than re-querying the log directly.
- Account-management events and most Security Auditing functions require the AD module and, for meaningful results, running against the Domain Controller.

## v4.0 — Monitoring & Reporting Platform

**Health Monitoring** *(local or remote via `-ComputerName`, remote requires WinRM on the target)*
- CPU Utilization · Memory Usage · Disk Usage · Uptime · Service Health Check · Network Connectivity Health

**Infrastructure Monitoring**
- Windows Server Monitoring (consolidated CPU/Memory/Disk/Uptime/Services in one call)
- Linux Server Monitoring via SSH *(requires `Posh-SSH` + a Linux target — untested, no target available during development)*
- Process Monitoring (top processes by CPU or memory)
- Critical Service Sweep (checks a fixed baseline of commonly critical services)

**Reporting**
- Daily Health Report
- Security Report (summarizes v3.0's Security module output)
- Server Audit Report (combines System, Security, and Monitoring data)
- HTML Dashboard Generation — dark-themed, with colored progress bars (CPU/memory/disk), status badges, a real recent-events security timeline (not just category counts), named local administrators, a critical-services table, and top-5 processes by CPU

**Design notes:**
- `Get-CimInstance` is only called with `-ComputerName` for genuinely remote targets — passing it even for the local machine forces the WinRM/WS-Management path instead of the fast local one, which fails outright if WinRM isn't configured (a real bug found and fixed during testing).
- Uses `Get-CimInstance` rather than `Get-Counter` for cross-machine metrics — one code path works identically for local and remote targets, where `Get-Counter`'s remoting behavior is inconsistent.
- The Reports module composes functions from System (v2.0), Security (v3.0), and Monitoring (v4.0) — the clearest payoff of the "always return objects, never just print text" rule followed since v1.0.
- Remote Windows monitoring requires WinRM enabled on the target (`Enable-PSRemoting`); Linux monitoring requires the `Posh-SSH` module and SSH access.

## Roadmap

### v5.0 — Enterprise Operations Console
WPF GUI with dashboard, AD management, security dashboard, monitoring dashboard, dark theme, multi-module architecture, role-based access, configuration profiles, and report export.

### Future Ideas
- **Cloud Integration:** Azure authentication, VM monitoring, resource inventory, user management
- **M365 Integration:** Entra ID, Intune, Exchange Online, licensing reports
- **Security Enhancements:** MITRE ATT&CK mapping, SIEM export, IOC search, threat hunting module

## Project Structure

```
Enterprise-Admin-Toolkit/
├── Core/               # Entry point + shared logging/prerequisites
├── Modules/
│   ├── Network/        # v1.0
│   ├── ActiveDirectory/# v2.0
│   ├── System/         # v2.0
│   ├── Security/       # v3.0
│   ├── Monitoring/     # v4.0
│   └── Reports/        # v4.0
├── GUI/                # v5.0
├── Config/             # Central configuration (config.psd1)
├── Logs/                # Runtime logs (git-ignored)
├── Documentation/
├── Screenshots/
└── Releases/
```

## Technologies

PowerShell · Active Directory · Windows Server · Event Viewer · WPF · HTML/CSS Reporting · Microsoft Entra ID (future) · Microsoft Azure (future)

## Author

**Ayman Ibnousoufyane**
IT Support | Systems | Networks | Cloud | Security
[GitHub](https://github.com/Ayman6594)
