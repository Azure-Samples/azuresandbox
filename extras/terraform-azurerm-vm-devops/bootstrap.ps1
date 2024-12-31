# bootstrap script to prepare the environment for the Terraform deployment
# Author: rdoherty@microsoft.com (GitHub @doherty100)

#region parameters

param(
    [Parameter(Mandatory=$true)]
    [string]$JsonConfigFile
)

#endregion

#region constants

$ErrorActionPreference = "Stop"
$minPSVersion = [Version]"7.4.1"
$minPSAzureVersion = [Version]"11.3.1"

#endregion

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Output
}
function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    throw $msg
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

function Import-Module {
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
    
        if ($updateModule.ModuleVersion -gt $updateModule.ExistingVersion) {
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
function Start-DscCompliationJob {
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

    Write-Log "Compliling DSC Configuration '$DscConfigurationName' for virtual machine '$VirtualMachineName'..."

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
                -Encrypted $true `
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
                -Encrypted $true `
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

function Set-Credential {
    param (
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]$AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter(Mandatory = $true)]
        [String]$Description,

        [Parameter(Mandatory = $true)]
        [String]$UserName,

        [Parameter(Mandatory = $true)]
        [String]$UserSecret        
    )

    Write-Log "Setting automation credential '$Name'..."

    try {
        $automationCredential = Get-AzAutomationCredential `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -ErrorAction Stop `
        | Where-Object { $_.Name -eq $Name }
    }
    catch {
        Exit-WithError $_
    }
    
    $userSecretSecure = ConvertTo-SecureString $UserSecret -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $userSecretSecure
    
    if ($null -eq $automationCredential) {
        try {
            $automationCredential = New-AzAutomationCredential `
                -Name $Name `
                -Description $Description `
                -Value $credential `
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
            $automationCredential = Set-AzAutomationCredential `
                -Name $Name `
                -Description $Description `
                -Value $credential `
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
# Check Powershell version
$currentPSVersion = $PSVersionTable.PSVersion
Write-Log "Current PowerShell version is '$($currentPSVersion)'..."

if ($currentPSVersion -lt $minPSVersion) {
    throw "Current PowerShell version '$currentPSVersion' is less than the minimum required version '$minPSVersion'..."
}

# Check PowerShell Azure Module version
if (Get-Module -ListAvailable -Name 'Az') {
    Write-Log "Module 'Az' is installed."
} else {
    Exit-WithError "Powershell module 'Az' is not installed..."
}

$currentAzVersion = (Get-Module -ListAvailable -Name 'Az' | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Log "Current PowerShell Az module version is '$($currentAzVersion)'..."

if ($currentAzVersion -lt $minPSAzureVersion) {
    Exit-WithError "Current PowerShell Az module version '$currentAzVersion' is less than the minimum required version '$minPSAzureVersion'..."
}

# Validate the required environment variables
if ([string]::IsNullOrEmpty($env:TF_VAR_arm_client_secret)) {
    Exit-WithError "Environment variable 'TF_VAR_arm_client_secret' is not set..."
}

# Validate Json Config File

# Validate Json Config File
$fileName = Split-Path -Path $JsonConfigFile -Leaf

if ($fileName -ne $JsonConfigFile) {
    Exit-WithError "Json Config File '$JsonConfigFile' should be a filename with no path..."
}

if (-not (Test-Path -Path ".\$JsonConfigFile")) {
    Exit-WithError "Json Config File '$JsonConfigFile' does not exist in the working directory..."
}

# Get config values
Write-Log "Reading Json configuration from '$JsonConfigFile' file..."

try {
    $config = Get-Content -Path ".\$JsonConfigFile" -Raw | ConvertFrom-Json
} catch {
    Exit-WithError "Failed to read '$JsonConfigFile' file, check to ensure it is well formed..."
}

$aad_tenant_id = $config.aad_tenant_id
$adds_domain_name = $config.adds_domain_name
$admin_password_secret = $config.admin_password_secret
$admin_username_secret = $config.admin_username_secret
$automation_account_id = $config.automation_account_id
$arm_client_id = $config.arm_client_id
$domain_admin_password_secret = $config.domain_admin_password_secret
$domain_admin_username_secret = $config.domain_admin_username_secret
$key_vault_id = $config.key_vault_id
$location = $config.location
$resource_group_name = $config.resource_group_name
$storage_account_name = $config.storage_account_name
$storage_container_name = $config.storage_container_name
$subnet_id = $config.subnet_id
$subscription_id = $config.subscription_id
$tags = $config.tags
$vm_devops_win_config_script = $config.vm_devops_win_config_script
$vm_devops_win_data_disk_size_gb = $config.vm_devops_win_data_disk_size_gb
$vm_devops_win_dsc_config = $config.vm_devops_win_dsc_config
$vm_devops_win_image_offer = $config.vm_devops_win_image_offer
$vm_devops_win_image_publisher = $config.vm_devops_win_image_publisher
$vm_devops_win_image_sku = $config.vm_devops_win_image_sku
$vm_devops_win_image_version = $config.vm_devops_win_image_version
$vm_devops_win_instances = $config.vm_devops_win_instances
$vm_devops_win_instances_start = $config.vm_devops_win_instances_start
$vm_devops_win_license_type = $config.vm_devops_win_license_type
$vm_devops_win_name = $config.vm_devops_win_name
$vm_devops_win_os_disk_size_gb = $config.vm_devops_win_os_disk_size_gb
$vm_devops_win_patch_mode = $config.vm_devops_win_patch_mode
$vm_devops_win_size = $config.vm_devops_win_size
$vm_devops_win_storage_account_type = $config.vm_devops_win_storage_account_type

# Validate vm_devops_win_instances
if ($vm_devops_win_instances -lt 1 -or $vm_devops_win_instances -gt 1000) {
    Exit-WithError "Invalid vm_devops_win_instances '$vm_devops_instances', must be between 1 and 1000..."
}

# Validate vm_devops_win_instances_start
if ($vm_devops_win_instances_start -lt 0 -or $vm_devops_win_instances_start -gt 999) {
    Exit-WithError "Invalid vm_devops_win_instances_start '$vm_devops_win_instances_start', must be between 0 and 999..."
}

# Validate maximum instance number
$max_instance_num = $vm_devops_win_instances_start + $vm_devops_win_instances - 1

if ($max_instance_num -gt 999) {
    Exit-WithError "Invalid max instance number '$max_instance_num', must be less than 1000..."
}

# Validate vm_devops_win_os_disk_size_gb
if ($vm_devops_win_os_disk_size_gb -lt 128) {
    Exit-WithError "Invalid vm_devops_win_os_disk_size_gb '$vm_devops_win_os_disk_size_gb', must a minimum of 128..."
}

# Validate vm_devops_win_data_disk_size_gb
if ($vm_devops_win_data_disk_size_gb -lt 0 -or $vm_devops_win_data_disk_size_gb -ge 32768) {
    Exit-WithError "Invalid vm_devops_win_data_disk_size_gb '$vm_devops_win_data_disk_size_gb', must be between 0 and 32767 Gb..."
}

# Validate vm_devops_win_dsc_config
if (-not (Test-Path -Path ".\$vm_devops_win_dsc_config.ps1")) {
    Exit-WithError "Script '.\$vm_devops_win_dsc_config.ps1' does not exist..."
}

# Validate vm_devops_win_config_script
if (-not (Test-Path -Path ".\$vm_devops_win_config_script")) {
    Exit-WithError "Script '.\$vm_devops_win_config_script' does not exist..."
}

# Connect to Azure
Write-Log "Connecting to Azure using service principal '$arm_client_id'..."

$securePassword = ConvertTo-SecureString -String $env:TF_VAR_arm_client_secret -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arm_client_id, $securePassword

try {
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $aad_tenant_id | Out-Null
} catch {
    Exit-WithError "Failed to connect to Azure: $_"
}

# Set default subscription
Write-Log "Setting default subscription to '$subscription_id'..."

try {
    Set-AzContext -Subscription $subscription_id | Out-Null
} catch {
    Exit-WithError "Failed to set default subscription: $_"
}

# Validate resource group
Write-Log "Validating resource group '$resource_group_name'..."

try {
    Get-AzResourceGroup -Name $resource_group_name | Out-Null
} catch {
    Exit-WithError "Resource group '$resource_group_name' does not exist..."
}

# Get key vault secrets
$key_vault_name = Split-Path -Path $key_vault_id -Leaf

try {
    $admin_username = Get-AzKeyVaultSecret -VaultName $key_vault_name -Name $admin_username_secret -AsPlainText
} catch {
    Exit-WithError "Failure getting '$admin_username_secret' from key vault '$key_vault_name'..."
}

if ([string]::IsNullOrEmpty($admin_username)) {
    Exit-WithError "Secret '$admin_username_secret' in key vault '$key_vault_name' returned a null or empty value..."
}

Write-Log "Value of secret '$admin_username_secret' is '$admin_username'..."

try {
    $admin_password = Get-AzKeyVaultSecret -VaultName $key_vault_name -Name $admin_password_secret -AsPlainText
} catch {
    Exit-WithError "Failure getting '$admin_password_secret' from key vault '$key_vault_name'..."
}

if ([string]::IsNullOrEmpty($admin_password)) {
    Exit-WithError "Secret '$admin_password_secret' in key vault '$key_vault_name' returned a null or empty value..."
}

Write-Log "Length of secret '$admin_password_secret' is '$($admin_password.Length)'..."

try {
    $domain_admin_username = Get-AzKeyVaultSecret -VaultName $key_vault_name -Name $domain_admin_username_secret -AsPlainText
} catch {
    Exit-WithError "Failure getting '$domain_admin_username_secret' from key vault '$key_vault_name'..."
}

if ([string]::IsNullOrEmpty($domain_admin_username)) {
    Exit-WithError "Secret '$domain_admin_username_secret' in key vault '$key_vault_name' returned a null or empty value..."
}

Write-Log "Value of secret '$domain_admin_username_secret' is '$admin_username'..."

try {
    $domain_admin_password = Get-AzKeyVaultSecret -VaultName $key_vault_name -Name $domain_admin_password_secret -AsPlainText
} catch {
    Exit-WithError "Failure getting '$domain_admin_password_secret' from key vault '$key_vault_name'..."
}

if ([string]::IsNullOrEmpty($domain_admin_password)) {
    Exit-WithError "Secret '$domain_admin_password_secret' in key vault '$key_vault_name' returned a null or empty value..."
}

Write-Log "Length of secret '$domain_admin_password_secret' is '$($admin_password.Length)'..."

try {
    $storage_account_key = Get-AzKeyVaultSecret -VaultName $key_vault_name -Name $storage_account_name -AsPlainText
} catch {
    Exit-WithError "Failure getting secret '$storage_account_name' from key vault '$key_vault_name'..."
}

if ([string]::IsNullOrEmpty($storage_account_key)) {
    Exit-WithError "Secret '$storage_account_name' in key vault '$key_vault_name' returned a null or empty value..."
}

Write-Log "Length of secret '$storage_account_name' is '$($storage_account_key.Length)'..."

# Validate subnet
Write-Log "Validating subnet '$subnet_id'..."

$subnet_id_parts = $subnet_id.Split("/")
$vnet_resource_group_name = $subnet_id_parts[4]
$vnet_name = $subnet_id_parts[-3]
$subnet_name = $subnet_id_parts[-1]

try {
    $vnet = Get-AzVirtualNetwork -Name $vnet_name -ResourceGroupName $vnet_resource_group_name
} catch {
    Exit-WithError "Virtual network '$vnet_name' does not exist in resource group '$vnet_resource_group_name'..."
}

try {
    Get-AzVirtualNetworkSubnetConfig -Name $subnet_name -VirtualNetwork $vnet | Out-Null
} catch {
    Exit-WithError "Subnet '$subnet_id' does not exist..."
}

# Temporarily enable public internet access on storage account
Write-Log "Enabling public internet access on storage account '$storage_account_name'..."

try {
    Set-AzStorageAccount -ResourceGroupName $resource_group_name -Name $storage_account_name -PublicNetworkAccess "Enabled" | Out-Null 
} catch {
    Exit-WithError "Failed to enable public internet access on storage account '$storage_account_name': $_"
}

Write-Log "Pausing for 60 seconds to allow storage account settings to propogate..."
Start-Sleep -Seconds 60

# Upload script to storage account
Write-Log "Uploading script '$vm_devops_win_config_script' to container '$storage_container_name' in '$storage_account_name'..."

try {
    $storage_context = New-AzStorageContext -StorageAccountName $storage_account_name -UseConnectedAccount
} catch {
    Exit-WithError $_.Exception.Message
}

$blob = @{
    File             = ".\$vm_devops_win_config_script"
    Container        = $storage_container_name
    Blob             = $vm_devops_win_config_script
    Context          = $storage_context
}

try {
    Set-AzStorageBlobContent @blob -Force | Out-Null
} catch {
    Exit-WithError "Failed to upload script '$vm_devops_win_config_script' to container '$storage_container_name' in storage account '$storage_account_name': $_"
}

# Disable public internet access on storage account
Write-Log "Disabling public internet access on storage account '$storage_account_name'..."

try {
    Set-AzStorageAccount -ResourceGroupName $resource_group_name -Name $storage_account_name -PublicNetworkAccess "Disabled" | Out-Null 
} catch {
    Exit-WithError "Failed to disable public internet access on storage account '$storage_account_name': $_"
}

# Configure automation account
$automation_account_parts = $automation_account_id.Split("/")
$automation_account_resource_group_name = $automation_account_parts[4]
$automation_account_name = $automation_account_parts[8]

Write-Log "Configuring automation account '$automation_account_name' in resource group '$automation_account_resource_group_name'..."

try {
    Get-AzAutomationAccount -Name $automation_account_name -ResourceGroupName $automation_account_resource_group_name | Out-Null
} catch {
    Exit-WithError "Automation account '$automation_account_name' does not exist in resource gruop '$automation_account_resource_group_name'..."
}

Update-ExistingModule `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -ModuleName 'PSDscResources'

Update-ExistingModule `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -ModuleName 'xDSCDomainjoin'

Import-Module `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -ModuleName 'cChoco' `
    -ModuleUri 'https://www.powershellgallery.com/api/v2/package/cChoco'

Set-Variable `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -VariableName 'adds_domain_name' `
    -VariableValue $adds_domain_name

Set-Credential `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -Name 'domainadmin' `
    -Description 'Domain admin account credential' `
    -UserName $($adds_domain_name + '\' + $domain_admin_username) `
    -UserSecret $domain_admin_password 

Import-DscConfiguration `
    -ResourceGroupName $automation_account_resource_group_name `
    -AutomationAccountName $automation_account_name `
    -DscConfigurationName $vm_devops_win_dsc_config `
    -DscConfigurationScript "$vm_devops_win_dsc_config.ps1"

for ($i = $vm_devops_win_instances_start; $i -le ($vm_devops_win_instances_start + $vm_devops_win_instances - 1); $i++ ) {
    $virtual_machine_name = "$vm_devops_win_name{0:D3}" -f $i

    Start-DscCompliationJob `
        -ResourceGroupName $automation_account_resource_group_name `
        -AutomationAccountName $automation_account_name `
        -DscConfigurationName $vm_devops_win_dsc_config `
        -VirtualMachineName $virtual_machine_name
}
    
# Disconnect from Azure
Write-Log "Disconnecting from Azure..."
Disconnect-AzAccount | Out-Null

# Create terraform.tfvars file
$tfvarsPath = ".\terraform.tfvars"
Write-Log "Generating '$tfvarsPath' file..."

Set-Content -Path $tfvarsPath -Value "aad_tenant_id = `"$aad_tenant_id`""
Add-Content -Path $tfvarsPath -Value "admin_password_secret = `"$admin_password_secret`""
Add-Content -Path $tfvarsPath -Value "admin_username_secret = `"$admin_username_secret`""
Add-Content -Path $tfvarsPath -Value "automation_account_id = `"$automation_account_id`""
Add-Content -Path $tfvarsPath -Value "arm_client_id = `"$arm_client_id`""
Add-Content -Path $tfvarsPath -Value "key_vault_id = `"$key_vault_id`""
Add-Content -Path $tfvarsPath -Value "location = `"$location`""
Add-Content -Path $tfvarsPath -Value "resource_group_name = `"$resource_group_name`""
Add-Content -Path $tfvarsPath -Value "storage_account_name = `"$storage_account_name`""
Add-Content -Path $tfvarsPath -Value "storage_container_name = `"$storage_container_name`""
Add-Content -Path $tfvarsPath -Value "subnet_id = `"$subnet_id`""
Add-Content -Path $tfvarsPath -Value "subscription_id = `"$subscription_id`""
Add-Content -Path $tfvarsPath -Value "tags = $(ConvertTo-Json($tags))"
Add-Content -Path $tfvarsPath -Value "vm_devops_win_config_script = `"$vm_devops_win_config_script`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_data_disk_size_gb = $vm_devops_win_data_disk_size_gb"
Add-Content -Path $tfvarsPath -Value "vm_devops_win_dsc_config = `"$vm_devops_win_dsc_config`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_image_offer = `"$vm_devops_win_image_offer`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_image_publisher = `"$vm_devops_win_image_publisher`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_image_sku = `"$vm_devops_win_image_sku`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_image_version = `"$vm_devops_win_image_version`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_instances = $vm_devops_win_instances"
Add-Content -Path $tfvarsPath -Value "vm_devops_win_instances_start = $vm_devops_win_instances_start"
Add-Content -Path $tfvarsPath -Value "vm_devops_win_license_type = `"$vm_devops_win_license_type`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_name = `"$vm_devops_win_name`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_os_disk_size_gb = $vm_devops_win_os_disk_size_gb"
Add-Content -Path $tfvarsPath -Value "vm_devops_win_patch_mode = `"$vm_devops_win_patch_mode`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_size = `"$vm_devops_win_size`""
Add-Content -Path $tfvarsPath -Value "vm_devops_win_storage_account_type = `"$vm_devops_win_storage_account_type`""

Write-Log "Bootstrapping complete..."
#endregion
