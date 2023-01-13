configuration JumpBoxConfig {
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

        WindowsFeature 'RSAT-ADDS' {
            Name = 'RSAT-ADDS'
            Ensure = 'Present'
            DependsOn = '[xDSCDomainjoin]JoinDomain'            
        }

        WindowsFeature 'RSAT-DNS-Server' {
            Name = 'RSAT-DNS-Server'
            Ensure = 'Present'
            DependsOn = '[xDSCDomainjoin]JoinDomain' 
        }

        ADGroup 'JumpBoxes' {
            GroupName = 'JumpBoxes'
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

        cChocoPackageInstaller 'Edge' {
            Name = 'microsoft-edge'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'AzPowerShell' {
            Name = 'az.powershell'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'VSCode' {
            Name = 'vscode'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'SSMS' {
            Name = 'sql-server-management-studio'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'AzureStorageExplorer' {
            Name = 'microsoftazurestorageexplorer'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'AzCopy' {
            Name = 'azcopy10'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'AzureDataStudio' {
            Name = 'azure-data-studio'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'MySQLWorkbench' {
            Name = 'mysql.workbench'
            DependsOn = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }
    }
}
