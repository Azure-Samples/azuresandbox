# This script must be run on a domain joined Azure VM

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$AppSecret,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountKerbKey,
    
    [Parameter(Mandatory = $true)]
    [string]$Domain
)

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

$xDot500Path="DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"
$password = ConvertTo-SecureString $StorageAccountKerbKey -AsPlainText -Force
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

Write-Log "Adding computer account for storage account '$StorageAccountName' to domain '$Domain'..."

try {
    New-ADComputer `
        -SAMAccountName $StorageAccountName `
        -Path $xDot500Path `
        -Name $StorageAccountName `
        -AccountPassword $password `
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

Write-Log "Configuring storage account '$StorageAccountName' for Kerberos authentication with domain '$Domain'..."

try{
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

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
