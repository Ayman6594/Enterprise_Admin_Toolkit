<#
.SYNOPSIS
    Active Directory administration module (v2.0) for Enterprise Admin Toolkit.

.DESCRIPTION
    Wraps the built-in ActiveDirectory module (RSAT) cmdlets with the same
    conventions as Modules\Network: structured object returns, centralized
    logging, try/catch, and SupportsShouldProcess on every action that
    changes an account's state.

    IMPORTANT - runs in the caller's current security context (Kerberos/NTLM
    via the logged-on user), same as running these cmdlets directly in a
    PowerShell session on a domain-joined machine. It does NOT prompt for
    separate admin credentials by default. If you need to run this as a
    different account (e.g. a dedicated "SupportTools" service/admin account
    rather than your own elevated account - the least-privilege pattern most
    enterprises actually want), every function below accepts an optional
    -Credential parameter that gets passed straight through to the
    underlying AD cmdlet.

.NOTES
    Requires: ActiveDirectory module (RSAT-AD-PowerShell), a domain-joined
    machine, and an account with the relevant AD permissions delegated to it.
    Test against a lab domain - never against production AD.
#>

function New-ADUserAccount {
    <#
    .SYNOPSIS
        Creates a new Active Directory user account.
    .PARAMETER GivenName
        First name.
    .PARAMETER Surname
        Last name.
    .PARAMETER SamAccountName
        Logon name (e.g. "jdupont"). Must be unique in the domain.
    .PARAMETER OUPath
        Distinguished Name of the target OU, e.g. "OU=Support,DC=corp,DC=local".
        If omitted, AD places the account in the default Users container.
    .PARAMETER Credential
        Optional alternate credential to run the operation as.
    .EXAMPLE
        New-ADUserAccount -GivenName "Jean" -Surname "Dupont" -SamAccountName "jdupont" -OUPath "OU=Support,DC=corp,DC=local"
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$GivenName,
        [Parameter(Mandatory = $true)] [string]$Surname,
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter()] [string]$OUPath,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot create user" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Create AD user account")) {
        try {
            Write-ToolkitLog -Message "Creating AD user '$SamAccountName' ($GivenName $Surname)" -Level INFO -Module ActiveDirectory

            # Temporary password + ChangePasswordAtLogon: standard enterprise onboarding
            # pattern - the account is created but unusable until the new hire sets
            # their own password on first logon.
            $tempPassword = ConvertTo-SecureString -String ([System.Guid]::NewGuid().ToString().Substring(0, 12) + "!Aa1") -AsPlainText -Force

            $params = @{
                Name                  = "$GivenName $Surname"
                GivenName             = $GivenName
                Surname               = $Surname
                SamAccountName        = $SamAccountName
                UserPrincipalName     = "$SamAccountName@$((Get-ADDomain).DNSRoot)"
                AccountPassword       = $tempPassword
                Enabled               = $true
                ChangePasswordAtLogon = $true
                ErrorAction           = "Stop"
            }
            if ($OUPath)      { $params["Path"]       = $OUPath }
            if ($Credential)  { $params["Credential"] = $Credential }

            New-ADUser @params

            Write-ToolkitLog -Message "AD user '$SamAccountName' created successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{
                SamAccountName = $SamAccountName
                Name           = "$GivenName $Surname"
                Status         = "Created - temporary password set, ChangePasswordAtLogon enabled"
            }
        }
        catch {
            Write-ToolkitLog -Message "Failed to create AD user '$SamAccountName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Disable-ADUserAccount {
    <#
    .SYNOPSIS
        Disables an Active Directory user account.
    .PARAMETER SamAccountName
        Logon name of the account to disable.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot disable user" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Disable AD user account")) {
        try {
            Write-ToolkitLog -Message "Disabling AD user '$SamAccountName'" -Level WARN -Module ActiveDirectory
            $params = @{ Identity = $SamAccountName; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Disable-ADAccount @params

            Write-ToolkitLog -Message "AD user '$SamAccountName' disabled successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Status = "Disabled" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to disable AD user '$SamAccountName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Enable-ADUserAccount {
    <#
    .SYNOPSIS
        Enables a previously disabled Active Directory user account.
    .PARAMETER SamAccountName
        Logon name of the account to enable.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot enable user" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Enable AD user account")) {
        try {
            Write-ToolkitLog -Message "Enabling AD user '$SamAccountName'" -Level INFO -Module ActiveDirectory
            $params = @{ Identity = $SamAccountName; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Enable-ADAccount @params

            Write-ToolkitLog -Message "AD user '$SamAccountName' enabled successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Status = "Enabled" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to enable AD user '$SamAccountName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Unlock-ADUserAccount {
    <#
    .SYNOPSIS
        Unlocks an Active Directory user account locked out by failed logon attempts.
    .DESCRIPTION
        This is one of the single most common IT Support tickets in any
        enterprise. Worth knowing: an account locks out due to the domain's
        Account Lockout Policy (bad password attempt threshold) - this function
        clears the lock, it does not change the policy itself.
    .PARAMETER SamAccountName
        Logon name of the account to unlock.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot unlock user" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Unlock AD user account")) {
        try {
            Write-ToolkitLog -Message "Unlocking AD user '$SamAccountName'" -Level INFO -Module ActiveDirectory
            $params = @{ Identity = $SamAccountName; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Unlock-ADAccount @params

            Write-ToolkitLog -Message "AD user '$SamAccountName' unlocked successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Status = "Unlocked" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to unlock AD user '$SamAccountName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Reset-ADUserPassword {
    <#
    .SYNOPSIS
        Resets an Active Directory user's password.
    .DESCRIPTION
        Prompts interactively via Read-Host -AsSecureString - the new password
        is never stored as plaintext in a variable, printed to the console, or
        written to the log file. Only the action itself is logged, never the
        password value.
    .PARAMETER SamAccountName
        Logon name of the account.
    .PARAMETER ForceChangeAtLogon
        If set (default: true), the user must change this password on next logon.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter()] [bool]$ForceChangeAtLogon = $true,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot reset password" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, "Reset AD user password")) {
        try {
            $securePassword = Read-Host -Prompt "Enter new password for $SamAccountName" -AsSecureString

            Write-ToolkitLog -Message "Resetting password for AD user '$SamAccountName' (ForceChangeAtLogon=$ForceChangeAtLogon)" -Level WARN -Module ActiveDirectory

            $params = @{ Identity = $SamAccountName; NewPassword = $securePassword; Reset = $true; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Set-ADAccountPassword @params

            if ($ForceChangeAtLogon) {
                $expireParams = @{ Identity = $SamAccountName; ChangePasswordAtLogon = $true; ErrorAction = "Stop" }
                if ($Credential) { $expireParams["Credential"] = $Credential }
                Set-ADUser @expireParams
            }

            Write-ToolkitLog -Message "Password reset for AD user '$SamAccountName' completed successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Status = "Password reset"; ChangeAtLogon = $ForceChangeAtLogon }
        }
        catch {
            Write-ToolkitLog -Message "Failed to reset password for AD user '$SamAccountName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Add-ADUserToGroupCustom {
    <#
    .SYNOPSIS
        Adds an Active Directory user to a group.
    .PARAMETER SamAccountName
        Logon name of the user.
    .PARAMETER GroupName
        Name of the target AD group.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter(Mandatory = $true)] [string]$GroupName,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot modify group membership" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess("$SamAccountName -> $GroupName", "Add user to group")) {
        try {
            Write-ToolkitLog -Message "Adding '$SamAccountName' to group '$GroupName'" -Level INFO -Module ActiveDirectory
            $params = @{ Identity = $GroupName; Members = $SamAccountName; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Add-ADGroupMember @params

            Write-ToolkitLog -Message "'$SamAccountName' added to '$GroupName' successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Group = $GroupName; Status = "Added" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to add '$SamAccountName' to '$GroupName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Remove-ADUserFromGroupCustom {
    <#
    .SYNOPSIS
        Removes an Active Directory user from a group.
    .PARAMETER SamAccountName
        Logon name of the user.
    .PARAMETER GroupName
        Name of the AD group to remove the user from.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$SamAccountName,
        [Parameter(Mandatory = $true)] [string]$GroupName,
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot modify group membership" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    if ($PSCmdlet.ShouldProcess("$SamAccountName -> $GroupName", "Remove user from group")) {
        try {
            Write-ToolkitLog -Message "Removing '$SamAccountName' from group '$GroupName'" -Level WARN -Module ActiveDirectory
            $params = @{ Identity = $GroupName; Members = $SamAccountName; Confirm = $false; ErrorAction = "Stop" }
            if ($Credential) { $params["Credential"] = $Credential }
            Remove-ADGroupMember @params

            Write-ToolkitLog -Message "'$SamAccountName' removed from '$GroupName' successfully" -Level SUCCESS -Module ActiveDirectory
            return [PSCustomObject]@{ SamAccountName = $SamAccountName; Group = $GroupName; Status = "Removed" }
        }
        catch {
            Write-ToolkitLog -Message "Failed to remove '$SamAccountName' from '$GroupName': $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
            throw
        }
    }
}

function Get-DisabledADUsers {
    <#
    .SYNOPSIS
        Lists all disabled user accounts in the domain.
    .DESCRIPTION
        Useful both for support (find an account you disabled earlier) and for
        security auditing (v3.0 will build on this to flag stale disabled
        accounts that should be deleted, not just disabled).
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot list disabled users" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    try {
        Write-ToolkitLog -Message "Retrieving disabled AD user accounts" -Level INFO -Module ActiveDirectory
        $params = @{ Filter = "Enabled -eq `$false"; Properties = "LastLogonDate"; ErrorAction = "Stop" }
        if ($Credential) { $params["Credential"] = $Credential }

        $result = Get-ADUser @params | Select-Object SamAccountName, Name, LastLogonDate

        Write-ToolkitLog -Message "Found $($result.Count) disabled AD user(s)" -Level SUCCESS -Module ActiveDirectory
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to retrieve disabled AD users: $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
        throw
    }
}

function Get-LockedADUsers {
    <#
    .SYNOPSIS
        Lists all currently locked-out user accounts in the domain.
    .DESCRIPTION
        Wraps Search-ADAccount -LockedOut, which is the correct built-in
        cmdlet for this (much more reliable than filtering Get-ADUser on
        lockoutTime manually).
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [System.Management.Automation.PSCredential]$Credential
    )

    if (-not (Test-ADModuleAvailable)) {
        Write-ToolkitLog -Message "ActiveDirectory module not available - cannot list locked users" -Level ERROR -Module ActiveDirectory
        Write-Warning "The ActiveDirectory module (RSAT) is not installed on this machine."
        return
    }

    try {
        Write-ToolkitLog -Message "Retrieving locked-out AD user accounts" -Level INFO -Module ActiveDirectory
        $params = @{ LockedOut = $true; ErrorAction = "Stop" }
        if ($Credential) { $params["Credential"] = $Credential }

        $result = Search-ADAccount @params | Select-Object SamAccountName, Name, LockedOut, LastLogonDate

        Write-ToolkitLog -Message "Found $($result.Count) locked AD user(s)" -Level SUCCESS -Module ActiveDirectory
        return $result
    }
    catch {
        Write-ToolkitLog -Message "Failed to retrieve locked AD users: $($_.Exception.Message)" -Level ERROR -Module ActiveDirectory
        throw
    }
}

Export-ModuleMember -Function *
