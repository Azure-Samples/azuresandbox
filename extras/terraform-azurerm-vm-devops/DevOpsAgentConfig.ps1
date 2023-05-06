configuration DevOpsAgentConfig {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'xDSCDomainjoin'
    Import-DscResource -ModuleName 'ActiveDirectoryDsc'
    Import-DscResource -ModuleName 'cChoco'
    
    $domain = Get-AutomationVariable -Name 'adds_domain_name'
    $domainAdminCredential = Get-AutomationPSCredential 'domainadmin'

    node $ComputerName {
        xDSCDomainjoin 'JoinDomain' {
            Domain = $domain
            Credential = $domainAdminCredential
        }

        WindowsFeature 'RSAT-AD-PowerShell' {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
            DependsOn = '[xDSCDomainjoin]JoinDomain'            
        }

        ADGroup 'DevOpsAgents' {
            GroupName = 'DevOpsAgents'
            GroupScope = 'Global'
            Category = 'Security'
            MembersToInclude = "$ComputerName$"
            Credential = $domainAdminCredential
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]RSAT-AD-PowerShell'            
        }

        cChocoInstaller 'Chocolatey' {
            InstallDir = 'c:\choco'
            DependsOn = '[xDSCDomainjoin]JoinDomain'
        }

        cChocoPackageInstaller 'VSCode' {
            Name = 'vscode'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'microsoft-build-tools' {
            Name = 'microsoft-build-tools'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'svn' {
            Name = 'svn'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }
    }
}
