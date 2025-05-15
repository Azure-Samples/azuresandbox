#!/usr/bin/env pwsh

# Helper script for exporting the certificates required to authenticate with point-to-site VPN from a client machine
# Requires Terraform, OpenSSL and PowerShell Az module to be installed
# Script must be run from root module directory

# Export self-signed root certificate in PEM format to file 'root_cert.pem'
terraform output -raw root_cert_pem > root_cert.pem

# Retrieve the client certificate in PEM format from the Terraform output
terraform output -raw client_cert_pem > client_cert.pem

# Retrieve the key vault name from the Terraform output
$keyVaultName = (terraform output -json resource_names | ConvertFrom-Json).key_vault

# Retrieve the client private key in PEM format from the Azure Key Vault
$clientKeyPem = (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'p2svpn-client-private-key-pem' -AsPlainText)

# Retrieve the admin password from the Azure Key Vault for use as client certificate passkey
$clientCertPasskey = (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'adminpassword' -AsPlainText)

# Write the private key and client certificate to temporary files
Set-Content -Path "client_key.pem" -Value $clientKeyPem

# Use OpenSSL to create the PFX file
openssl pkcs12 -export -out client_cert.pfx -inkey client_key.pem -in client_cert.pem -certfile root_cert.pem -passout pass:$clientCertPasskey

# Clean up temporary files
Remove-Item -Path "root_cert.pem", "client_key.pem", "client_cert.pem"
