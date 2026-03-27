#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$Domain,

    [Parameter(Mandatory = $true)]
    [String]$AdminUsername,

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
