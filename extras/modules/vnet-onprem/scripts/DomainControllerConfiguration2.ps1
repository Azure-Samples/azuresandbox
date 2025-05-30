configuration DomainControllerConfiguration2 {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc

    $adminCredential = Get-AutomationPSCredential 'bootstrapadmin'
    $domain = Get-AutomationVariable -Name 'adds2_domain_name'
    $dnsResolverCloud = Get-AutomationVariable -Name 'dns_resolver_cloud'

    node $ComputerName {
        WindowsFeature 'AD-Domain-Services' {
            Name = 'AD-Domain-Services'
            Ensure = 'Present'
        }

        ADDomain 'Domain' {
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
            DependsOn = '[ADDomain]Domain'
        }

        DnsServerConditionalForwarder 'SandboxDomainForwarder' {
            Name = 'mysandbox.local'
            MasterServers = @("$dnsResolverCloud")
            DependsOn = '[ADDomain]Domain'
        }

        DnsServerConditionalForwarder 'AzureFiles' {
            Name = 'file.core.windows.net'
            MasterServers = @("$dnsResolverCloud")
            DependsOn = '[ADDomain]Domain'
        }

        DnsServerConditionalForwarder 'AzureSqlDb' {
            Name = 'database.windows.net'
            MasterServers = @("$dnsResolverCloud")
            DependsOn = '[ADDomain]Domain'
        }

        DnsServerConditionalForwarder 'AzureMySQLFlexServer' {
            Name = 'mysql.database.azure.com'
            MasterServers = @("$dnsResolverCloud")
            DependsOn = '[ADDomain]Domain'
        }
    }
}
