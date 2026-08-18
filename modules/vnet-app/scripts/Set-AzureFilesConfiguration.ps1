#region parameters
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string]$Domain
)
#endregion

#region constants
$defaultPermission = "StorageFileDataSmbShareContributor"
$logpath = $PSCommandPath + '.log'
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
Write-Log "Running '$PSCommandPath'..."

Write-Log "Setting execution policy to 'RemoteSigned'..."
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Authenticate with the VM managed identity. Keep the context in this process
# only so no credential material is written to the user profile.
Write-Log "Disabling Azure PowerShell context autosave for this process..."
Disable-AzContextAutosave -Scope Process | Out-Null

Write-Log "Logging into Azure using managed identity..."

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
}
catch {
    Exit-WithError $_
}

Write-Log "Setting default subscription to '$SubscriptionId'..."

try {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}
catch {
    Exit-WithError $_
}

# Configure identity-based access for the storage account using the VM managed identity
$xDot500Path = "DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"
$spnValue = "cifs/$StorageAccountName.file.core.windows.net"

Write-Log "Checking for existing computer account for storage account '$StorageAccountName' in domain '$Domain'..."

$computer = Get-ADComputer -Identity $StorageAccountName

if ($null -eq $computer) {
    Write-Log "Existing computer account for storage account '$StorageAccountName' in domain '$Domain' not found..."
}
else {
    Write-Log "Deleting existing computer account for storage account '$StorageAccountName' in domain '$Domain'..."

    try {
        Remove-ADComputer -Identity $StorageAccountName -Confirm:$false -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }
}

Write-Log "Creating 'kerb1' key for storage account '$StorageAccountName' in resource group '$ResourceGroupName'..."

try {
    New-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -KeyName "kerb1" | Out-Null
}
catch {
    Exit-WithError $_
}

Write-Log "Getting 'kerb1' key for storage account '$StorageAccountName' in resource group '$ResourceGroupName'..."

$storageAccountKerbKey = Get-AzStorageAccountKey -ListKerbKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName | Where-Object { $_.KeyName -eq "kerb1" } | Select-Object -ExpandProperty Value

if ([string]::IsNullOrEmpty($storageAccountKerbKey)) {
    Exit-WithError "Key 'kerb1' not found for storage account '$StorageAccountName' in resource group '$ResourceGroupName'..."
}

Write-Log "The length of key 'kerb1' for storage account '$StorageAccountName' is '$($storageAccountKerbKey.Length)'..."

Write-Log "Adding computer account for storage account '$StorageAccountName' to domain '$Domain'..."
$storageAccountKerbKeySecure = ConvertTo-SecureString $storageAccountKerbKey -AsPlainText -Force

try {
    New-ADComputer `
        -SAMAccountName $StorageAccountName `
        -Path $xDot500Path `
        -Name $StorageAccountName `
        -AccountPassword $storageAccountKerbKeySecure `
        -AllowReversiblePasswordEncryption $false `
        -Description "Computer account object for Azure storage account '$StorageAccountName'." `
        -ServicePrincipalNames $spnValue `
        -Server $Domain `
        -Enabled $true `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-Log "Retrieving new computer account for storage account '$StorageAccountName'..."

try {
    $computer = Get-ADComputer -Identity $StorageAccountName
}
catch {
    Exit-WithError $_
}

$azureStorageSid = $computer.SID.Value
$domainInformation = Get-ADDomain -Server $Domain
$domainGuid = $domainInformation.ObjectGUID.ToString()
$domainName = $domainInformation.DNSRoot
$domainSid = $domainInformation.DomainSID.Value
$forestName = $domainInformation.Forest
$netBiosDomainName = $domainInformation.DnsRoot

Write-Log "Configuring storage account '$StorageAccountName' for Kerberos authentication with domain '$Domain'..."

try {
    Set-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -AccountName $StorageAccountName `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $domainName `
        -ActiveDirectoryNetBiosDomainName $netBiosDomainName `
        -ActiveDirectoryForestName $forestName `
        -ActiveDirectoryDomainGuid $domainGuid `
        -ActiveDirectoryDomainSid $domainSid `
        -ActiveDirectoryAzureStorageSid $azureStorageSid `
        -DefaultSharePermission $defaultPermission `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Disconnect-AzAccount

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
