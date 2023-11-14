configuration LabDomainConfig {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc

    $adminCredential = Get-AutomationPSCredential 'bootstrapadmin'
    $domain = Get-AutomationVariable -Name 'adds_domain_name'

    node $ComputerName {
        WindowsFeature 'AD-Domain-Services' {
            Name = 'AD-Domain-Services'
            Ensure = 'Present'
        }

        ADDomain 'LabDomain' {
            DomainName = $domain
            Credential = $adminCredential
            SafemodeAdministratorPassword = $adminCredential
            ForestMode = 'WinThreshold'
            DependsOn =  '[WindowsFeature]AD-Domain-Services'
        }

        DnsServerForwarder 'SetForwarders' {
            IsSingleInstance = 'Yes'
            IPAddresses = @('168.63.129.16')
            UseRootHint = $false
            DependsOn = '[ADDomain]LabDomain'
        }

        ADUser 'bootstrapadmin' {
            UserName = $adminCredential.UserName
            PasswordNeverExpires = $true
            DomainName = $domain
            DomainController = $ComputerName
            DependsOn = '[ADDomain]LabDomain'
        }
    }
}
