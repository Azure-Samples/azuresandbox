configuration MssqlVmConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'ComputerManagementDsc'
    Import-DscResource -ModuleName 'NetworkingDsc'
    Import-DscResource -ModuleName 'SqlServerDsc'
    
    $domain = Get-AutomationVariable -Name 'adds_domain_name'
    $localAdminCredential = Get-AutomationPSCredential 'bootstrapadmin'
    $domainAdminCredential = Get-AutomationPSCredential 'domainadmin'
    $domainAdminShortCredential = Get-AutomationPSCredential 'domainadminshort'

    node $ComputerName {
        Computer JoinDomain {
            Name = $ComputerName
            DomainName = $domain
            Credential = $domainAdminCredential
        }

        Firewall MssqlFirewallRule {
            Name = 'MssqlFirewallRule'
            DisplayName = 'Microsoft SQL Server database engine.'
            Ensure = 'Present'
            Enabled = 'True'
            Profile = ('Domain', 'Private')
            Direction = 'InBound'
            LocalPort = ('1433')
            Protocol = 'TCP'
            DependsOn = '[Computer]JoinDomain'
        }

        SqlLogin DomainAdmin {
            Name = $domainAdminShortCredential.UserName
            LoginType = 'WindowsUser'
            InstanceName = 'MSSQLSERVER'
            Ensure = 'Present'
            DependsOn = '[Computer]JoinDomain'
            PSDscRunAsCredential = $localAdminCredential
        }

        SqlRole SysAdminRole {
            ServerRoleName = 'sysadmin'
            MembersToInclude = $domainAdminShortCredential.UserName
            InstanceName = 'MSSQLSERVER'
            Ensure = 'Present'
            DependsOn = '[SqlLogin]DomainAdmin'
            PSDscRunAsCredential = $localAdminCredential
        }
    }
}
