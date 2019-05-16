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
        if ( -not ($_ -match "[a-z0-9\-\.]") ) {
            Throw "DNSSuffix can contain only alphabetical characters (A-Z), numeric characters (0-9), the minus sign (-), and the period (.). Period characters are allowed only when they are used to delimit the components of domain style names."
        }
        if ( -not ([regex]::Matches($_, "[a-z0-9\-]" ).count -le 2) ) {
            Throw "This script only supports DNSSuffix that contains one or two periods (.)"
        }
        return true
    })]    
    [String] $DNSSuffix,

    # Domain Safe Mode Admin Pasword
    [Parameter(Mandatory=$true)]
    [System.Security.SecureString] $SafeModeAdministratorPassword,

    # Create a default OU Structure
    [Parameter]
    [Switch] $CreateDomainOU
)

Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

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

$domain = Get-ADDomain $NetBIOS

if ($CreateDomainOU) {
    $dn = $domain.DistinguishedName

    New-ADOrganizationalUnit -Name "$NetBIOS People" -Path $dn
    New-ADOrganizationalUnit -Name "$NetBIOS Groups" -Path $dn
    New-ADOrganizationalUnit -Name "$NetBIOS Computers" -Path $dn

    New-ADOrganizationalUnit -Name "Admins" -Path "OU=$NetBIOS People,$dn"

    New-ADOrganizationalUnit -Name "Security" -Path "OU=$NetBIOS Groups,$dn"
    New-ADOrganizationalUnit -Name "Distribution" -Path "OU=$NetBIOS Groups,$dn"

    New-ADOrganizationalUnit -Name "Servers" -Path "OU=$NetBIOS Computers,$dn"
}