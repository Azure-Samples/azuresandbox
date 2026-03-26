#region functions
function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

function Exit-WithError {
    param( [string]$msg )
    Write-ScriptLog "There was an exception during the process, please review..."
    Write-ScriptLog $msg
    Exit 2
}
#endregion

#region main
Write-ScriptLog "Running '$PSCommandPath'..."

# Configure Windows Firewall rule for SQL Server (TCP 1433)
Write-ScriptLog "Configuring Windows Firewall rule for SQL Server (TCP 1433)..."

$existingRule = Get-NetFirewallRule -Name 'MssqlFirewallRule' -ErrorAction SilentlyContinue

if ($null -eq $existingRule) {
    try {
        New-NetFirewallRule `
            -Name 'MssqlFirewallRule' `
            -DisplayName 'Microsoft SQL Server database engine.' `
            -Enabled True `
            -Profile @('Domain', 'Private') `
            -Direction Inbound `
            -LocalPort 1433 `
            -Protocol TCP `
            -Action Allow `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Exit-WithError $_
    }
}
else {
    Write-ScriptLog "Firewall rule 'MssqlFirewallRule' already exists."
}

# Enable Windows Firewall groups
$firewallGroups = @(
    'Windows Management Instrumentation (WMI)',
    'Remote Service Management'
)

foreach ($group in $firewallGroups) {
    Write-ScriptLog "Enabling firewall group '$group'..."
    $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue

    if ($null -ne $rules -and @($rules).Count -gt 0) {
        $rules | Enable-NetFirewallRule -ErrorAction Stop
        Write-ScriptLog "Firewall group '$group' enabled ($(@($rules).Count) rules)."
    }
    else {
        Write-ScriptLog "Firewall group '$group' not found on this image, skipping."
    }
}

# Create RPC firewall rules to allow remote SQL Server service management from SSMS
$rpcRules = @(
    @{
        Name        = 'RPC-Endpoint-Mapper-In'
        DisplayName = 'RPC Endpoint Mapper (Inbound)'
        LocalPort   = '135'
        Program     = '%SystemRoot%\system32\svchost.exe'
    }
    @{
        Name        = 'RPC-Dynamic-Ports-In'
        DisplayName = 'RPC Dynamic Ports (Inbound)'
        LocalPort   = 'RPC'
        Program     = '%SystemRoot%\system32\services.exe'
    }
)

foreach ($rpcRule in $rpcRules) {
    $existing = Get-NetFirewallRule -Name $rpcRule.Name -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-ScriptLog "Creating firewall rule '$($rpcRule.Name)'..."
        New-NetFirewallRule `
            -Name $rpcRule.Name `
            -DisplayName $rpcRule.DisplayName `
            -Group 'Remote Procedure Call' `
            -Enabled True `
            -Profile @('Domain', 'Private') `
            -Direction Inbound `
            -LocalPort $rpcRule.LocalPort `
            -Protocol TCP `
            -Program $rpcRule.Program `
            -Action Allow `
            -ErrorAction Stop | Out-Null
    }
    else {
        Write-ScriptLog "Firewall rule '$($rpcRule.Name)' already exists."
    }
}

Write-ScriptLog "'$PSCommandPath' completed successfully."
Exit 0
#endregion
