param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$MssqlServerName,

    [Parameter(Mandatory = $true)]
    [string]$MssqlDatabaseName,

    [ValidateSet('true', 'false')]
    [string]$VerboseResults = 'false'
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
        [string]$msg,
        [string]$SanitizedMessage = 'Check result'
    )
    if ($status -ne 'SUMMARY' -and $VerboseResults -ne 'true') {
        $msg = $SanitizedMessage
    }
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
        Write-TestResult $moduleName 'PASS' ("SQL server '$MssqlServerName' exists with expected configuration (TLS 1.2, public access disabled, Entra-only auth)") -SanitizedMessage 'SQL server ''<value>'' exists with expected configuration (TLS 1.2, public access disabled, Entra-only auth)'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("SQL server '$MssqlServerName' configuration issues: " + ($issues -join '; ')) -SanitizedMessage 'SQL server ''<value>'' configuration issues: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL server '$MssqlServerName' not found or not accessible" -SanitizedMessage 'SQL server ''<value>'' not found or not accessible'
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 2: Database exists
try {
    $db = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -DatabaseName $MssqlDatabaseName -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' ("Database '$MssqlDatabaseName' exists on server '$MssqlServerName' (Status: $($db.Status))") -SanitizedMessage 'Database ''<value>'' exists on server ''<value>'' (Status: <value>)'
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Database '$MssqlDatabaseName' not found on server '$MssqlServerName'" -SanitizedMessage 'Database ''<value>'' not found on server ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
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
            Write-TestResult $moduleName 'PASS' ("Private endpoint '$($endpoints[0].Name)' is connected with status 'Approved'") -SanitizedMessage 'Private endpoint ''<value>'' is connected with status ''Approved'''
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Private endpoint '$($endpoints[0].Name)' connection status is '$status' (expected 'Approved')") -SanitizedMessage 'Private endpoint ''<value>'' connection status is ''<value>'' (expected ''Approved'')'
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "No private endpoint found for SQL server '$MssqlServerName'" -SanitizedMessage 'No private endpoint found for SQL server ''<value>'''
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private endpoints for SQL server '$MssqlServerName'" -SanitizedMessage 'Failed to query private endpoints for SQL server ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 4: Private DNS A record exists
try {
    $zoneName = 'privatelink.database.windows.net'
    $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $zoneName -RecordType A -ErrorAction Stop |
        Where-Object { $_.Name -eq $MssqlServerName }

    if ($recordSets) {
        $ip = $recordSets[0].Records[0].Ipv4Address
        Write-TestResult $moduleName 'PASS' ("Private DNS A record '$MssqlServerName.$zoneName' exists (IP: $ip)") -SanitizedMessage 'Private DNS A record ''<value>.<value>'' exists (IP: <value>)'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Private DNS A record '$MssqlServerName' not found in zone '$zoneName'" -SanitizedMessage 'Private DNS A record ''<value>'' not found in zone ''<value>'''
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query private DNS zone '$zoneName'" -SanitizedMessage 'Failed to query private DNS zone ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 5: Entra ID admin is configured as a security group
try {
    $admin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -ErrorAction Stop

    if ($admin) {
        if ($admin.DisplayName -match '^grp-') {
            Write-TestResult $moduleName 'PASS' ("Entra ID admin is group '$($admin.DisplayName)' (ObjectId: $($admin.ObjectId))") -SanitizedMessage 'Entra ID admin is group ''<value>'' (ObjectId: <value>)'
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' ("Entra ID admin '$($admin.DisplayName)' does not appear to be a security group (expected name starting with 'grp-')") -SanitizedMessage 'Entra ID admin ''<value>'' does not appear to be a security group (expected name starting with ''grp-'')'
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' 'No Entra ID administrator configured on SQL server' -SanitizedMessage 'No Entra ID administrator configured on SQL server'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to query Entra ID administrator for SQL server '$MssqlServerName'" -SanitizedMessage 'Failed to query Entra ID administrator for SQL server ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Test 6: Server-level auditing is enabled and audit events stream to Log Analytics (remediates VA2061)
try {
    $auditIssues = @()

    # Get-AzSqlServerAudit is the Azure SQL-native auditing cmdlet: LogAnalyticsTargetState
    # and WorkspaceResourceId together reflect the master-database diagnostic setting that
    # streams the SQLSecurityAuditEvents category to a Log Analytics workspace (the canonical
    # VA2061 remediation). Using it avoids Get-AzDiagnosticSetting, whose Log/Metric output
    # properties are being changed to List types in Az.Monitor 7.0.0.
    $audit = Get-AzSqlServerAudit -ResourceGroupName $ResourceGroupName -ServerName $MssqlServerName -ErrorAction Stop

    if (-not $audit -or $audit.LogAnalyticsTargetState -ne 'Enabled') {
        $auditIssues += "LogAnalyticsTargetState='$($audit.LogAnalyticsTargetState)' (expected 'Enabled')"
    }

    if (-not $audit.WorkspaceResourceId) {
        $auditIssues += 'auditing is not targeting a Log Analytics workspace (WorkspaceResourceId is empty)'
    }

    if ($auditIssues.Count -eq 0) {
        Write-TestResult $moduleName 'PASS' ("Server-level auditing is enabled and streaming 'SQLSecurityAuditEvents' to Log Analytics (remediates VA2061)") -SanitizedMessage 'Server-level auditing is enabled and streaming ''SQLSecurityAuditEvents'' to Log Analytics (remediates VA2061)'
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' ("Server-level auditing issues: " + ($auditIssues -join '; ')) -SanitizedMessage 'Server-level auditing issues: <value>'
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Failed to verify server-level auditing for SQL server '$MssqlServerName'" -SanitizedMessage 'Failed to verify server-level auditing for SQL server ''<value>'''
    Write-TestResult $moduleName 'FAIL' "Exception: $_" -SanitizedMessage 'Exception: <value>'
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
