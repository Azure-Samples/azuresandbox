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
$script:logPath = Join-Path $logDir 'Test-Integration-SshConnectivity.ps1.log'

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if (Test-Path $script:logPath) {
    Remove-Item $script:logPath -Force
}

Write-Log "Starting integration test: SSH connectivity to '$TargetVmName'..."

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
    Write-TestResult $moduleName 'FAIL' "SSH: Failed to retrieve credentials from Key Vault: $_"
    $failed++
    $total = $passed + $failed
    Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    return
}

if (-not $domainName -or -not $adminUser -or -not $adminPwd) {
    Write-TestResult $moduleName 'FAIL' "SSH: Missing prerequisites (domain='$domainName', user='$adminUser')"
    $failed++
    $total = $passed + $failed
    Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    return
}

# Test 1: SSH connectivity and remote command execution via scheduled task
# RunPowerShellScript runs as SYSTEM which has no domain Kerberos ticket.
# Use a scheduled task as the domain admin with SSH_ASKPASS for password auth.
$sshTestPassed = $false
$sshTestReason = 'not attempted'
$taskName = 'UnitTest-SSH-Connectivity'

$domainNetbios = $domainName.Split('.')[0].ToUpper()
$domainUser = "$domainNetbios\$adminUser"
$sshUser = "$adminUser@$domainName"
$targetFqdn = "$TargetVmName.$domainName"

# Clean up any previous task
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# The task script:
# 1. Run ssh.exe with GSSAPI (Kerberos) authentication — the scheduled task runs as the
#    domain admin so a valid Kerberos ticket is already available, no password prompt needed.
# 2. Exit 0 if hostname output received, 1 otherwise
$testScript = @"
try {
    `$ErrorActionPreference = 'Continue'
    `$output = & ssh.exe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=15 -o GSSAPIAuthentication=yes -o PreferredAuthentications=gssapi-with-mic '$sshUser@$targetFqdn' 'hostname' 2>`$null
    `$sshExit = `$LASTEXITCODE
    if (`$sshExit -eq 0 -and `$output) {
        `$output | Out-File 'C:\unit-tests\integration\ssh-result.txt' -Force
        exit 0
    } else { exit 1 }
} catch {
    exit 1
}
"@

$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($testScript))

try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NonInteractive -EncodedCommand " + $encodedCommand)
    Register-ScheduledTask -TaskName $taskName -Action $action -User $domainUser -Password $adminPwd -RunLevel Highest -Force -ErrorAction Stop | Out-Null

    # Clean up any previous result file
    Remove-Item 'C:\unit-tests\integration\ssh-result.txt' -Force -ErrorAction SilentlyContinue

    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop

    # Wait for the task to complete (max 60 seconds)
    $waited = 0
    do {
        Start-Sleep -Seconds 2
        $waited += 2
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    } while ($waited -lt 60 -and $taskInfo.LastTaskResult -eq 267009)

    $lastResult = $taskInfo.LastTaskResult

    if ($lastResult -eq 0) {
        $remoteHostname = ''
        if (Test-Path 'C:\unit-tests\integration\ssh-result.txt') {
            $remoteHostname = (Get-Content 'C:\unit-tests\integration\ssh-result.txt' -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
            Remove-Item 'C:\unit-tests\integration\ssh-result.txt' -Force -ErrorAction SilentlyContinue
        }
        $sshTestPassed = $true
        $sshTestReason = "SSH: Connected to '$targetFqdn' as '$sshUser', remote hostname='$remoteHostname'"
    }
    else {
        $sshTestReason = "SSH: Connection test failed (task exit code: $lastResult)"
    }
}
catch {
    $sshTestReason = "SSH: Scheduled task failed: $_"
}
finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

if ($sshTestPassed) {
    Write-TestResult $moduleName 'PASS' $sshTestReason
    $passed++
}
else {
    Write-TestResult $moduleName 'FAIL' $sshTestReason
    $failed++
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
#endregion
