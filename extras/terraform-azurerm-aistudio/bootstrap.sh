#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

# Initialize runtime defaults
default_owner_object_id=$(az account get-access-token --query accessToken --output tsv | tr -d '\n' | python3 -c "import jwt, sys; print(jwt.decode(sys.stdin.read(), algorithms=['RS256'], options={'verify_signature': False})['oid'])")
state_file="../../terraform-azurerm-vnet-shared/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

aad_tenant_id=$(terraform output -state=$state_file aad_tenant_id)
arm_client_id=$(terraform output -state=$state_file arm_client_id)
key_vault_id=$(terraform output -state=$state_file key_vault_id)
key_vault_name=$(terraform output -state=$state_file key_vault_name)
location=$(terraform output -state=$state_file location)
resource_group_name=$(terraform output -state=$state_file resource_group_name)
storage_account_name=$(terraform output -state=$state_file storage_account_name)
subscription_id=$(terraform output -state=$state_file subscription_id)
tags=$(terraform output -json -state=$state_file tags)

state_file="../../terraform-azurerm-vnet-app/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

private_dns_zones=$(terraform output -json -state=$state_file private_dns_zones)
storage_share_name=$(terraform output -state=$state_file storage_share_name)
vnet_app_01_subnets=$(terraform output -json -state=$state_file vnet_app_01_subnets)

# Get user input
read -e -i $default_owner_object_id -p "Object id for Azure CLI signed in user (owner_object_id) -: " owner_object_id

# Validate user input
owner_object_id=${owner_object_id:-$default_owner_object_id}

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Validate object id of Azure CLI signed in user
if [ -z "$owner_object_id" ]
then
  printf "Object id for Azure CLI signed in user (owner_object_id) not provided.\n"
  usage
fi

# Upload documents
printf "Temporarily enabling public internet access and shared key access on storage account '${storage_account_name:1:-1}'...\n"
az storage account update \
  --subscription ${subscription_id:1:-1} \
  --name ${storage_account_name:1:-1} \
  --resource-group ${resource_group_name:1:-1} \
  --public-network-access Enabled \
  --allow-shared-key-access true

printf "Sleeping for 15 seconds to allow storage account settings to propogate...\n"
sleep 15

printf "Getting storage account key for storage account '${storage_account_name:1:-1}' from key vault '${key_vault_name:1:-1}'...\n"
storage_account_key=$(az keyvault secret show --name ${storage_account_name:1:-1} --vault-name ${key_vault_name:1:-1} --query value --output tsv)

for i in {1..12}
do
  printf "Attempt $i: Uploading documents to share '${storage_share_name:1:-1}' in storage account '${storage_account_name:1:-1}'...\n"
  az storage file upload-batch \
      --account-name ${storage_account_name:1:-1} \
      --account-key "$storage_account_key" \
      --destination ${storage_share_name:1:-1} \
      --destination-path 'documents' \
      --source './documents/' \
      --pattern '*.pdf' && break || sleep 15
done

printf "Disabling public internet access and shared key access on storage account '${storage_account_name:1:-1}'...\n"
az storage account update \
  --subscription ${subscription_id:1:-1} \
  --name ${storage_account_name:1:-1} \
  --resource-group ${resource_group_name:1:-1} \
  --public-network-access Disabled \
  --allow-shared-key-access false

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id           = $aad_tenant_id\n"         > ./terraform.tfvars
printf "arm_client_id           = $arm_client_id\n"         >> ./terraform.tfvars
printf "key_vault_id            = $key_vault_id\n"          >> ./terraform.tfvars
printf "key_vault_name          = $key_vault_name\n"        >> ./terraform.tfvars
printf "location                = $location\n"              >> ./terraform.tfvars
printf "private_dns_zones       = $private_dns_zones\n"     >> ./terraform.tfvars
printf "resource_group_name     = $resource_group_name\n"   >> ./terraform.tfvars
printf "storage_account_name    = $storage_account_name\n"  >> ./terraform.tfvars
printf "subscription_id         = $subscription_id\n"       >> ./terraform.tfvars
printf "tags                    = $tags\n"                  >> ./terraform.tfvars
printf "vnet_app_01_subnets     = $vnet_app_01_subnets\n"   >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in \"variables.tf\" prior to applying Terraform configurations...\n"
printf "\nBootstrapping complete...\n"

exit 0
