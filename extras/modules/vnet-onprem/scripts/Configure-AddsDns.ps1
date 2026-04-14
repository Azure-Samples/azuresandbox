#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$Domain,

    [Parameter(Mandatory = $true)]
    [String]$AdminUsername,

    [Parameter(Mandatory = $true)]
    [String]$ComputerName,

    [Parameter(Mandatory = $true)]
    [String]$DnsResolverCloud,

    [Parameter(Mandatory = $true)]
    [String]$AddsDomainNameCloud
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

Import-Module ActiveDirectory -ErrorAction Stop

# Configure DNS forwarder to Azure DNS
Write-Log "Configuring DNS forwarder..."

try {
    Set-DnsServerForwarder -IPAddress @('168.63.129.16') -UseRootHint $false -ErrorAction Stop
    Write-Log "DNS forwarder set to 168.63.129.16 with UseRootHint disabled."
}
catch {
    Exit-WithError "Failed to set DNS forwarder: $_"
}

# Configure conditional forwarders
$conditionalForwarders = @(
    @{ Name = $AddsDomainNameCloud; Description = "Cloud sandbox domain" },
    @{ Name = "file.core.windows.net"; Description = "Azure Files" },
    @{ Name = "database.windows.net"; Description = "Azure SQL Database" },
    @{ Name = "mysql.database.azure.com"; Description = "Azure MySQL Flexible Server" }
)

foreach ($forwarder in $conditionalForwarders) {
    Write-Log "Configuring conditional forwarder for '$($forwarder.Name)' -> $DnsResolverCloud ($($forwarder.Description))..."

    try {
        # Remove existing forwarder if it exists, then recreate
        $existing = Get-DnsServerZone -Name $forwarder.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "Removing existing conditional forwarder for '$($forwarder.Name)'..."
            Remove-DnsServerZone -Name $forwarder.Name -Force -ErrorAction Stop
        }

        Add-DnsServerConditionalForwarderZone -Name $forwarder.Name -MasterServers @($DnsResolverCloud) -ErrorAction Stop
        Write-Log "Conditional forwarder for '$($forwarder.Name)' configured successfully."
    }
    catch {
        Exit-WithError "Failed to configure conditional forwarder for '$($forwarder.Name)': $_"
    }
}

# Configure admin user
try {
    Set-ADUser -Identity $AdminUsername -PasswordNeverExpires $true -ErrorAction Stop
    Write-Log "Admin user '$AdminUsername' configured with PasswordNeverExpires."
}
catch {
    Exit-WithError "Failed to configure admin user: $_"
}

Write-Log "Phase 2 complete."
Exit 0
#endregion
