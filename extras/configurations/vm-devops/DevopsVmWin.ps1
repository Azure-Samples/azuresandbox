configuration DevopsVmWin {
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

        cChocoInstaller 'Chocolatey' {
            InstallDir = 'c:\choco'
            DependsOn = '[xDSCDomainjoin]JoinDomain'
        }

		cChocoPackageInstaller 'VSCode' {
            Name        = 'vscode'
            DependsOn   = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }

        cChocoPackageInstaller 'SSMS' {
            Name        = 'sql-server-management-studio'
            DependsOn   = '[cChocoInstaller]Chocolatey'
            AutoUpgrade = $true
        }
    }
}
