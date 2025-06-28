#!/usr/bin/env pwsh

#region parameters
param (
    [Parameter(Mandatory = $true)]
    [String]$TenantId,

    [Parameter(Mandatory = $true)]
    [String]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [String]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [String]$Location,

    [Parameter(Mandatory = $true)]
    [String]$AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [String]$VirtualMachineName,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$AppSecret,

    [Parameter(Mandatory = $true)]
    [string]$DscConfigurationName
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

function Register-DscNode {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $VirtualMachineName,

        [Parameter(Mandatory = $true)]
        [string] $Location,

        [Parameter(Mandatory = $true)]
        [string] $DscConfigurationName
    )

    $nodeConfigName = $DscConfigurationName + '.' + $VirtualMachineName

    try {
        $dscNodes = Get-AzAutomationDscNode `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $VirtualMachineName `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    if ($null -eq $dscNodes) {
        Write-Log "No existing DSC node registrations for '$VirtualMachineName' with node configuration '$nodeConfigName' found..."
    }
    else {
        foreach ($dscNode in $dscNodes) {
            $dscNodeId = $dscNode.Id
            Write-Log "Unregistering DSC node registration '$dscNodeId'..."

            try {
                Unregister-AzAutomationDscNode `
                    -Id $dscNodeId `
                    -Force `
                    -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName
            }
            catch {
                Exit-WithError $_
            }
        }
    }

    Write-Log "Checking for node configuration '$nodeConfigName'..."

    try {
        $nodeConfig = Get-AzAutomationDscNodeConfiguration `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $nodeConfigName `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    $rollupStatus = $nodeConfig.RollupStatus
    Write-Log "DSC node configuration '$nodeConfigName' RollupStatus is '$($rollupStatus)'..."

    if ($rollupStatus -ne 'Good'){
        Exit-WithError "Invalid DSC node configuration RollupStatus..."
    }

    Write-Log "Registering DSC node '$VirtualMachineName' with node configuration '$nodeConfigName'..."
    Write-Log "Warning, this process can take several minutes and the VM will be rebooted..."

    Register-AzAutomationDscNode `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -AzureVMName $VirtualMachineName `
        -AzureVMResourceGroup $ResourceGroupName `
        -AzureVMLocation $Location `
        -NodeConfigurationName $nodeConfigName `
        -ConfigurationModeFrequencyMins 15 `
        -ConfigurationMode 'ApplyOnly' `
        -AllowModuleOverwrite $false `
        -RebootNodeIfNeeded $true `
        -ActionAfterReboot 'ContinueConfiguration' `
        -ErrorAction SilentlyContinue

    Write-Log "Sleeping for 60 seconds before checking node status..."    
    Start-Sleep -Seconds 60
    
    try {
        $dscNodes = Get-AzAutomationDscNode `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $VirtualMachineName `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }

    if ($null -eq $dscNodes) {
        Exit-WithError "No existing DSC node registrations for '$VirtualMachineName' with node configuration '$nodeConfigName' found..."
    }

    $dscNode = $dscNodes[0]
    $dscNodeId = $dscNode.Id
    $dscNodeStatus = $dscNode.Status
    Write-Log "DSC node registration id '$dscNodeId' found with status '$dscNodeStatus'..."    
    
    $maxRetries = 30
    $retryCount = 0
    $statusCompliant = "Compliant"

    while ($retryCount -lt $maxRetries -and $dscNodeStatus -ne $statusCompliant) {
        $retryCount++
        try {
            $dscNodes = Get-AzAutomationDscNode `
                -Id $dscNodeId `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -ErrorAction Stop
            }
        catch {
            Exit-WithError $_
        }

        $dscNode = $dscNodes[0]
        $dscNodeId = $dscNode.Id
        $dscNodeStatus = $dscNode.Status
        Write-Log "Retry '$retryCount': DSC node registration id '$dscNodeId' status is '$dscNodeStatus'..."

        if ($dscNodeStatus -ne $statusCompliant) {
            Write-Log "DSC node status is not '$statusCompliant'. Retrying in 30 seconds..."
            Start-Sleep -Seconds 30
        }
    }

    if ($dscNodeStatus -ne $statusCompliant) {
        Exit-WithError "DSC node status did not reach '$statusCompliant' after $maxRetries attempts."
    }    
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

Write-Log "Logging into Azure using service principal id '$AppId'..."

$AppSecretSecure = ConvertTo-SecureString $AppSecret -AsPlainText -Force
$spCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $AppSecretSecure

try {
    Connect-AzAccount -Credential $spCredential -Tenant $TenantId -ServicePrincipal -ErrorAction Stop | Out-Null
}
catch {
    Exit-WithError $_
}

# Set default subscription
Write-Log "Setting default subscription to '$SubscriptionId'..."

try {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}
catch {
    Exit-WithError $_
}

# Get automation account
$automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName

if ($null -eq $automationAccount) {
    Exit-WithError "Automation account '$AutomationAccountName' was not found..."
}

Write-Log "Located automation account '$AutomationAccountName' in resource group '$ResourceGroupName'"

# Register DSC Node
Register-DscNode `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -VirtualMachineName $VirtualMachineName `
    -Location $Location `
    -DscConfigurationName $DscConfigurationName

Exit
#endregion
