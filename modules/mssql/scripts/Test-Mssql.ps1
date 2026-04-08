param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$MssqlServerName,

    [Parameter(Mandatory = $true)]
    [string]$MssqlDatabaseName
)

#region functions
function Write-Log {
    param([string]$msg)
    Write-Output "$(Get-Date -Format FileDateTimeUniversal) : $msg"
}

function Write-TestResult {
    param(
        [string]$module,
        [string]$status,
        [string]$msg
    )
    Write-Log ("[MODULE:$module] [$status] $msg")
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'mssql'

Write-Log "Starting unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' MssqlServerName='$MssqlServerName' MssqlDatabaseName='$MssqlDatabaseName'")

$passed = 0
$failed = 0

# Test 1: SQL server exists with expected configuration
try {
    $server = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -ErrorAction Stop

    $issues = @()

    if ($server.MinimalTlsVersion -ne '1.2') {
        $issues += "MinimalTlsVersion='$($server.MinimalTlsVersion)' (expected '1.2')"
    }

    if ($server.PublicNetworkAccess -ne 'Disabled') {
        $issues += "PublicNetworkAccess='$($server.PublicNetworkAccess)' (expected 'Disabled')"
    }

    if (-not $server.Administrators -or -not $server.Administrators.AzureAdOnlyAuthentication) {
        $issues += 'Entra-only authentication not enabled'
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("SQL server '$MssqlServerName' exists with expected configuration (TLS 1.2, public access disabled, Entra-only auth)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("SQL server '$MssqlServerName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL server '$MssqlServerName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Database exists
try {
    $db = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -DatabaseName $MssqlDatabaseName -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' ("Database '$MssqlDatabaseName' exists on server '$MssqlServerName' (Status: $($db.Status))")
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Database '$MssqlDatabaseName' not found on server '$MssqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: Private endpoint is connected and approved
try {
    $endpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object {
            $_.PrivateLinkServiceConnections | Where-Object { $_.PrivateLinkServiceId -match "Microsoft.Sql/servers/$MssqlServerName" }
        }

    if ($endpoints) {
        $connection = $endpoints[0].PrivateLinkServiceConnections[0]
        $status = $connection.PrivateLinkServiceConnectionState.Status

        if ($status -eq 'Approved') {
            Write-TestResult $moduleName 'PASS' ("Private endpoint '$($endpoints[0].Name)' is connected with status 'Approved'")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Private endpoint '$($endpoints[0].Name)' connection status is '$status' (expected 'Approved')")
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No private endpoint found for SQL server '$MssqlServerName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private endpoints for SQL server '$MssqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Private DNS A record exists
try {
    $zoneName = 'privatelink.database.windows.net'
    $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $zoneName -RecordType A -ErrorAction Stop |
        Where-Object { $_.Name -eq $MssqlServerName }

    if ($recordSets) {
        $ip = $recordSets[0].Records[0].Ipv4Address
        Write-TestResult $moduleName 'PASS' ("Private DNS A record '$MssqlServerName.$zoneName' exists (IP: $ip)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Private DNS A record '$MssqlServerName' not found in zone '$zoneName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private DNS zone '$zoneName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: Entra ID admin is configured as a security group
try {
    $admin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -ErrorAction Stop

    if ($admin) {
        if ($admin.DisplayName -match '^grp-') {
            Write-TestResult $moduleName 'PASS' ("Entra ID admin is group '$($admin.DisplayName)' (ObjectId: $($admin.ObjectId))")
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Entra ID admin '$($admin.DisplayName)' does not appear to be a security group (expected name starting with 'grp-')")
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' 'No Entra ID administrator configured on SQL server'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query Entra ID administrator for SQL server '$MssqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
