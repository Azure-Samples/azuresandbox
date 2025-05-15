#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$TenantId,

    [Parameter(Mandatory = $true)]
    [String]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [String]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [string]$AdminUsernameSecret,

    [Parameter(Mandatory = $true)]
    [string]$AdminPwdSecret
)
#endregion

#region constants
$TaskName = 'Set-AzureFilesConfiguration'
$MaxTaskAttempts = 10
$SCHED_S_TASK_RUNNING = 0x00041301
$ERROR_SHUTDOWN_IN_PROGRESS = 0x8007045B
#endregion

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
}

function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}
#endregion

#region main
$logpath = $PSCommandPath + '.log'
Write-Log "Running '$PSCommandPath'..."

# Log into Azure with retry logic
Write-Log "Logging into Azure using managed identity..."

$maxRetries = 40
$retryCount = 0
$success = $false

while (-not $success -and $retryCount -lt $maxRetries) {
    try {
        Connect-AzAccount -Identity -ErrorAction Stop
        $success = $true
        Write-Log "Successfully logged into Azure."
    }
    catch {
        $retryCount++
        Write-Log "Failed to log into Azure. Attempt $retryCount of $maxRetries. Retrying in 1 minute..."
        if ($retryCount -ge $maxRetries) {
            Exit-WithError "Failed to log into Azure after $maxRetries attempts."
        }
        Start-Sleep -Seconds 60
    }
}

# Get Secrets from key vault
Write-Log "Getting secret '$AdminUsernameSecret' from key vault '$KeyVaultName'..."

try {
    $adminUsername = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminUsernameSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminUsername)) {
    Exit-WithError "Secret '$AdminUsernameSecret' not found in key vault '$KeyVaultName'..."
}

Write-Log "The value of secret '$AdminUsernameSecret' is '$adminUsername'..."

Write-Log "Getting secret '$AdminPwdSecret' from key vault '$KeyVaultName'..."

try {
    $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminPwdSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminPwd)) {
    Exit-WithError "Secret '$AdminPwdSecret' not found in key vault '$KeyVaultName'..."
}

Write-Log "The length of secret '$AdminPwdSecret' is '$($adminPwd.Length)'..."

# Disconnect from Azure
Disconnect-AzAccount

# Register scheduled task to configure Azure Storage for kerberos authentication with domain
$scriptPath = "$((Get-Item $PSCommandPath).DirectoryName)\$TaskName.ps1"
$domainAdminUser = "$($Domain.Split('.')[0].ToUpper())\$adminUsername"

if ( -not (Test-Path $scriptPath) ) {
    Exit-WithError "Unable to locate '$scriptPath'..."
}

Write-Log "Registering scheduled task '$TaskName' to run '$scriptPath' as '$domainAdminUser'..."

$commandParamParts = @(
    '$params = @{',
    "TenantId = '$TenantId'; ", 
    "SubscriptionId = '$SubscriptionId'; ", 
    "AppId = '$AppId'; ",
    "ResourceGroupName = '$ResourceGroupName'; ",
    "KeyVaultName = '$KeyVaultName'; ",
    "StorageAccountName = '$StorageAccountName'; ",
    "Domain = '$Domain'",
    '}'
)

$taskAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-ExecutionPolicy Unrestricted -Command `"$($commandParamParts -join ''); . $scriptPath @params`""

try {
    Register-ScheduledTask `
        -Force `
        -Password $adminPwd `
        -User $domainAdminUser `
        -TaskName $TaskName `
        -Action $taskAction `
        -RunLevel 'Highest' `
        -Description "Configure Azure Files for kerberos authentication with domain." `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-Log "Starting scheduled task '$TaskName'..."

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

$i = 0
do {
    $i++

    Write-Log "Getting information for scheduled task '$TaskName' (attempt '$i' of '$MaxTaskAttempts')..."

    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    }
    catch {
        Exit-WithError $_
    }

    # Note: LastTaskResult values are documented here: https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants 
    $lastTaskResult = $taskInfo.LastTaskResult

    Write-Log "LastTaskResult for task '$TaskName' is '$lastTaskResult'..."

    if ($lastTaskResult -eq 0) {
        break
    }

    if ($lastTaskResult -eq $SCHED_S_TASK_RUNNING) {
        Start-Sleep 10
        continue
    }

    if ($lastTaskResult -eq $ERROR_SHUTDOWN_IN_PROGRESS) {
        Exit-WithError "Task '$taskName' cannot be started because the system is shutting down..."
    }

    if ($i -eq $MaxTaskAttempts) {
        Exit-WithError "Task '$taskName' is taking too long to complete..."
    }

    Exit-WithError "Scheduled task '$taskName' returned unexpected LastTaskResult '$lastTaskResult'..."
} while ($true)

Write-Log "Unregistering scheduled task '$TaskName'..."

try {
    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
