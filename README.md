# Enterprise Admin Toolkit

A PowerShell-based administration, monitoring, and security toolkit built to automate common IT Operations, System Administration, Security Monitoring, and Infrastructure Support tasks.

## Purpose

This project simulates a real-world enterprise administration console used by IT Support, System Administrators, NOC Engineers, and Security Analysts.

It evolves through multiple versions, gradually adding advanced enterprise features — from basic network troubleshooting up to a full WPF GUI console with Active Directory, security monitoring, and reporting.

## Status

| Version | Focus | Status |
|---|---|---|
| v1.0 | Network Troubleshooting Toolkit | ✅ Complete |
| v2.0 | System Administration Toolkit (Active Directory) | 🔜 Planned |
| v3.0 | Security Operations Toolkit (Blue Team) | 🔜 Planned |
| v4.0 | Monitoring & Reporting Platform | 🔜 Planned |
| v5.0 | Enterprise Operations Console (WPF GUI) | 🔜 Planned |

## Getting Started (v1.0)

**Requirements:** Windows 10/11 or Windows Server with PowerShell 5.1+. Some actions require an elevated (Run as Administrator) session.

```powershell
git clone https://github.com/Ayman6594/Enterprise-Admin-Toolkit.git
cd Enterprise-Admin-Toolkit
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
- Destructive/system-changing actions (`Reset-WinsockCatalog`, `Reset-TCPIPStack`, `Reset-IPAddress`) implement `SupportsShouldProcess` (`-WhatIf` / `-Confirm`) and check for administrator privileges before running.

## Roadmap

### v2.0 — System Administration Toolkit
Active Directory user/group management (create, disable, enable, unlock, reset password, group membership), disk usage checks, service management, installed software and system info reports.

### v3.0 — Security Operations Toolkit
Windows Event Log monitoring (failed/successful/privileged logons, account creation/deletion, group membership changes), security auditing (domain admins, lockouts, password policy, local admins), and incident response tooling (log search, user activity investigation, security timeline generation).

### v4.0 — Monitoring & Reporting Platform
Centralized health monitoring (CPU, memory, disk, uptime, services) for Windows and Linux servers, process/critical service monitoring, and automated daily/security/audit reports with HTML dashboard generation.

### v5.0 — Enterprise Operations Console
WPF GUI with dashboard, AD management, security dashboard, monitoring dashboard, dark theme, multi-module architecture, role-based access, configuration profiles, and report export.

### Future Ideas
- **Cloud Integration:** Azure authentication, VM monitoring, resource inventory, user management
- **M365 Integration:** Entra ID, Intune, Exchange Online, licensing reports
- **Security Enhancements:** MITRE ATT&CK mapping, SIEM export, IOC search, threat hunting module

## Project Structure

```
Enterprise-Admin-Toolkit/
├── Core/               # Entry point + shared logging/utility functions
├── Modules/
│   ├── Network/        # v1.0
│   ├── ActiveDirectory/# v2.0
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
