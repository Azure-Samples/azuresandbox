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
    [String]$AutomationAccountId,

    [Parameter(Mandatory = $true)]
    [String]$VirtualMachineName,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$AppSecret,

    [Parameter(Mandatory = $true)]
    [string]$DscConfigurationName
)

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
        [string] $VmResourceGroupName,

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
        Get-AzAutomationDscNodeConfiguration `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $nodeConfigName | Out-Null
    }
    catch {
        Exit-WithError $_
    }

    Write-Log "Registering DSC node '$VirtualMachineName' with node configuration '$nodeConfigName'..."
    Write-Log "Warning, this process can take several minutes and the VM will be rebooted..."

    Register-AzAutomationDscNode `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -AzureVMName $VirtualMachineName `
        -AzureVMResourceGroup $VmResourceGroupName `
        -AzureVMLocation $Location `
        -NodeConfigurationName $nodeConfigName `
        -ConfigurationModeFrequencyMins 15 `
        -ConfigurationMode 'ApplyOnly' `
        -AllowModuleOverwrite $false `
        -RebootNodeIfNeeded $true `
        -ActionAfterReboot 'ContinueConfiguration' `
        -ErrorAction SilentlyContinue
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
$automationAccountParts = $AutomationAccountId.Split("/")
$automationAccountResourceGroupName = $automationAccountParts[4]
$automationAccountName = $automationAccountParts[8]


$automationAccount = Get-AzAutomationAccount -ResourceGroupName $automationAccountResourceGroupName -Name $automationAccountName

if ($null -eq $automationAccount) {
    Exit-WithError "Automation account '$automationAccountName' was not found in resource group '$automationAccountResourceGroupName'..."
}

Write-Log "Located automation account '$AutomationAccountName' in resource group '$automationAccountResourceGroupName'"

# Register DSC Node
Register-DscNode `
    -ResourceGroupName $automationAccountResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -VmResourceGroupName $ResourceGroupName `
    -VirtualMachineName $VirtualMachineName `
    -Location $Location `
    -DscConfigurationName $DscConfigurationName

Exit
#endregion
