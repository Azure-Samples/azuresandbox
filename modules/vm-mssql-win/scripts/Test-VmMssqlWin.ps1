param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName
)

#region functions
function Write-Log {
    param([string]$msg)
    $entry = "$(Get-Date -Format FileDateTimeUniversal) : $msg"
    $entry | Out-File -FilePath $script:logPath -Append -Force
    Write-Output $entry
}

function Write-TestResult {
    param(
        [string]$module,
        [string]$status,
        [string]$msg
    )
    Write-Log ("[MODULE:$module] [$status] $msg")
}

function Invoke-SqlQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $cxnString = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $cxnString.'Data Source' = 'localhost'
    $cxnString.'Initial Catalog' = 'master'
    $cxnString.'Integrated Security' = $true
    $cxnString.'Encrypt' = $true
    $cxnString.'TrustServerCertificate' = $true

    $cxn = New-Object System.Data.SqlClient.SqlConnection($cxnString.ConnectionString)
    $cxn.Open()

    $cmd = $cxn.CreateCommand()
    $cmd.CommandText = $Query

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dataSet = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $cxn.Close()
    return $dataSet.Tables[0]
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'vm-mssql-win'
$logDir = "C:\unit-tests\$moduleName"
$script:logPath = Join-Path $logDir 'Test-VmMssqlWin.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting unit tests for module '$moduleName' on '$env:COMPUTERNAME'..."
Write-Log "Parameters: KeyVaultName='$KeyVaultName'"

$passed = 0
$failed = 0
$domainName = $null
$adminUsername = $null
$adminPassword = $null

# Discover domain name from this machine
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $domainName = $cs.Domain
    Write-Log "Detected domain: '$domainName'"
}
catch {
    Write-Log "WARNING: Could not detect domain name via CIM: $_"
}

