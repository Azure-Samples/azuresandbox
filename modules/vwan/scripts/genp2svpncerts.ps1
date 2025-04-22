# Creates a root certificate and a self-signed child certificate for use with Azure P2S VPN

# Set defaults
$defaultRootCertCN = "MyP2SVPNRootCert"
$defaultChildCertCN = "MyP2SVPNChildCert"

# Get user input
do {
    $rootCertCN = Read-Host "Root certificate CN [$defaultRootCertCN]"
    if ($rootCertCN.Trim().Length -eq 0) {
        $rootCertCN = $defaultRootCertCN
    }
} until ($rootCertCN.Trim().Length -gt 0)

do {
    $childCertCN = Read-Host "Child certificate CN [$defaultChildCertCN]"
    if ($childCertCN.Trim().Length -eq 0) {
        $childCertCN = $defaultChildCertCN
    }
} until ($childCertCN.Trim().Length -gt 0)

do {
    $childCertPwd = Read-Host "Child certificate password" -AsSecureString
    $plainTextPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($childCertPwd))
} until ($plainTextPwd.Trim().Length -gt 0)

# Clear the plain text password from memory
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($childCertPwd))

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
