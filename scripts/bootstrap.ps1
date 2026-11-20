#!/usr/bin/env pwsh

# Creates a terraform.tfvars file for Azure Sandbox that authenticates Terraform as the user
# signed in with Azure CLI (auth_mode = "azure_cli", the default).
# Requires Azure PowerShell module and Azure CLI

#region functions
function Show-Usage {
    Write-Host "Usage: .\bootstrap.ps1" -ForegroundColor Red
    exit 1
}

function Show-JWTtoken {

    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [SecureString]$token
    )

    # Convert SecureString to plain text
    $plainToken = [System.Net.NetworkCredential]::new("", $token).Password

    # Validate as per https://tools.ietf.org/html/rfc7519
    # Access and ID tokens are fine, Refresh tokens will not work
    if (!$plainToken.Contains(".") -or !$plainToken.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }

    # Header
    $tokenheader = $plainToken.Split(".")[0].Replace('-', '+').Replace('_', '/')
    # Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
    while ($tokenheader.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenheader += "=" }
    Write-Verbose "Base64 encoded (padded) header:"
    Write-Verbose $tokenheader
    # Convert from Base64 encoded string to PSObject all at once
    Write-Verbose "Decoded header:"
    [System.Text.Encoding]::ASCII.GetString([system.convert]::FromBase64String($tokenheader)) | ConvertFrom-Json | Format-List | Out-Null

    # Payload
    $tokenPayload = $plainToken.Split(".")[1].Replace('-', '+').Replace('_', '/')
    # Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
    while ($tokenPayload.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenPayload += "=" }
    Write-Verbose "Base64 encoded (padded) payload:"
    Write-Verbose $tokenPayload
    # Convert to Byte array
    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    # Convert to string array
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
    Write-Verbose "Decoded array in JSON format:"
    Write-Verbose $tokenArray
    # Convert from JSON to PSObject
    $tokobj = $tokenArray | ConvertFrom-Json
    Write-Verbose "Decoded Payload:"
    
    return $tokobj
}#endregion

#region constants
# Initialize constants
$defaultCostCenter = "mycostcenter"
$defaultEnvironment = "dev"
$defaultLocation = "southcentralus"
$defaultProject = "sand"
#endregion

#region main

# Terraform authenticates with Azure CLI, so it must be installed and signed in
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI could not be found. Please install Azure CLI." -ForegroundColor Red
    Show-Usage
}

az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "You are not logged into Azure CLI. Please run 'az login' first." -ForegroundColor Red
    Show-Usage
}

# Ensure Azure PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Azure PowerShell module is not installed. Please install it using 'Install-Module -Name Az'." -ForegroundColor Red
    Show-Usage
}

# Connect to Azure if not already connected
if (-not (Get-AzContext)) {
    Write-Host "You are not logged into Azure. Please log in." -ForegroundColor Yellow
    Connect-AzAccount -UseDeviceAuthentication
}

# Retrieve runtime defaults
Write-Host "Retrieving runtime defaults ..."

# Set default subscription from currently logged in Azure PowerShell session
$defaultSubscriptionId = (Get-AzContext).Subscription.Id
if (-not $defaultSubscriptionId) {
    Write-Host "Unable to retrieve Azure subscription details. Please log in using 'Connect-AzAccount'." -ForegroundColor Red
    Show-Usage
}

# Set default user from currently logged in Azure PowerShell session
$defaultOperatorObjectId = (Show-JWTtoken -token (Get-AzAccessToken -AsSecureString).Token).oid

# Set default Microsoft Entra tenant id from currently logged in Azure PowerShell session
$defaultEntraTenantId = (Get-AzContext).Tenant.Id

# Get user input
$entraTenantId = Read-Host "Microsoft Entra tenant id (entra_tenant_id) default '$defaultEntraTenantId'"

if (-not $entraTenantId) {
    $entraTenantId = $defaultEntraTenantId
}

$operatorObjectId = Read-Host "Operator object id (operator_object_id) default '$defaultOperatorObjectId'"

if (-not $operatorObjectId) {
    $operatorObjectId = $defaultOperatorObjectId
}

$subscriptionId = Read-Host "Azure subscription id (subscription_id) default '$defaultSubscriptionId'"

if (-not $subscriptionId) {
    $subscriptionId = $defaultSubscriptionId
}

$location = Read-Host "Azure location (location) default '$defaultLocation'"

if (-not $location) {
    $location = $defaultLocation
}

$environment = Read-Host "Environment tag value (environment) default '$defaultEnvironment'"

if (-not $environment) {
    $environment = $defaultEnvironment
}

$costCenter = Read-Host "Cost center tag value (costcenter) default '$defaultCostCenter'"

if (-not $costCenter) {
    $costCenter = $defaultCostCenter
}

$project = Read-Host "Project tag value (project) default '$defaultProject'"

if (-not $project) {
    $project = $defaultProject
}

# Validate subscription
$subscriptionName = (Get-AzSubscription -SubscriptionId $subscriptionId).Name
if ($subscriptionName) {
    Write-Host "Found subscription '$subscriptionName'..."
} else {
    Write-Host "Invalid subscription id '$subscriptionId'." -ForegroundColor Red
    Show-Usage
}

# Validate location
$locationDisplayName = (Get-AzLocation | Where-Object { $_.Location -eq $location }).DisplayName
if ($locationDisplayName) {
    Write-Host "Found location '$locationDisplayName'..."
} else {
    Write-Host "Invalid location '$location'." -ForegroundColor Red
    Show-Usage
}

# Build tags map
$tags = @{
    project     = $project
    costcenter  = $costCenter
    environment = $environment
}

# Generate terraform.tfvars file
Write-Host "`nGenerating terraform.tfvars file...`n"

@"
entra_tenant_id    = "$entraTenantId"
location           = "$location"
operator_object_id = "$operatorObjectId"
subscription_id    = "$subscriptionId"

tags = {
  project     = "$($tags.project)"
  costcenter  = "$($tags.costcenter)"
  environment = "$($tags.environment)"
}

# Enable modules here

# enable_module_vnet_app         = true
# enable_module_vm_jumpbox_linux = true
# enable_module_vm_mssql_win     = true
# enable_module_mssql            = true
# enable_module_mysql            = true
# enable_module_vwan             = true

# Enable extra modules here

# enable_module_petstore         = true
# enable_module_avd              = true
# enable_module_vnet_onprem      = true
"@ | Out-File -FilePath ./terraform.tfvars -Encoding utf8

Get-Content ./terraform.tfvars

exit 0
#endregion
