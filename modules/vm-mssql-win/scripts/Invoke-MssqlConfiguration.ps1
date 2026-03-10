# First boot Azure VM extension orchestrator script for SQL Server 2025 / Windows Server 2025 Azure Virtual Machine configuration.
# Installs Azure PowerShell in order to connect to KeyVault to retrieve secrets using managed identity.
# Executes Set-MssqlConfiguration.ps1 on first boot as a scheduled task.
# Reboots the computer to use new page file settings.

# This script has only been tested under the following conditions:
# - Windows Server 2025 using PowerShell 5.x for Windows
# - Runs as local administrator on the VM being configured

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
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [string]$AdminUsernameSecret,

    [Parameter(Mandatory = $true)]
    [string]$AdminPwdSecret
)
#endregion

#region constants
$TaskName = 'Set-MssqlConfiguration'
$RebootTaskName = 'Set-MssqlConfiguration-Reboot'
$MaxTaskAttempts = 10
$SCHED_S_TASK_RUNNING = 0x00041301
#endregion

#region functions
function Write-ScriptLog {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
}

function Write-InputParameter {
    param(
        [hashtable]$Parameters
    )

    Write-ScriptLog "Input parameters provided to script:"

    foreach ($key in ($Parameters.Keys | Sort-Object)) {
        $value = $Parameters[$key]

        if ($null -eq $value) {
            Write-ScriptLog "Parameter '$key' = <null>"
            continue
        }

        Write-ScriptLog "Parameter '$key' = '$value'"
    }
}

function Exit-WithError {
    param( [string]$msg )
    Write-ScriptLog "There was an exception during the process, please review..."
    Write-ScriptLog $msg
    Exit 2
}
#endregion

#region main
$logpath = $PSCommandPath + '.log'
Write-ScriptLog "Running '$PSCommandPath'..."
Write-InputParameter -Parameters $PSBoundParameters

# Install Powershell Az module
Write-ScriptLog "Installing NuGet package provider..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope AllUsers -Confirm:$false

Write-ScriptLog "Configuring PSGallery installation policy 'Trusted'..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-ScriptLog "Installing PowerShell Az.Accounts module..."
Install-Module -Name Az.Accounts -Repository PSGallery -Scope AllUsers -Force -AllowClobber

Write-ScriptLog "Installing PowerShell Az.KeyVault module..."
Install-Module -Name Az.KeyVault -Repository PSGallery -Scope AllUsers -Force -AllowClobber

# Log into Azure
Write-ScriptLog "Logging into Azure using managed identity..."

try {
    Connect-AzAccount -Identity
}
catch {
    Exit-WithError $_
}

# Get Secrets from key vault
Write-ScriptLog "Getting secret '$AdminUsernameSecret' from key vault '$KeyVaultName'..."

try {
    $adminUsername = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminUsernameSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminUsername)) {
    Exit-WithError "Secret '$AdminUsernameSecret' not found in key vault '$KeyVaultName'..."
}

Write-ScriptLog "The value of secret '$AdminUsernameSecret' is '$adminUsername'..."

Write-ScriptLog "Getting secret '$AdminPwdSecret' from key vault '$KeyVaultName'..."

try {
    $adminPwd = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminPwdSecret -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($adminPwd)) {
    Exit-WithError "Secret '$AdminPwdSecret' not found in key vault '$KeyVaultName'..."
}

Write-ScriptLog "The length of secret '$AdminPwdSecret' is '$($adminPwd.Length)'..."

# Disconnect from Azure
Disconnect-AzAccount

# Register scheduled task to configure SQL Server
$scriptPath = "$((Get-Item $PSCommandPath).DirectoryName)\$TaskName.ps1"
$domainAdminUser = "$($Domain.Split('.')[0].ToUpper())\$adminUsername"

if ( -not (Test-Path $scriptPath) ) {
    Exit-WithError "Unable to locate '$scriptPath'..."
}

Write-ScriptLog "Registering scheduled task '$TaskName' to run '$scriptPath' as '$domainAdminUser'..."

$commandParamParts = @(
    '$params = @{',
      "KeyVaultName = '$KeyVaultName'; ",
      "DomainAdminUser = '$domainAdminUser'; ",
      "AdminPwdSecret = '$AdminPwdSecret'",
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
        -Description "Configure SQL Server." `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-ScriptLog "Starting scheduled task '$TaskName'..."

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

$i = 0
do {
    $i++

    Write-ScriptLog "Getting information for scheduled task '$TaskName' (attempt '$i' of '$MaxTaskAttempts')..."

    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    }
    catch {
        Exit-WithError $_
    }

    # Note: LastTaskResult values are documented here: https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants
    $lastTaskResult = $taskInfo.LastTaskResult

    Write-ScriptLog "LastTaskResult for task '$TaskName' is '$lastTaskResult'..."

    if ($lastTaskResult -eq 0) {
        break
    }

    if ($lastTaskResult -eq $SCHED_S_TASK_RUNNING) {
        Start-Sleep 10
        continue
    }

    if ($i -eq $MaxTaskAttempts) {
        Exit-WithError "Task '$taskName' is taking too long to complete..."
    }

    Exit-WithError "Scheduled task '$taskName' returned unexpected LastTaskResult '$lastTaskResult'..."
} while ($true)

Write-ScriptLog "Unregistering scheduled task '$TaskName'..."

try {
    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

# Register one-time reboot task to run one minute from now.
$rebootTaskRunAt = (Get-Date).AddMinutes(1)
Write-ScriptLog "Registering one-time reboot scheduled task '$RebootTaskName' to run at '$rebootTaskRunAt' as '$domainAdminUser'..."

$rebootTaskAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-ExecutionPolicy Unrestricted -Command "Restart-Computer -Force"'

$rebootTaskTrigger = New-ScheduledTaskTrigger -Once -At $rebootTaskRunAt

try {
    Register-ScheduledTask `
        -Force `
        -Password $adminPwd `
        -User $domainAdminUser `
        -TaskName $RebootTaskName `
        -Action $rebootTaskAction `
        -Trigger $rebootTaskTrigger `
        -RunLevel 'Highest' `
        -Description "Force reboot after SQL configuration completes." `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-ScriptLog "One-time reboot scheduled task '$RebootTaskName' created successfully. Exiting without waiting for execution..."

Write-ScriptLog "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
