configuration JumpBoxConfig2 {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'xDSCDomainjoin'
    Import-DscResource -ModuleName 'cChoco'
    
    $domain = Get-AutomationVariable -Name 'adds2_domain_name'
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
    }
}
