#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$Domain,

    [Parameter(Mandatory = $true)]
    [String]$AdminUsername,

    # Note: This parameter is passed from Terraform as a protected parameter. The value is encrypted in transit to the VM via the Azure API and is not logged.
    [Parameter(Mandatory = $true)]
    [String]$AdminPwd, 

    [Parameter(Mandatory = $true)]
    [String]$ComputerName
)
#endregion

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

# Install AD DS feature
Write-Log "Installing AD-Domain-Services Windows feature..."

try {
    $result = Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Log "Feature installation result: Success=$($result.Success), RestartNeeded=$($result.RestartNeeded)"
}
catch {
    Exit-WithError $_
}

# Check if AD forest already exists
Write-Log "Checking if AD forest already exists..."

try {
    Import-Module ADDSDeployment -ErrorAction Stop
    $existingForest = Get-ADForest -ErrorAction Stop
    Write-Log "AD forest '$($existingForest.Name)' already exists. Skipping forest creation."
}
catch {
    Write-Log "No existing AD forest found. Creating AD forest for domain '$Domain'..."

    $securePassword = ConvertTo-SecureString $AdminPwd -AsPlainText -Force

    try {
        Install-ADDSForest `
            -DomainName $Domain `
            -SafeModeAdministratorPassword $securePassword `
            -DomainMode 'WinThreshold' `
            -ForestMode 'WinThreshold' `
            -InstallDns `
            -NoRebootOnCompletion `
            -Force `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "AD forest created. Scheduling reboot in 30 seconds..."
    & shutdown /r /t 30 /c "Rebooting to complete AD DS domain controller promotion"
}

Write-Log "Phase 1 complete."
Exit 0
#endregion
