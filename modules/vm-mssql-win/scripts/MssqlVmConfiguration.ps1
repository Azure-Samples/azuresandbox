configuration MssqlVmConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'xDSCDomainjoin'
    Import-DscResource -ModuleName 'NetworkingDsc'
    Import-DscResource -ModuleName 'SqlServerDsc'
    Import-DscResource -ModuleName 'ActiveDirectoryDsc'
    
    $domain = Get-AutomationVariable -Name 'adds_domain_name'
    $localAdminCredential = Get-AutomationPSCredential 'bootstrapadmin'
    $domainAdminCredential = Get-AutomationPSCredential 'domainadmin'
    $domainAdminShortCredential = Get-AutomationPSCredential 'domainadminshort'

    node $ComputerName {
        xDSCDomainjoin 'JoinDomain' {
            Domain = $domain
            Credential = $domainAdminCredential
        }

        Firewall 'MssqlFirewallRule' {
            Name = 'MssqlFirewallRule'
            DisplayName = 'Microsoft SQL Server database engine.'
            Ensure = 'Present'
            Enabled = 'True'
            Profile = ('Domain', 'Private')
            Direction = 'InBound'
            LocalPort = ('1433')
            Protocol = 'TCP'
            DependsOn = '[xDSCDomainjoin]JoinDomain'
        }

        SqlLogin 'DomainAdmin' {
            Name = $domainAdminShortCredential.UserName
            LoginType = 'WindowsUser'
            InstanceName = 'MSSQLSERVER'
            Ensure = 'Present'
            DependsOn = '[xDSCDomainjoin]JoinDomain'
            PSDscRunAsCredential = $localAdminCredential
        }

        SqlRole 'sysadmin' {
            ServerRoleName = 'sysadmin'
            MembersToInclude = $domainAdminShortCredential.UserName
            InstanceName = 'MSSQLSERVER'
            Ensure = 'Present'
            DependsOn = '[SqlLogin]DomainAdmin'
            PSDscRunAsCredential = $localAdminCredential
        }

        WindowsFeature 'RSAT-AD-PowerShell' {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
            DependsOn = '[xDSCDomainjoin]JoinDomain'            
        }

        ADGroup 'DatabaseServers' {
            GroupName = 'DatabaseServers'
            GroupScope = 'Global'
            Category = 'Security'
            MembersToInclude = "$ComputerName$"
            Credential = $domainAdminCredential
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]RSAT-AD-PowerShell'            
        }
    }
}