# Retrieve domain admin credentials from Key Vault via managed identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $adminUsername = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminuser' -AsPlainText -ErrorAction Stop
    $adminPassword = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminpassword' -AsPlainText -ErrorAction Stop
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Retrieved admin credentials from Key Vault '$KeyVaultName' (user='$adminUsername')"
}
catch {
    Write-Log "WARNING: Failed to retrieve admin credentials from Key Vault '$KeyVaultName': $_"
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# Test 1: Domain joined
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PartOfDomain) {
        Write-TestResult $moduleName 'PASS' "AD: '$env:COMPUTERNAME' is domain joined to '$($cs.Domain)'"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "AD: '$env:COMPUTERNAME' is not domain joined"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "AD: Failed to query domain membership"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 2: DNS - Resolve this VM's FQDN
if ($domainName) {
    try {
        $fqdn = "$env:COMPUTERNAME.$domainName"
        $dnsResult = Resolve-DnsName $fqdn -ErrorAction Stop
        $ip = ($dnsResult | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
        Write-TestResult $moduleName 'PASS' "DNS: '$fqdn' resolves to '$ip'"
        $passed++
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "DNS: '$fqdn' does not resolve"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "DNS: Skipped - domain name not available"
    $failed++
}

# Test 3: SQL Server data disk (M: drive) present
$sqlDataDrive = 'M'
try {
    $volume = Get-Volume -DriveLetter $sqlDataDrive -ErrorAction Stop
    if ($volume.FileSystemLabel -match 'sqldata') {
        Write-TestResult $moduleName 'PASS' "Disk: SQL Server data disk '$($sqlDataDrive):' present (label: '$($volume.FileSystemLabel)', size: $([math]::Round($volume.Size / 1GB, 1)) GB)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Disk: '$($sqlDataDrive):' exists but label '$($volume.FileSystemLabel)' does not contain 'sqldata'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Disk: SQL Server data disk '$($sqlDataDrive):' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 4: SQL Server log disk (L: drive) present
$sqlLogDrive = 'L'
try {
    $volume = Get-Volume -DriveLetter $sqlLogDrive -ErrorAction Stop
    if ($volume.FileSystemLabel -match 'sqllog') {
        Write-TestResult $moduleName 'PASS' "Disk: SQL Server log disk '$($sqlLogDrive):' present (label: '$($volume.FileSystemLabel)', size: $([math]::Round($volume.Size / 1GB, 1)) GB)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Disk: '$($sqlLogDrive):' exists but label '$($volume.FileSystemLabel)' does not contain 'sqllog'"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Disk: SQL Server log disk '$($sqlLogDrive):' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 5: SQL Server service is running
try {
    $sqlService = Get-Service -Name MSSQLSERVER -ErrorAction Stop
    if ($sqlService.Status -eq 'Running') {
        Write-TestResult $moduleName 'PASS' "SQL Service: MSSQLSERVER is running"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "SQL Service: MSSQLSERVER status is '$($sqlService.Status)' (expected 'Running')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL Service: MSSQLSERVER service not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 6: SQL Server Agent service is running
try {
    $agentService = Get-Service -Name SQLSERVERAGENT -ErrorAction Stop
    if ($agentService.Status -eq 'Running') {
        Write-TestResult $moduleName 'PASS' "SQL Service: SQLSERVERAGENT is running"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "SQL Service: SQLSERVERAGENT status is '$($agentService.Status)' (expected 'Running')"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL Service: SQLSERVERAGENT service not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 7: SQL Server connectivity - can execute a query
$sqlConnected = $false
try {
    $result = Invoke-SqlQuery -Query "SELECT @@SERVERNAME AS ServerName, @@VERSION AS ServerVersion"
    $serverName = $result.ServerName
    $sqlConnected = $true
    Write-TestResult $moduleName 'PASS' "SQL Connectivity: Connected to SQL Server instance '$serverName'"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL Connectivity: Failed to connect to SQL Server on localhost"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 8: SQL Server default data directory is on M: drive
if ($sqlConnected) {
    try {
        $result = Invoke-SqlQuery -Query "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DefaultDataPath"
        $defaultDataPath = $result.DefaultDataPath.TrimEnd('\')

        if ($defaultDataPath -like "${sqlDataDrive}:\*") {
            Write-TestResult $moduleName 'PASS' "SQL Config: Default data directory is '$defaultDataPath'"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "SQL Config: Default data directory is '$defaultDataPath' (expected on '$($sqlDataDrive):')"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "SQL Config: Failed to query default data directory"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "SQL Config: Skipped default data directory check - SQL not connected"
    $failed++
}

# Test 9: SQL Server default log directory is on L: drive
if ($sqlConnected) {
    try {
        $result = Invoke-SqlQuery -Query "SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS DefaultLogPath"
        $defaultLogPath = $result.DefaultLogPath.TrimEnd('\')

        if ($defaultLogPath -like "${sqlLogDrive}:\*") {
            Write-TestResult $moduleName 'PASS' "SQL Config: Default log directory is '$defaultLogPath'"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "SQL Config: Default log directory is '$defaultLogPath' (expected on '$($sqlLogDrive):')"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "SQL Config: Failed to query default log directory"
        Write-TestResult $moduleName 'FAIL' "Exception: $_"
        $failed++
    }
}
else {
    Write-TestResult $moduleName 'FAIL' "SQL Config: Skipped default log directory check - SQL not connected"
    $failed++
}

# Test 10: SQL Server firewall rule for TCP 1433 exists
try {
    $fwRule = Get-NetFirewallRule -Name 'MssqlFirewallRule' -ErrorAction Stop
    $portFilter = $fwRule | Get-NetFirewallPortFilter

    if ($fwRule.Enabled -eq 'True' -and $portFilter.LocalPort -eq '1433' -and $portFilter.Protocol -eq 'TCP') {
        Write-TestResult $moduleName 'PASS' "Firewall: SQL Server rule 'MssqlFirewallRule' exists (TCP 1433, Enabled)"
        $passed++
    }
    else {
        Write-TestResult $moduleName 'FAIL' "Firewall: SQL Server rule 'MssqlFirewallRule' exists but misconfigured (Enabled=$($fwRule.Enabled), Port=$($portFilter.LocalPort), Protocol=$($portFilter.Protocol))"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "Firewall: SQL Server rule 'MssqlFirewallRule' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Test 11: SQL Server startup scheduled task exists
try {
    $task = Get-ScheduledTask -TaskName 'Set-MssqlStartupConfiguration' -ErrorAction Stop
    Write-TestResult $moduleName 'PASS' "Scheduled Task: 'Set-MssqlStartupConfiguration' exists (state: $($task.State))"
    $passed++
}
catch {
    Write-TestResult $moduleName 'FAIL' "Scheduled Task: 'Set-MssqlStartupConfiguration' not found"
    Write-TestResult $moduleName 'FAIL' "Exception: $_"
    $failed++
}

# Tests 12-16: SQL Server tests requiring sysadmin privileges
# RunPowerShellScript runs as NT AUTHORITY\SYSTEM which lacks privileges to query
# sys.server_principals, sys.master_files, or create databases.
# Use a single scheduled task running as the domain admin to perform all privileged checks.
$sqlTaskName = 'UnitTest-SQL-SysadminChecks'
$sqlResultFile = "C:\unit-tests\$moduleName\sysadmin-checks-result.txt"

if ($adminUsername -and $adminPassword -and $domainName) {
    $netbiosDomain = $domainName.Split('.')[0].ToUpper()
    $domainUser = "$netbiosDomain\$adminUsername"
    $testDbName = 'unittestdb'

    # Clean up any previous task and result file
    Unregister-ScheduledTask -TaskName $sqlTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $sqlResultFile -Force -ErrorAction SilentlyContinue

    # The task script runs all privileged SQL checks and writes structured results to a file.
    # Each line: CHECK_NAME|PASS_OR_FAIL|detail
    $testScript = @"
`$ErrorActionPreference = 'Stop'
`$resultFile = '$sqlResultFile'
`$results = @()

function Run-SqlQuery {
    param([System.Data.SqlClient.SqlConnection]`$Conn, [string]`$Query)
    `$cmd = `$Conn.CreateCommand()
    `$cmd.CommandText = `$Query
    `$adapter = New-Object System.Data.SqlClient.SqlDataAdapter(`$cmd)
    `$ds = New-Object System.Data.DataSet
    `$adapter.Fill(`$ds) | Out-Null
    return `$ds.Tables[0]
}

try {
    `$cxn = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    `$cxn.'Data Source' = 'localhost'
    `$cxn.'Initial Catalog' = 'master'
    `$cxn.'Integrated Security' = `$true
    `$cxn.'Encrypt' = `$true
    `$cxn.'TrustServerCertificate' = `$true
    `$conn = New-Object System.Data.SqlClient.SqlConnection(`$cxn.ConnectionString)
    `$conn.Open()

    # Check 1: Domain admin login exists with sysadmin role
    try {
        `$domainLogin = '$domainUser'
        `$r = Run-SqlQuery -Conn `$conn -Query "SELECT SUSER_ID(N'`$domainLogin') AS LoginId, IS_SRVROLEMEMBER('sysadmin', N'`$domainLogin') AS IsSysAdmin"
        `$loginId = `$null
        `$isSysAdmin = `$null
        foreach (`$row in `$r) {
            `$loginId = `$row.LoginId
            `$isSysAdmin = `$row.IsSysAdmin
        }
        if (`$null -ne `$loginId -and `$loginId -isnot [System.DBNull] -and "`$isSysAdmin" -eq '1') {
            `$results += "LOGIN|PASS|'`$domainLogin' exists (id=`$loginId) and is a sysadmin"
        } elseif (`$null -ne `$loginId -and `$loginId -isnot [System.DBNull]) {
            `$results += "LOGIN|FAIL|'`$domainLogin' exists (id=`$loginId) but is not a sysadmin (IS_SRVROLEMEMBER=`$isSysAdmin)"
        } else {
            `$results += "LOGIN|FAIL|'`$domainLogin' not found (SUSER_ID returned NULL)"
        }
    } catch {
        `$results += "LOGIN|FAIL|Exception: `$_"
    }

    # Check 2: System database data files on M: drive
    try {
        `$r = Run-SqlQuery -Conn `$conn -Query "SELECT db.name AS DatabaseName, mf.physical_name AS PhysicalPath FROM sys.master_files mf JOIN sys.databases db ON mf.database_id = db.database_id WHERE db.name IN ('master', 'model', 'msdb') AND mf.type_desc = 'ROWS' ORDER BY db.name"
        `$allOk = `$true
        `$details = @()
        foreach (`$row in `$r) {
            `$pp = "`$(`$row.PhysicalPath)"
            `$details += "`$(`$row.DatabaseName)=`$pp"
            if (`$pp -notlike '${sqlDataDrive}:\*') { `$allOk = `$false }
        }
        if (`$details.Count -eq 0) {
            `$results += "SYSDB_DATA|FAIL|No system database data files found"
        } elseif (`$allOk) {
            `$results += "SYSDB_DATA|PASS|System database data files are on '${sqlDataDrive}:' (`$(`$details -join ', '))"
        } else {
            `$results += "SYSDB_DATA|FAIL|Not all system database data files are on '${sqlDataDrive}:' (`$(`$details -join ', '))"
        }
    } catch {
        `$results += "SYSDB_DATA|FAIL|Exception: `$_"
    }

    # Check 3: System database log files on L: drive
    try {
        `$r = Run-SqlQuery -Conn `$conn -Query "SELECT db.name AS DatabaseName, mf.physical_name AS PhysicalPath FROM sys.master_files mf JOIN sys.databases db ON mf.database_id = db.database_id WHERE db.name IN ('master', 'model', 'msdb') AND mf.type_desc = 'LOG' ORDER BY db.name"
        `$allOk = `$true
        `$details = @()
        foreach (`$row in `$r) {
            `$pp = "`$(`$row.PhysicalPath)"
            `$details += "`$(`$row.DatabaseName)=`$pp"
            if (`$pp -notlike '${sqlLogDrive}:\*') { `$allOk = `$false }
        }
        if (`$details.Count -eq 0) {
            `$results += "SYSDB_LOG|FAIL|No system database log files found"
        } elseif (`$allOk) {
            `$results += "SYSDB_LOG|PASS|System database log files are on '${sqlLogDrive}:' (`$(`$details -join ', '))"
        } else {
            `$results += "SYSDB_LOG|FAIL|Not all system database log files are on '${sqlLogDrive}:' (`$(`$details -join ', '))"
        }
    } catch {
        `$results += "SYSDB_LOG|FAIL|Exception: `$_"
    }

    # Check 4: tempdb files on T: drive
    try {
        `$r = Run-SqlQuery -Conn `$conn -Query "SELECT mf.name AS LogicalName, mf.physical_name AS PhysicalPath FROM sys.master_files mf WHERE mf.database_id = DB_ID('tempdb') ORDER BY mf.type_desc, mf.name"
        `$allOk = `$true
        `$details = @()
        foreach (`$row in `$r) {
            `$pp = "`$(`$row.PhysicalPath)"
            `$details += "`$(`$row.LogicalName)=`$pp"
            if (`$pp -notlike 'T:\*') { `$allOk = `$false }
        }
        if (`$details.Count -eq 0) {
            `$results += "TEMPDB|FAIL|No tempdb files found"
        } elseif (`$allOk) {
            `$results += "TEMPDB|PASS|tempdb files are on 'T:' (`$(`$details -join ', '))"
        } else {
            `$results += "TEMPDB|FAIL|Not all tempdb files are on 'T:' (`$(`$details -join ', '))"
        }
    } catch {
        `$results += "TEMPDB|FAIL|Exception: `$_"
    }

    # Check 5: Create and validate test database
    try {
        `$cmd = `$conn.CreateCommand()
        `$cmd.CommandText = "IF DB_ID('$testDbName') IS NOT NULL DROP DATABASE [$testDbName]; CREATE DATABASE [$testDbName];"
        `$cmd.ExecuteNonQuery() | Out-Null
        `$r = Run-SqlQuery -Conn `$conn -Query "SELECT mf.type_desc AS FileType, mf.physical_name AS PhysicalPath FROM sys.master_files mf WHERE mf.database_id = DB_ID('$testDbName')"
        `$dataOnM = `$false
        `$logOnL = `$false
        `$details = @()
        foreach (`$row in `$r) {
            `$ft = "`$(`$row.FileType)"
            `$pp = "`$(`$row.PhysicalPath)"
            `$details += "`$ft=`$pp"
            if (`$ft -eq 'ROWS' -and `$pp -like '${sqlDataDrive}:\*') { `$dataOnM = `$true }
            if (`$ft -eq 'LOG' -and `$pp -like '${sqlLogDrive}:\*') { `$logOnL = `$true }
        }
        `$cmd.CommandText = "DROP DATABASE [$testDbName];"
        `$cmd.ExecuteNonQuery() | Out-Null
        if (`$dataOnM -and `$logOnL) {
            `$results += "CREATEDB|PASS|Created database '$testDbName' - data on '${sqlDataDrive}:', log on '${sqlLogDrive}:' (`$(`$details -join ', '))"
        } else {
            `$results += "CREATEDB|FAIL|Files not on expected drives: `$(`$details -join ', ')"
        }
    } catch {
        try { `$cmd2 = `$conn.CreateCommand(); `$cmd2.CommandText = "IF DB_ID('$testDbName') IS NOT NULL DROP DATABASE [$testDbName];"; `$cmd2.ExecuteNonQuery() | Out-Null } catch {}
        `$results += "CREATEDB|FAIL|Exception: `$_"
    }

    `$conn.Close()
} catch {
    `$results += "CONNECTION|FAIL|Failed to connect to SQL Server as domain admin: `$_"
}

Set-Content -Path `$resultFile -Value (`$results -join "`n")
exit 0
"@

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($testScript))

    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NonInteractive -EncodedCommand " + $encodedCommand)
        Register-ScheduledTask -TaskName $sqlTaskName -Action $action -User $domainUser -Password $adminPassword -RunLevel Highest -Force -ErrorAction Stop | Out-Null

        Start-ScheduledTask -TaskName $sqlTaskName -ErrorAction Stop

        # Wait for the task to complete (max 120 seconds)
        $waited = 0
        do {
            Start-Sleep -Seconds 2
            $waited += 2
            $taskInfo = Get-ScheduledTaskInfo -TaskName $sqlTaskName -ErrorAction SilentlyContinue
        } while ($waited -lt 120 -and $taskInfo.LastTaskResult -eq 267009)

        if (Test-Path $sqlResultFile) {
            $resultLines = Get-Content $sqlResultFile

            # Map check names to test labels
            $checkLabels = @{
                'LOGIN'      = 'SQL Login'
                'SYSDB_DATA' = 'SQL Config'
                'SYSDB_LOG'  = 'SQL Config'
                'TEMPDB'     = 'SQL Config'
                'CREATEDB'   = 'SQL Smoke Test'
                'CONNECTION' = 'SQL Connection'
            }

            foreach ($line in $resultLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line.Trim() -split '\|', 3
                $checkName = $parts[0]
                $checkStatus = $parts[1]
                $checkDetail = if ($parts.Count -gt 2) { $parts[2] } else { '' }
                $label = if ($checkLabels.ContainsKey($checkName)) { $checkLabels[$checkName] } else { $checkName }

                if ($checkStatus -eq 'PASS') {
                    Write-TestResult $moduleName 'PASS' "$label`: $checkDetail"
                    $passed++
                }
                else {
                    Write-TestResult $moduleName 'FAIL' "$label`: $checkDetail"
                    $failed++
                }
            }
        }
        else {
            Write-TestResult $moduleName 'FAIL' "SQL Sysadmin Checks: Scheduled task completed (exit code: $($taskInfo.LastTaskResult)) but result file not found"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "SQL Sysadmin Checks: Scheduled task failed: $_"
        $failed++
    }
    finally {
        Unregister-ScheduledTask -TaskName $sqlTaskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $sqlResultFile -Force -ErrorAction SilentlyContinue
    }
}
else {
    $skipReason = if (-not $adminUsername -or -not $adminPassword) { 'admin credentials not available from Key Vault' }
                  elseif (-not $domainName) { 'domain name not available' }
                  else { 'unknown prerequisite failure' }
    Write-TestResult $moduleName 'FAIL' "SQL Login: Skipped - $skipReason"
    $failed++
    Write-TestResult $moduleName 'FAIL' "SQL Config: Skipped system database data file check - $skipReason"
    $failed++
    Write-TestResult $moduleName 'FAIL' "SQL Config: Skipped system database log file check - $skipReason"
    $failed++
    Write-TestResult $moduleName 'FAIL' "SQL Config: Skipped tempdb file check - $skipReason"
    $failed++
    Write-TestResult $moduleName 'FAIL' "SQL Smoke Test: Skipped - $skipReason"
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' ("Passed: $passed Failed: $failed Total: $total")

if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
