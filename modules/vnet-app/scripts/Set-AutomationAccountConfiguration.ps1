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
    [String]$AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [String]$VmJumpboxWinName,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$AppSecret
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

Function Get-Dependency {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ModuleName,
        [Parameter(Mandatory = $false)]
        [int] $Level = 0
    )

    if ($Level -eq 0) {
        $orderedModules = [System.Collections.ArrayList]@()
    }

    # Getting dependencies from the gallery
    Write-Verbose "Checking dependencies for $ModuleName"
    $moduleUri = "https://www.powershellgallery.com/api/v2/Search()?`$filter={1}&searchTerm=%27{0}%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40"
    $currentModuleUrl = $moduleUri -f $ModuleName, 'IsLatestVersion'
    $searchResult = Invoke-RestMethod -Method Get -Uri $currentModuleUrl -UseBasicParsing | Where-Object { $_.title.InnerText -eq $ModuleName }

    if ($null -eq $searchResult) {
        Write-Log "Skipping module '$ModuleName' because it cannot be found in PowerShell Gallery..."
        Continue
    }
    
    $moduleInformation = (Invoke-RestMethod -Method Get -UseBasicParsing -Uri $searchResult.id)

    #Creating Variables to get an object
    $moduleVersion = $moduleInformation.entry.properties.version
    $dependencies = $moduleInformation.entry.properties.dependencies
    $dependencyReadable = $dependencies -replace '\:.*', ''

    $moduleObject = [PSCustomObject]@{
        ModuleName    = $ModuleName
        ModuleVersion = $ModuleVersion
    }

    # If no dependencies are found, the module is added to the list
    if ([string]::IsNullOrEmpty($dependencies) ) {
        $orderedModules.Add($moduleObject) | Out-Null
    }

    else {
        # If there are dependencies, they are first checked for dependencies of there own. After that they are added to the list.
        Get-Dependency -ModuleName $dependencyReadable -Level ($Level++)
        $orderedModules.Add($moduleObject) | Out-Null
    }

    return $orderedModules
}

