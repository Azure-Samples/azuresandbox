#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

# Set these defaults prior to running the script.

# Initialize runtime defaults
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
vnet_app_01_subnets=$(terraform output -json -state=$state_file vnet_app_01_subnets)

# User input

# Validate user input

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi


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
