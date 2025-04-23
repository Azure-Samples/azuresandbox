configuration JumpBoxConfig2 {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'xDSCDomainjoin'
    Import-DscResource -ModuleName 'ActiveDirectoryDsc'
    Import-DscResource -ModuleName 'cChoco'
    
    $domain = Get-AutomationVariable -Name 'adds2_domain_name'
    $domainAdminCredential = Get-AutomationPSCredential 'domainadmin'

    node $ComputerName {
        WindowsFeature 'RSAT-AD-PowerShell' {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        WindowsFeature 'RSAT-ADDS' {
            Name = 'RSAT-ADDS'
            Ensure = 'Present'
        }

        WindowsFeature 'RSAT-DNS-Server' {
            Name = 'RSAT-DNS-Server'
            Ensure = 'Present'
        }

        cChocoInstaller 'Chocolatey' {
            InstallDir = 'c:\choco'
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

        xDSCDomainjoin 'JoinDomain' {
            Domain = $domain
            Credential = $domainAdminCredential
            DependsOn = '[WindowsFeature]RSAT-AD-PowerShell' 
        }
    }
}
