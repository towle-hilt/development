param(
    # Domain name (DOMAIN)
    [Parameter(Mandatory=$True)]
    [ValidateScript({
        if ( -not ($_ -match "[A-Za-z0-9]{1,15}")) {
            Throw "This script only supports NetBIOS names between 1 and 15 characters in length and must only contain letters and numbers."
        }
        return $true
    })]
    [String] $NetBIOS,

    # Domain DNS suffix (domain.com)
    [Parameter(Mandatory=$True)]
    [ValidateScript({
        $array = $_.Split(".")

        # does the array not contain two or three items?
        if ( -not ($array.count -in 2,3) ) {
            Throw "This script only supports DNSSuffix that contains one or two periods (domain.com or internal.domain.com)"
        }

        # for each part of array, does it contain non-word characters?
        if ( ($array | ForEach-Object { $_ -match "\W" }) -contains $True ) {
            Throw "DNSSuffix can contain only alphabetical characters (A-Z), numeric characters (0-9), the hyphen (-)."
        }

        return true
    })]
    [String] $DNSSuffix,

    # SafeModeAdministratorPassword
    [Parameter(Mandatory=$False)]
    [System.Security.SecureString] $SafeModeAdministratorPassword

)

begin {

    function new-Password {
        param (
            [Parameter(Mandator)]
            [switch]$Interactive
        )

        $password = [system.web.security.membership]::GeneratePassword(8,2)

        if ($Interactive) {
            Write-Host "`nNew password created:`n`n      $password`n"
            Set-Clipboard -Value $password
            Write-Host "This password has been added to your clipboard.`n"

            while ($response -ne "continue") {
                $response = Read-Host -Prompt "Type 'continue' when you are ready to continue"
            } 
            
            Write-Host "Confirmed, lets continue..."
            Start-Sleep -Seconds 2
        }

        $password = ConvertTo-SecureString -String $password -AsPlainText -Force

        return $password
    }

    # If needed, create SafeModeAdministratorPassword
    if (-not $SafeModeAdministratorPassword) { new-Password -Interactive }
    
    # Install AD Features
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

}

process {

    Write-Verbose "[DOMAIN] Initiating domain setup process."

    if ( -not (Get-ADDomain $NetBIOS) ) {
        Install-ADDSForest `
            -CreateDnsDelegation:$false `
            -DomainMode WinThreshold `
            -DomainName $DNSSuffix `
            -DomainNetbiosName $NetBIOS `
            -ForestMode WinThreshold `
            -InstallDns:$true `
            -NoRebootOnCompletion:$true `
            -SafeModeAdministratorPassword $SafeModeAdministratorPassword `
            -Force:$true
    }

    Write-Verbose "[DOMAIN] ... Domain installed."

    # confirm that the necessary services are running
    $services = "adws","dns","kdc","netlogon"
    $services = Get-Service | Where-Object { $services -contains $_.Name -and $_.Status -eq 'Running' }

    if ( -not ($services.count -eq 4) ) {
        Write-Verbose "[ERROR] Unable to detect running domain services"
        Write-Verbose "`n $services"
        Throw "Unable to detect running Domain Servivces, please reboot."
    }

    $domain = Get-ADDomain $NetBIOS
    $dn = $domain.DistinguishedName

    # create ou structure
    Write-Verbose "[OU] Setup organizational units"

    "People","Groups","Computers","Servers" | ForEach-Object {
        New-ADOrganizationalUnit -Name "$NetBIOS $_" -Path $dn
        Write-Verbose "[OU] ... Created OU $_"        
    }

    New-ADOrganizationalUnit -Name "Admins" -Path "OU=$NetBIOS People,$dn"
    Write-Verbose "[OU] ... Created OU Admins"

    "Security","Role","Distribution" | ForEach-Object {
        New-ADOrganizationalUnit -Name $_ -Path "OU=$NetBIOS Groups,$dn"
        Write-Verbose "[OU] ... Created OU $_"
    }

    # create initial groups
    Write-Verbose "[Groups] Setup initial groups"
    New-ADGroup -Name "sg._svc.$Netbios DomainAdmin" -SamAccountName "sg._svc.$Netbios DomainAdmin" -GroupCategory Security -GroupScope Global -DisplayName "sg._svc.$Netbios DomainAdmin" -Path "OU=Security,OU=$NetBIOS Groups,$dn" -Description "$NetBios Domain Administrator"

}