function Import-Module-Custom {
    param(
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]$AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String]$ModuleName,

        [Parameter(Mandatory = $true)]
        [String]$ModuleUri
    )

    Write-Log "Importing module '$ModuleName'..."
    $automationModule = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName | Where-Object { $_.Name -eq $ModuleName }

    if ($null -eq $automationModule) {
        try {
            $automationModule = New-AzAutomationModule `
                -Name $ModuleName `
                -ContentLinkUri $ModuleUri `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -ErrorAction Stop            
        }
        catch {
            Exit-WithError $_
        }
    }

    if ($automationModule.ProvisioningState -ne 'Created') {
        while ($true) {
            $automationModule = Get-AzAutomationModule -Name $ModuleName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        
            if (($automationModule.ProvisioningState -eq 'Succeeded') -or ($automationModule.ProvisioningState -eq 'Failed') -or ($automationModule.ProvisioningState -eq 'Created')) {
                break
            }

            Write-Log "Module '$($automationModule.Name)' provisioning state is '$($automationModule.ProvisioningState)'..."
            Start-Sleep -Seconds 10
        }
    }

    if ($automationModule.ProvisioningState -eq "Failed") {
        Exit-WithError "Module '$($automationModule.Name)' import failed..."
    }

    Write-Log "Module '$($automationModule.Name)' provisioning state is '$($automationModule.ProvisioningState)'..."
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

    Write-Log "Compiling DSC Configuration '$DscConfigurationName'..."

    $params = @{
        ComputerName = $VirtualMachineName
    }

    $configurationData = @{
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
            -ConfigurationData $configurationData `
            -Parameters $params `
            -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }
    
    $jobId = $dscCompilationJob.Id
    
    while (-not $dscCompilationJob.Exception) {
        $dscCompilationJob = $dscCompilationJob | Get-AzAutomationDscCompilationJob
        Write-Log "DSC compilation job ID '$jobId' status is '$($dscCompilationJob.Status)'..."

        if ($dscCompilationJob.Status -in @("Queued", "Starting", "Resuming", "Running", "Stopping", "Suspending", "Activating", "New")) {
            Start-Sleep -Seconds 10
            continue
        }

        # Stop looping if status is Completed, Failed, Stopped, Suspended
        if ($dscCompilationJob.Status -in @("Completed", "Failed", "Stopped", "Suspended")) {
            break
        }

        # Anything else is an unexpected status
        Exit-WithError "DSC compilation job ID '$jobId' returned unexpected status '$($dscCompilationJob.Status)'..."
    }
    
    if ($dscCompilationJob.Exception) {
        Exit-WithError "DSC compilation job ID '$jobId' failed with an exception..."
    }

    if ($dscCompilationJob.Status -in @("Failed", "Stopped", "Suspended")) {
        Exit-WithError "DSC compilation job ID '$jobId' failed with status '$($dscCompilationJob.Status)'..."
    }
}

function Update-ExistingModule {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $ModuleName
    )

    Write-Log "Getting module '$ModuleName' in automation account '$AutomationAccountName'..."

    try {
        $automationModules = Get-AzAutomationModule `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $ModuleName `
            -ErrorAction Stop
    }
    catch{
        Exit-WithError $_
    }

    if ($null -eq $automationModules) {
        Exit-WithError "No modules found in automation account '$AutomationAccountName'..."
    }
    
    # Create a ordered list of all modules including old and current version
    $orderedModuleList = [System.Collections.ArrayList]@()
    foreach ($module in $automationModules) {
        if($($module.Name) -like "Azure*") {
            Write-Log "Skipping upgrade for deprecated module $($module.Name)..."
            continue
        }
    
        $modulesAndDependencies = Get-Dependency -moduleName $module.Name
        foreach ($moduleFiltered  in $modulesAndDependencies) {
            $existingVersion = ($automationModules | Where-Object { $_.Name -eq $moduleFiltered.ModuleName }).Version
            $moduleFiltered | Add-Member -MemberType NoteProperty -Name "ExistingVersion" -Value $existingVersion
            $orderedModuleList.Add($moduleFiltered) | Out-Null
        }
    }
    
    # Create a list of modules that are already updated
    $updatedModules = [System.Collections.ArrayList]@()
    
    foreach ($updateModule in $orderedModuleList) {
        # continue loop if module has already been handled
        if ($updatedModules -contains $updateModule.ModuleName) { 
            continue 
        }
    
        $moduleName = $updateModule.ModuleName
        Write-Log "Checking '$moduleName' in automation account '$AutomationAccountName' for upgrade..."

        # Ensure both versions are cast to [System.Version] and handle four-element versions
        try {
            $existingVersion = [System.Version]::Parse($updateModule.ExistingVersion)
            $moduleVersion = [System.Version]::Parse($updateModule.ModuleVersion)
        }
        catch {
            Exit-WithError "Invalid version format detected for module '$($updateModule.ModuleName)'. ExistingVersion: '$($updateModule.ExistingVersion)', ModuleVersion: '$($updateModule.ModuleVersion)'"
        }

        if ($moduleVersion -gt $existingVersion) {
            # Get the module file
            $moduleContentUrl = "https://www.powershellgallery.com/api/v2/package/$moduleName"
            do {
                # PS Core work-around for issue https://github.com/PowerShell/PowerShell/issues/4534
                try{
                    $moduleContentUrl = (Invoke-WebRequest -Uri $moduleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop).Headers.Location}
                catch{
                    $moduleContentUrl = $_.Exception.Response.Headers.Location.AbsoluteUri
                }
            } while ($moduleContentUrl -notlike "*.nupkg")
    
            Write-Log "Updating module '$moduleName' in automation account '$AutomationAccountName' from '$($updateModule.ExistingVersion)' to '$($updateModule.ModuleVersion)'..."
    
            $parameters = @{
                ResourceGroupName     = $ResourceGroupName
                AutomationAccountName = $AutomationAccountName
                Name                  = $moduleName
                ContentLink           = $moduleContentUrl
            }
            try {
                New-AzAutomationModule @parameters -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Log "Module '$moduleName' could not be updated..."
                Continue
            }

            # Check provisioning state
            while ($true) {
                $automationModule = Get-AzAutomationModule -Name $ModuleName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

                if (($automationModule.ProvisioningState -eq 'Succeeded') -or ($automationModule.ProvisioningState -eq 'Failed') ) {
                    break
                }

                Write-Log "Module '$($automationModule.Name)' provisioning state is '$($automationModule.ProvisioningState)'..."
                Start-Sleep -Seconds 10    
            }

            switch ($automationModule.ProvisioningState) {
                "Failed" { 
                    Exit-WithError "Update for module '$moduleName' has failed..." 
                }
                "Succeeded" { 
                    Write-Log "Module '$moduleName' update succeeded..." 
                }
                Default { 
                    Write-Log "Module '$moduleName' ended in state '$updateState'..." 
                }
            }
        }
        else {
            Write-Log "Module '$moduleName' does not need to be updated..."
        }

        $updatedModules.Add($updateModule.ModuleName) | Out-Null
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

# Bootstrap automation modules
Update-ExistingModule `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -ModuleName 'ComputerManagementDsc'

Import-Module-Custom `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -ModuleName 'cChoco' `
    -ModuleUri 'https://www.powershellgallery.com/api/v2/package/cChoco'

# Import DSC Configurations
Import-DscConfiguration `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'JumpBoxConfiguration' `
    -DscConfigurationScript 'JumpBoxConfiguration.ps1'

# Compile DSC Configurations
Start-DscCompilationJob `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DscConfigurationName 'JumpBoxConfiguration' `
    -VirtualMachineName $VmJumpboxWinName

Exit 0
#endregion
