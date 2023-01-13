configuration MssqlVmConfig {
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
        SqlScriptQuery 'EnableSa' {
            InstanceName = 'MSSQLSERVER'
            GetQuery = @'
SELECT [is_disabled] FROM [master].[sys].[sql_logins] WHERE ([name] = 'sa') FOR JSON AUTO;
GO
'@
            TestQuery = @'
IF (SELECT [is_disabled] FROM [master].[sys].[sql_logins] WHERE ([name] = 'sa')) = 1 
BEGIN
    RAISERROR ('sa login is disabled.', 16, 1 ) ;
END
ELSE
BEGIN
    PRINT 'sa login is enabled' ;
END ;
GO
'@
            SetQuery = @'
ALTER LOGIN sa ENABLE ;
GO
ALTER LOGIN sa WITH PASSWORD = '$(UsernameSecret)' ;
GO
USE [master]
GO
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', 
     N'Software\Microsoft\MSSQLServer\MSSQLServer',
     N'LoginMode', REG_DWORD, 2 ;
GO
'@
            Variable = @(
                ('UsernameSecret={0}' -f $localAdminCredential.GetNetworkCredential().Password)
            )

            QueryTimeout = 30
            PSDscRunAsCredential = $localAdminCredential
        }

        xDSCDomainjoin 'JoinDomain' {
            Domain = $domain
            Credential = $domainAdminCredential
            DependsOn = '[SqlScriptQuery]EnableSa'
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
