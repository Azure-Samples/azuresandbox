configuration VmDevopsWinConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ComputerName
    )

    Import-DscResource -ModuleName 'PSDscResources'
    Import-DscResource -ModuleName 'ComputerManagementDsc'
    Import-DscResource -ModuleName 'cChoco'
    
    $domain = Get-AutomationVariable -Name 'adds_domain_name'
    $domainAdminCredential = Get-AutomationPSCredential 'domainadmin'

        node $ComputerName {
        WindowsFeature RsatAdds {
            Name = 'RSAT-ADDS'
            Ensure = 'Present'
        }

        WindowsFeature RsatDns {
            Name = 'RSAT-DNS-Server'
            Ensure = 'Present'
        }

        cChocoInstaller InstallChoco {
            InstallDir = 'c:\choco'
        }

        cChocoPackageInstallerSet DeveloperTools {
            Ensure = 'Present'
            Name = @(
                "az.powershell"
                "mysql.workbench"
                "sql-server-management-studio"
                "vscode"
            )
            DependsOn = '[cChocoInstaller]InstallChoco'
        }

        # Custom Script to Wait for Software Installation
        Script WaitForSoftware {
            GetScript = {
                @{
                    Result = (Get-Module -Name Az -ListAvailable | Where-Object { $_.Name -eq 'Az' })
                }
            }
            TestScript = {
                (Get-Module -Name Az -ListAvailable | Where-Object { $_.Name -eq 'Az' }) -ne $null
            }
            SetScript = {
                Write-Verbose "Waiting for the Az PowerShell module to be installed on Windows PowerShell..."
            }
            DependsOn = "[cChocoPackageInstallerSet]DeveloperTools"
        }

        Computer JoinDomain {
            Name = $ComputerName
            DomainName = $domain
            Credential = $domainAdminCredential
            DependsOn = '[Script]WaitForSoftware'
        }

        # Force a reboot if required
        PendingReboot RebootAfterDomainJoin {
            Name = 'DomainJoin'
            DependsOn = '[Computer]JoinDomain'
        }
    }
}
