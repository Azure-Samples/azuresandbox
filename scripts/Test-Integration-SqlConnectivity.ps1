param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$TargetVmName
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
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'integration'
$logDir = 'C:\unit-tests\integration'
$script:logPath = Join-Path $logDir 'Test-Integration-SqlConnectivity.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: SQL connectivity from '$env:COMPUTERNAME' to '$TargetVmName'..."

$passed = 0
$failed = 0

# Get domain name
$domainName = $null
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $domainName = $cs.Domain
    Write-Log "Detected domain: '$domainName'"
}
catch {
    Write-Log "WARNING: Could not detect domain name: $_"
}

# Get credentials from Key Vault via managed identity
$adminUser = $null
$adminPwd = $null

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $adminUser = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminuser' -AsPlainText -ErrorAction Stop
    $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'adminpassword' -AsPlainText -ErrorAction Stop
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Retrieved domain admin credentials from Key Vault."
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL: Failed to retrieve credentials from Key Vault: $_"
    $failed++
    $total = $passed + $failed
    Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    return
}

if (-not $domainName -or -not $adminUser -or -not $adminPwd) {
    Write-TestResult $moduleName 'FAIL' "SQL: Missing prerequisites (domain='$domainName', user='$adminUser')"
    $failed++
    $total = $passed + $failed
    Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    return
}

# Test 1: SQL Server connectivity and sysadmin role verification via scheduled task
# RunPowerShellScript runs as SYSTEM which has no domain Kerberos ticket.
# Use a scheduled task as the domain admin to connect with Windows Authentication.
$taskName = 'UnitTest-SQL-Connectivity'
$resultFile = 'C:\unit-tests\integration\sql-connectivity-result.txt'

$domainNetbios = $domainName.Split('.')[0].ToUpper()
$domainUserFull = "$domainNetbios\$adminUser"

# Clean up any previous task and result file
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $resultFile -Force -ErrorAction SilentlyContinue

# The task script: connect to SQL Server on the target VM, verify sysadmin role, disconnect.
$testScript = @"
`$ErrorActionPreference = 'Stop'
`$resultFile = '$resultFile'
try {
    `$cxn = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    `$cxn.'Data Source' = '$TargetVmName'
    `$cxn.'Initial Catalog' = 'master'
    `$cxn.'Integrated Security' = `$true
    `$cxn.'Encrypt' = `$true
    `$cxn.'TrustServerCertificate' = `$true
    `$conn = New-Object System.Data.SqlClient.SqlConnection(`$cxn.ConnectionString)
    `$conn.Open()
    `$cmd = `$conn.CreateCommand()
    `$cmd.CommandText = 'SELECT SUSER_NAME() AS LoginName, IS_SRVROLEMEMBER(''sysadmin'') AS IsSysAdmin'
    `$adapter = New-Object System.Data.SqlClient.SqlDataAdapter(`$cmd)
    `$ds = New-Object System.Data.DataSet
    `$adapter.Fill(`$ds) | Out-Null
    `$loginName = `$null
    `$isSysAdmin = `$null
    foreach (`$row in `$ds.Tables[0]) {
        `$loginName = "`$(`$row.LoginName)"
        `$isSysAdmin = "`$(`$row.IsSysAdmin)"
    }
    `$conn.Close()
    `$conn.Dispose()
    if (`$isSysAdmin -eq '1') {
        Set-Content -Path `$resultFile -Value "PASS|Connected to '$TargetVmName' as '`$loginName' with sysadmin privileges"
    } else {
        Set-Content -Path `$resultFile -Value "FAIL|Connected to '$TargetVmName' as '`$loginName' but IS_SRVROLEMEMBER('sysadmin') returned `$isSysAdmin"
    }
    exit 0
} catch {
    Set-Content -Path `$resultFile -Value "FAIL|Failed to connect to '$TargetVmName': `$_"
    exit 1
}
"@

$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($testScript))

try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NonInteractive -EncodedCommand " + $encodedCommand)
    Register-ScheduledTask -TaskName $taskName -Action $action -User $domainUserFull -Password $adminPwd -RunLevel Highest -Force -ErrorAction Stop | Out-Null

    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop

    # Wait for the task to complete (max 60 seconds)
    $waited = 0
    do {
        Start-Sleep -Seconds 2
        $waited += 2
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    } while ($waited -lt 60 -and $taskInfo.LastTaskResult -eq 267009)

    if (Test-Path $resultFile) {
        $resultContent = Get-Content $resultFile -Raw
        $parts = $resultContent.Trim() -split '\|', 2
        $resultStatus = $parts[0]
        $resultDetail = if ($parts.Count -gt 1) { $parts[1] } else { '' }

        if ($resultStatus -eq 'PASS') {
            Write-TestResult $moduleName 'PASS' "SQL: $resultDetail"
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "SQL: $resultDetail"
            $failed++
        }
    }
    else {
        Write-TestResult $moduleName 'FAIL' "SQL: Scheduled task completed (exit code: $($taskInfo.LastTaskResult)) but result file not found"
        $failed++
    }
}
catch {
    Write-TestResult $moduleName 'FAIL' "SQL: Scheduled task failed: $_"
    $failed++
}
finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $resultFile -Force -ErrorAction SilentlyContinue
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
#endregion
