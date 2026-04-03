param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$MysqlServerName,

    [Parameter(Mandatory = $true)]
    [string]$MysqlDatabaseName
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

$moduleName = 'mysql'

Write-Log "Starting unit tests for module '$moduleName'..."
Write-Log ("Parameters: ResourceGroupName='$ResourceGroupName' MysqlServerName='$MysqlServerName' MysqlDatabaseName='$MysqlDatabaseName'")

$passed = 0
$failed = 0

# Test 1: MySQL Flexible Server exists with expected configuration
# Note: Using Get-AzResource instead of Get-AzMySqlFlexibleServer due to bug
# https://github.com/Azure/azure-powershell/issues/29365
# Get-AzMySqlFlexibleServer reports incorrect results for NetworkPublicNetworkAccess property
try {
    # $server = Get-AzMySqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $MysqlServerName -ErrorAction Stop
    $server = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.DBforMySQL/flexibleServers' -Name $MysqlServerName -ExpandProperties -ErrorAction Stop

    $issues = @()

    if ($server.Properties.network.publicNetworkAccess -ne 'Disabled') {
        $issues += "PublicNetworkAccess='$($server.Properties.network.publicNetworkAccess)' (expected 'Disabled')"
    }

    if ($issues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("MySQL Flexible Server '$MysqlServerName' exists with expected configuration (public access disabled)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("MySQL Flexible Server '$MysqlServerName' configuration issues: " + ($issues -join '; '))
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "MySQL Flexible Server '$MysqlServerName' not found or not accessible"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: Database exists
try {
    $db = Get-AzMySqlFlexibleServerDatabase -ResourceGroupName $ResourceGroupName -ServerName $MysqlServerName -Name $MysqlDatabaseName -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' ("Database '$MysqlDatabaseName' exists on server '$MysqlServerName'")
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Database '$MysqlDatabaseName' not found on server '$MysqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 3: Private endpoint is connected and approved
try {
    $endpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object {
            $_.PrivateLinkServiceConnections | Where-Object { $_.PrivateLinkServiceId -match "Microsoft.DBforMySQL/flexibleServers/$MysqlServerName" }
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
        Write-TestResult $moduleName 'FAIL' "No private endpoint found for MySQL Flexible Server '$MysqlServerName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private endpoints for MySQL Flexible Server '$MysqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: Private DNS A record exists
try {
    $zoneName = 'privatelink.mysql.database.azure.com'
    $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $zoneName -RecordType A -ErrorAction Stop |
        Where-Object { $_.Name -eq $MysqlServerName }

    if ($recordSets) {
        $ip = $recordSets[0].Records[0].Ipv4Address
        Write-TestResult $moduleName 'PASS' ("Private DNS A record '$MysqlServerName.$zoneName' exists (IP: $ip)")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Private DNS A record '$MysqlServerName' not found in zone '$zoneName'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private DNS zone '$zoneName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: SQL auth admin is configured
try {
    $server = Get-AzMySqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $MysqlServerName -ErrorAction Stop

    if ($server.AdministratorLogin) {
        Write-TestResult $moduleName 'PASS' ("SQL auth admin login is configured (AdministratorLogin: '$($server.AdministratorLogin)')")
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' 'No administrator login configured on MySQL Flexible Server'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query administrator login for MySQL Flexible Server '$MysqlServerName'"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
