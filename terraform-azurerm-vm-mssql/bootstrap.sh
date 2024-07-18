#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

# Set these defaults prior to running the script.
default_vm_mssql_win_name="mssqlwin1"
vm_mssql_win_post_deploy_script="configure-vm-mssql.ps1"
vm_mssql_win_size="Standard_B4s_v2"
vm_mssql_win_sql_startup_script="sql-startup.ps1"

# Intialize runtime defaults
state_file="../terraform-azurerm-vnet-shared/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

aad_tenant_id=$(terraform output -state=$state_file aad_tenant_id)
adds_domain_name=$(terraform output -state=$state_file adds_domain_name)
admin_password_secret=$(terraform output -state=$state_file admin_password_secret)
admin_username_secret=$(terraform output -state=$state_file admin_username_secret)
arm_client_id=$(terraform output -state=$state_file arm_client_id)
automation_account_name=$(terraform output -state=$state_file automation_account_name)
key_vault_id=$(terraform output -state=$state_file key_vault_id)
key_vault_name=$(terraform output -state=$state_file key_vault_name)
location=$(terraform output -state=$state_file location)
resource_group_name=$(terraform output -state=$state_file resource_group_name)
storage_account_name=$(terraform output -state=$state_file storage_account_name)
storage_container_name=$(terraform output -state=$state_file storage_container_name)
subscription_id=$(terraform output -state=$state_file subscription_id)
tags=$(terraform output -json -state=$state_file tags)

state_file="../terraform-azurerm-vnet-app/terraform.tfstate"
printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

vnet_app_01_subnets=$(terraform output -json -state=$state_file vnet_app_01_subnets)

# User input
read -e -i $default_vm_mssql_win_name -p "SQL Server virtual machine name (vm_mssql_win_name) -: " vm_mssql_win_name

vm_mssql_win_name=${vm_mssql_win_name:-$default_vm_mssql_win_name}

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Validate VM size sku availability in location
location_noquotes=${location:1:-1}
printf "Checking for availability of virtual machine sku '$vm_mssql_win_size' in location '$location_noquotes'...\n"

reason_code=$(az vm list-skus --location $location_noquotes --size $vm_mssql_win_size --all --query "[?name=='$vm_mssql_win_size']|[0].restrictions|[?type=='Location']|[0].reasonCode" --output tsv)

if [ -z "$reason_code" ]
then
  printf "Virtual machine sku '$vm_mssql_win_size' is available in location '$location_noquotes'...\n"
else
  printf "Virtual machine sku '$vm_mssql_win_size' is not available in location '$location_noquotes' due to reason code '$reason_code'...\n"
  usage
fi

# Temporarily enable public internet access
printf "Temporarily enabling public internet access to storage account '${storage_account_name:1:-1}'...\n"
az storage account update \
  --subscription ${subscription_id:1:-1} \
  --name ${storage_account_name:1:-1} \
  --resource-group ${resource_group_name:1:-1} \
  --public-network-access Enabled

printf "Sleeping for 15 seconds to allow storage account settings to propogate...\n"
sleep 15

# Upload post-deployment scripts
vm_mssql_win_post_deploy_script_uri="https://${storage_account_name:1:-1}.blob.core.windows.net/${storage_container_name:1:-1}/$vm_mssql_win_post_deploy_script"
vm_mssql_win_sql_startup_script_uri="https://${storage_account_name:1:-1}.blob.core.windows.net/${storage_container_name:1:-1}/$vm_mssql_win_sql_startup_script"

printf "Getting storage account key for storage account '${storage_account_name:1:-1}' from key vault '${key_vault_name:1:-1}'...\n"
storage_account_key=$(az keyvault secret show --name ${storage_account_name:1:-1} --vault-name ${key_vault_name:1:-1} --query value --output tsv)

for i in {1..12}
do
  printf "Attempt $i: Uploading post-deployment scripts to container '${storage_container_name:1:-1}' in storage account '${storage_account_name:1:-1}'...\n"
  az storage blob upload-batch \
      --account-name ${storage_account_name:1:-1} \
      --account-key "$storage_account_key" \
      --destination ${storage_container_name:1:-1} \
      --source '.' \
      --pattern '*.ps1' \
      --overwrite && break || sleep 15
done

# Disable public internet access
printf "Disabling public internet access to storage account '${storage_account_name:1:-1}'...\n"
az storage account update \
  --subscription ${subscription_id:1:-1} \
  --name ${storage_account_name:1:-1} \
  --resource-group ${resource_group_name:1:-1} \
  --public-network-access Disabled

# Bootstrap auotmation account
printf "Configuring automation account '${automation_account_name:1:-1}'...\n"

./configure-automation.ps1 \
  -TenantId ${aad_tenant_id:1:-1} \
  -SubscriptionId ${subscription_id:1:-1} \
  -ResourceGroupName ${resource_group_name:1:-1} \
  -AutomationAccountName ${automation_account_name:1:-1} \
  -VmMssqlWinName $vm_mssql_win_name \
  -AppId ${arm_client_id:1:-1} \
  -AppSecret "$TF_VAR_arm_client_secret" 

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id                       = $aad_tenant_id\n"                           > ./terraform.tfvars
printf "adds_domain_name                    = $adds_domain_name\n"                        >> ./terraform.tfvars
printf "admin_password_secret               = $admin_password_secret\n"                   >> ./terraform.tfvars
printf "admin_username_secret               = $admin_username_secret\n"                   >> ./terraform.tfvars
printf "arm_client_id                       = $arm_client_id\n"                           >> ./terraform.tfvars
printf "automation_account_name             = $automation_account_name\n"                 >> ./terraform.tfvars
printf "key_vault_id                        = $key_vault_id\n"                            >> ./terraform.tfvars
printf "key_vault_name                      = $key_vault_name\n"                          >> ./terraform.tfvars
printf "location                            = $location\n"                                >> ./terraform.tfvars
printf "resource_group_name                 = $resource_group_name\n"                     >> ./terraform.tfvars
printf "storage_account_name                = $storage_account_name\n"                    >> ./terraform.tfvars
printf "subscription_id                     = $subscription_id\n"                         >> ./terraform.tfvars
printf "tags                                = $tags\n"                                    >> ./terraform.tfvars
printf "vm_mssql_win_name                   = \"$vm_mssql_win_name\"\n"                   >> ./terraform.tfvars
printf "vm_mssql_win_post_deploy_script     = \"$vm_mssql_win_post_deploy_script\"\n"     >> ./terraform.tfvars
printf "vm_mssql_win_post_deploy_script_uri = \"$vm_mssql_win_post_deploy_script_uri\"\n" >> ./terraform.tfvars
printf "vm_mssql_win_size                   = \"$vm_mssql_win_size\"\n"                   >> ./terraform.tfvars
printf "vm_mssql_win_sql_startup_script     = \"$vm_mssql_win_sql_startup_script\"\n"     >> ./terraform.tfvars
printf "vm_mssql_win_sql_startup_script_uri = \"$vm_mssql_win_sql_startup_script_uri\"\n" >> ./terraform.tfvars
printf "vnet_app_01_subnets                 = $vnet_app_01_subnets\n"                     >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in \"variables.tf\" prior to applying Terraform configurations...\n"
printf "\nBootstrapping complete...\n"

exit 0
