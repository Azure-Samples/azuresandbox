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
    [String]$ContainerRegistryId,

    [Parameter(Mandatory = $true)]
    [String]$SourceContainerImage,

    [Parameter(Mandatory = $true)]
    [String]$SourceContainerRegistry,

    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [String]$AppSecret
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

# Get container registry
$registryName = ($ContainerRegistryId -split '/')[-1]
Write-Log "Getting container registry '$registryName'..."

try {
    $containerRegistry = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $registryName -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

# Check to see if the image already exists
$imageParts = $SourceContainerImage -split ':'
$tag = if ($imageParts.Length -gt 1) { $imageParts[1] } else { 'latest' }
$repositoryNameParts = $imageParts[0] -split "/"
$repositoryName = if ($repositoryNameParts.Length -gt 1) {$repositoryNameParts[1]} else {$repositoryNameParts[0]}

Write-Log "Attempting to import container image '$SourceContainerImage' from '$SourceContainerRegistry' to '$registryName'..."

$importSucceeded = $true
try {
    Import-AzContainerRegistryImage `
        -SourceImage $SourceContainerImage `
        -ResourceGroupName $ResourceGroupName `
        -RegistryName $containerRegistry.Name `
        -SourceRegistryUri $SourceContainerRegistry `
        -TargetTag "${repositoryName}:$tag" `
        -ErrorAction Stop
}
catch {
    $importSucceeded = $false
    Write-Log "Import failed: $($_.Exception.Message)"
}

if ($importSucceeded) {
    Write-Log "Successfully imported image '$SourceContainerImage' to Azure Container Registry '$registryName'."
} else {
    Write-Log "Continuing execution despite import failure."
}

Disconnect-AzAccount | Out-Null

exit 0
#endregion
