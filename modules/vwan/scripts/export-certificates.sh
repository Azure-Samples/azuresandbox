#!/bin/bash

# Helper script for exporting the certificates required to authenticate with point-to-site VPN from a client machine
# Requires Terraform, Azure CLI, OpenSSL and jq packages to be installed
# Script must be run from the root module directory

# Retrieve self-signed root certificate in PEM format
root_cert_pem=$(terraform output -raw root_cert_pem)

# Retrieve the client certificate in PEM format from the Terraform output
client_cert_pem=$(terraform output -raw client_cert_pem)

# Retrieve the key vault name from the Terraform output
key_vault_name=$(terraform output -json resource_names | jq -r .key_vault)

# Retrieve the client private key in PEM format from the Azure Key Vault
client_key_pem=$(az keyvault secret show --name p2svpn-client-private-key-pem --vault-name $key_vault_name --query value -o tsv)

# Retrieve the admin password from the Azure Key Vault for use as client certificate passkey
client_cert_passkey=$(az keyvault secret show --name adminpassword --vault-name $key_vault_name --query value -o tsv)

# Export client certificate in PFX format to file 'client_cert.pfx'
openssl pkcs12 -export -out client_cert.pfx \
  -inkey <(echo "$client_key_pem") \
  -in <(echo "$client_cert_pem") \
  -certfile <(echo "$root_cert_pem") \
  -passout pass:"$client_cert_passkey"
