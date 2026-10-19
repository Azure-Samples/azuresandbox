#!/usr/bin/env pwsh

# Creates a terraform.tfvars file for this configuration
# Requires Azure PowerShell module. Terraform itself authenticates as the operator signed in to Azure CLI (az login),
# so no service principal is needed.

#region functions
function Show-Usage {
    Write-Host "Usage: .\bootstrap.ps1" -ForegroundColor Red
    exit 1
}

#endregion

#region constants
# Initialize constants
$defaultCostCenter = "mycostcenter"
$defaultEnvironment = "dev"
$defaultLocation = "centralus"
$defaultProject = "devops"
#endregion

#region main
# Terraform authenticates with Azure CLI, so it must be installed and signed in
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI could not be found. Please install Azure CLI." -ForegroundColor Red
    Show-Usage
}

az account show --only-show-errors --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Azure CLI is not signed in. Please run 'az login' first." -ForegroundColor Red
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

# Set default Microsoft Entra tenant id from currently logged in Azure PowerShell session
$defaultEntraTenantId = (Get-AzContext).Tenant.Id

# Get user input
$entraTenantId = Read-Host "Microsoft Entra tenant id (entra_tenant_id) default '$defaultEntraTenantId'"

if (-not $entraTenantId) {
    $entraTenantId = $defaultEntraTenantId
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
entra_tenant_id = "$entraTenantId"
location        = "$location"
subscription_id = "$subscriptionId"

tags = {
  project     = "$($tags.project)"
  costcenter  = "$($tags.costcenter)"
  environment = "$($tags.environment)"
}
"@ | Out-File -FilePath ./terraform.tfvars -Encoding utf8

Get-Content ./terraform.tfvars

exit 0
#endregion
