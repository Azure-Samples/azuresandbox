Write-Host "Generating Kerberos key for storage account '$storageAccountName'..."
$kerberosKey = (New-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -KeyName "kerb1").Value
Write-Host "Kerberos key generated successfully."

