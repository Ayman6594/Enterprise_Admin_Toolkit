<#
.SYNOPSIS
    Environment prerequisite checks for Enterprise Admin Toolkit modules.

.DESCRIPTION
    Some modules (ActiveDirectory) depend on Windows features/RSAT tools that
    aren't present on every machine. Rather than let Import-Module throw a
    raw "module not found" error deep in the menu, we check up front and
    give the operator a clear, actionable message.
#>

function Test-ADModuleAvailable {
    <#
    .SYNOPSIS
        Checks whether the ActiveDirectory PowerShell module is installed.
    .DESCRIPTION
        The ActiveDirectory module ships with RSAT (Remote Server Administration
        Tools). It is NOT installed by default on Windows 10/11 or on a member
        server without the RSAT-AD-PowerShell feature.
    #>
    [CmdletBinding()]
    param()

    $available = [bool](Get-Module -ListAvailable -Name ActiveDirectory)
    return $available
}

Export-ModuleMember -Function Test-ADModuleAvailable
