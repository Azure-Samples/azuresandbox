# Creates a root certificate and a self-signed child certificate for use with Azure P2S VPN

# Set defaults
$defaultRootCertCN = "MyP2SVPNRootCert"
$defaultChildCertCN = "MyP2SVPNChildCert"

#Get user input
if (!($rootCertCN = Read-Host "Root certificate CN [$defaultRootCertCN]")) { $rootCertCN = $defaultRootCertCN }
if (!($childCertCN = Read-Host "Child certificate CN [$defaultChildCertCN]")) { $childCertCN = $defaultChildCertCN }

if (!($childCertPwd = Read-Host "Child certificate password" -AsSecureString)) { 
    Write-Host "Error: Strong client certificate password required."
    return 2 
}

$rootCertDerFilePath = ".\$($rootCertCN)_DER_Encoded.cer"
$rootCertBase64FilePath = ".\$($rootCertCN)_Base64_Encoded.cer"
$childCertPfxFilePath = ".\$($childCertCN).pfx"


Write-Host "Creating root certificate..."

$rootCert = New-SelfSignedCertificate `
    -Type Custom `
    -KeySpec Signature `
    -Subject "CN=$rootCertCN" `
    -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyUsageProperty Sign `
    -KeyUsage CertSign

Write-Host "Exporting root certificate..."
Export-Certificate -Cert $rootCert -FilePath $rootCertDerFilePath -Force
Start-Process -FilePath 'certutil.exe' -ArgumentList "-f -encode $rootCertDerFilePath $rootCertBase64FilePath" -WindowStyle Hidden
	
Write-Host "Creating child certificate..."

$childCert = New-SelfSignedCertificate `
    -Type Custom `
    -DnsName $childCertCertCn `
    -KeySpec Signature `
    -Subject "CN=$childCertCN" `
    -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $rootCert `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

Write-Host "Exporting child certificate..."
Export-PfxCertificate `
    -Cert $childCert `
    -FilePath $childCertPfxFilePath `
    -ChainOption BuildChain `
    -CryptoAlgorithmOption AES256_SHA256 `
    -Password $childCertPwd `
    -NoProperties `
    -Force

Write-Host "Child Certificate Thumbprint: $($childCert.Thumbprint)"

