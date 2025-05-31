#!/usr/bin/env pwsh

#region params
param (
    [Parameter(Mandatory = $true)]
    [String]$TenantId,

    [Parameter(Mandatory = $true)]
    [String]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [String]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [String]$AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [String]$Domain,

    [Parameter(Mandatory = $true)]
    [String]$VmAddsName,

    [Parameter(Mandatory = $true)]
    [String]$VmJumpboxWinName,

    [Parameter(Mandatory = $true)]
    [String]$AdminUsername,

    [Parameter(Mandatory = $true)]
    [String]$AdminPwd,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$AppSecret,

    [Parameter(Mandatory = $true)]
    [String]$DnsResolverCloud
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

function Import-DscConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]$AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String]$DscConfigurationName,

        [Parameter(Mandatory = $true)]
        [String]$DscConfigurationScript
    )
    
    Write-Log "Importing DSC configuration '$DscConfigurationName' from '$DscConfigurationScript'..."
    $dscConfigurationScriptPath = Join-Path $PSScriptRoot $DscConfigurationScript
    
    try {
        Import-AzAutomationDscConfiguration `
            -SourcePath $dscConfigurationScriptPath `
            -Description $DscConfigurationName `
            -Published `
            -Force `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -ErrorAction Stop `
        | Out-Null
    }
    catch {
        Exit-WithError $_
    }
}

function Start-DscCompilationJob {
    param(
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]$AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String]$DscConfigurationName,

        [Parameter(Mandatory = $true)]
        [String]$VirtualMachineName
    )

    Write-Log "Compliling DSC Configuration '$DscConfigurationName'..."

    $params = @{
        ComputerName = $VirtualMachineName
    }

    $configuationData = @{
        AllNodes = @(
            @{
                NodeName = "$VirtualMachineName"
                PsDscAllowPlainTextPassword = $true
            }
        )
    }

    try {
        $dscCompilationJob = Start-AzAutomationDscCompilationJob `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -ConfigurationName $DscConfigurationName `
            -ConfigurationData $configuationData `
            -Parameters $params `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }
    
    $jobId = $dscCompilationJob.Id
    
    while ($null -eq $dscCompilationJob.EndTime -and $null -eq $dscCompilationJob.Exception) {
        $dscCompilationJob = $dscCompilationJob | Get-AzAutomationDscCompilationJob
        Write-Log "DSC compilation job ID '$jobId' status is '$($dscCompilationJob.Status)'..."
        Start-Sleep -Seconds 10
    }
    
    if ($dscCompilationJob.Exception) {
        Exit-WithError "DSC compilation job ID '$jobId' failed..."
    }
    
    Write-Log "DSC compilation job ID '$jobId' status is '$($dscCompilationJob.Status)'..."    
}

function Set-Variable {
    param(
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]$AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String]$VariableName,

        [Parameter(Mandatory = $true)]
        [String]$VariableValue
    )

    Write-Log "Setting automation variable '$VariableName' to value '$VariableValue'..."
    $automationVariable = Get-AzAutomationVariable -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName | Where-Object { $_.Name -eq $VariableName }

    if ($null -eq $automationVariable) {
        try {
            $automationVariable = New-AzAutomationVariable `
                -Name $VariableName `
                -Encrypted $false `
                -Description $VariableName `
                -Value $VariableValue `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -ErrorAction Stop
        }
        catch {
            Exit-WithError $_
        }
    }
    else {
        try {
            $automationVariable = Set-AzAutomationVariable `
                -Name $VariableName `
                -Encrypted $false `
                -Value $VariableValue `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -ErrorAction Stop
        }
        catch {
            Exit-WithError $_
        }
    }
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

# Log into Azure
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

# Bootstrap automation variables
Set-Variable `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -VariableName 'adds2_domain_name' `
    -VariableValue $Domain

Set-Variable `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -VariableName 'dns_resolver_cloud' `
    -VariableValue $DnsResolverCloud

# Import DSC Configurations
Import-DscConfiguration `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'DomainControllerConfiguration2' `
    -DscConfigurationScript 'DomainControllerConfiguration2.ps1'

Import-DscConfiguration `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'JumpBoxConfiguration2' `
    -DscConfigurationScript 'JumpBoxConfiguration2.ps1'

# Compile DSC Configurations
Start-DscCompilationJob `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'DomainControllerConfiguration2' `
    -VirtualMachineName $VmAddsName

Start-DscCompilationJob `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'JumpBoxConfiguration2' `
    -VirtualMachineName $VmJumpboxWinName

Exit 0
#endregion
