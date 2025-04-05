#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

#region functions
usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}
#endregion

#region constants
default_vnet_name="vnet-app-01"
default_vnet_address_space="10.2.0.0/16"
default_skip_ssh_key_gen="no"
default_storage_share_name="myfileshare"
default_subnet_application_address_prefix="10.2.0.0/24"
default_subnet_appservice_address_prefix="10.2.4.0/24"
default_subnet_database_address_prefix="10.2.1.0/24"
default_subnet_misc_address_prefix="10.2.3.0/24"
default_subnet_privatelink_address_prefix="10.2.2.0/24"
default_vm_jumpbox_linux_name="jumplinux1"
default_vm_jumpbox_win_name="jumpwin1"
secret_expiration_days=365
vm_jumpbox_linux_size="Standard_B2ls_v2"
vm_jumpbox_win_post_deploy_script="configure-vm-jumpbox-win.ps1"
vm_jumpbox_win_configure_storage_script="configure-storage-kerberos.ps1"
vm_jumpbox_win_size="Standard_B2ls_v2"
#endregion

#region main

# Initialize runtime defaults
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
dns_server=$(terraform output -state=$state_file dns_server)
firewall_01_route_table_id=$(terraform output -state=$state_file firewall_01_route_table_id)
key_vault_id=$(terraform output -state=$state_file key_vault_id)
key_vault_name=$(terraform output -state=$state_file key_vault_name)
location=$(terraform output -state=$state_file location)
remote_virtual_network_id=$(terraform output -state=$state_file vnet_shared_01_id)
remote_virtual_network_name=$(terraform output -state=$state_file vnet_shared_01_name)
resource_group_name=$(terraform output -state=$state_file resource_group_name)
storage_account_name=$(terraform output -state=$state_file storage_account_name)
storage_container_name=$(terraform output -state=$state_file storage_container_name)
subscription_id=$(terraform output -state=$state_file subscription_id)
tags=$(terraform output -json -state=$state_file tags)

# User input
read -e -i $default_vnet_name                         -p "Virtual network name (vnet_name) --------------------------------------: " vnet_name
read -e -i $default_vnet_address_space                -p "Virtual network address space (vnet_address_space) --------------------: " vnet_address_space
read -e -i $default_subnet_application_address_prefix -p "Application subnet address prefix (subnet_application_address_prefix) -: " subnet_application_address_prefix
read -e -i $default_subnet_database_address_prefix    -p "Database subnet address prefix (subnet_database_address_prefix) -------: " subnet_database_address_prefix
read -e -i $default_subnet_privatelink_address_prefix -p "privatelink subnet address prefix (subnet_privatelink_address_prefix) -: " subnet_privatelink_address_prefix
read -e -i $default_subnet_misc_address_prefix        -p "Miscellaneous subnet address prefix (subnet_misc_address_prefix) ------: " subnet_misc_address_prefix
read -e -i $default_subnet_appservice_address_prefix  -p "App Service subnet address prefix (subnet_appservice_address_prefix) --: " subnet_appservice_address_prefix
read -e -i $default_vm_jumpbox_linux_name             -p "Linux jumpbox virtual machine name (vm_jumpbox_linux_name) ------------: " vm_jumpbox_linux_name
read -e -i $default_skip_ssh_key_gen                  -p "Skip SSH key generation (skip_ssh_key_gen) yes/no ? -------------------: " skip_ssh_key_gen
read -e -i $default_vm_jumpbox_win_name               -p "Windows jumpbox virtual machine name (vm_jumpbox_win_name) ------------: " vm_jumpbox_win_name
read -e -i $default_storage_share_name                -p "Azure Files share name (storage_share_name) ---------------------------: " storage_share_name

application_subnet_name=${application_subnet_name:-$default_application_subnet_name}
database_subnet_name=${database_subnet_name:-$default_database_subnet_name}
privatelink_subnet_name=${privatelink_subnet_name:-$default_privatelink_subnet_name}
skip_ssh_key_gen=${skip_ssh_key_gen:-$default_skip_ssh_key_gen}
storage_share_name=${storage_share_name:-$default_storage_share_name}
subnet_application_address_prefix=${subnet_application_address_prefix:-$default_subnet_application_address_prefix}
subnet_appservice_address_prefix=${subnet_appservice_address_prefix:-$default_subnet_appservice_address_prefix}
subnet_database_address_prefix=${subnet_database_address_prefix:-$default_subnet_database_address_prefix}
subnet_misc_address_prefix=${subnet_misc_address_prefix:-$default_subnet_misc_address_prefix}
subnet_privatelink_address_prefix=${subnet_privatelink_address_prefix:-$default_subnet_privatelink_address_prefix}
vm_jumpbox_linux_name=${vm_jumpbox_linux_name:-$default_vm_jumpbox_linux_name}
vm_jumpbox_win_name=${vm_jumpbox_win_name:-$default_vm_jumpbox_win_name}
vnet_name=${vnet_name:=$default_vnet_name}
vnet_address_space=${vnet_address_space:-$default_vnet_address_space}

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Validate skip_ssh_key_gen input
if [ "$skip_ssh_key_gen" != 'yes' ] && [ "$skip_ssh_key_gen" != 'no' ]
then
  printf "Invalid skip_ssh_key_gen input '$skip_ssh_key_gen'. Valid values are 'yes' or 'no'...\n"
  usage
fi

# Validate VM size sku availability in location
location_noquotes=${location:1:-1}
printf "Checking for availability of virtual machine sku '$vm_jumpbox_linux_size' in location '$location_noquotes'...\n"

reason_code=$(az vm list-skus --location $location_noquotes --size $vm_jumpbox_linux_size --all --query "[?name=='$vm_jumpbox_linux_size']|[0].restrictions|[?type=='Location']|[0].reasonCode" --output tsv)

if [ -z "$reason_code" ]
then
  printf "Virtual machine sku '$vm_jumpbox_linux_size' is available in location '$location_noquotes'...\n"
else
  printf "Virtual machine sku '$vm_jumpbox_linux_size' is not available in location '$location_noquotes' due to reason code '$reason_code'...\n"
  usage
fi

if [ "$vm_jumpbox_linux_size" != "$vm_jumpbox_win_size" ]
then
  printf "Checking for availability of virtual machine sku '$vm_jumpbox_win_size' in location '$location_noquotes'...\n"

  reason_code=$(az vm list-skus --location $location_noquotes --size $vm_jumpbox_win_size --all --query "[?name=='$vm_jumpbox_win_size']|[0].restrictions|[?type=='Location']|[0].reasonCode" --output tsv)

  if [ -z "$reason_code" ]
  then
    printf "Virtual machine sku '$vm_jumpbox_win_size' is available in location '$location_noquotes'...\n"
  else
    printf "Virtual machine sku '$vm_jumpbox_win_size' is not available in location '$location_noquotes' due to reason code '$reason_code'...\n"
    usage
  fi
fi

# Get key vault secrets
admin_username_secret_noquotes=${admin_username_secret:1:-1}
key_vault_name_noquotes=${key_vault_name:1:-1}
printf "Getting secret '$admin_username_secret_noquotes' from key vault '$key_vault_name_noquotes'...\n"
admin_username=$(az keyvault secret show --vault-name $key_vault_name_noquotes --name $admin_username_secret_noquotes --query value --output tsv)

if [ -n "$admin_username" ]
then 
  printf "The value of secret '$admin_username_secret_noquotes' is '$admin_username'...\n"
else
  printf "Unable to determine the value of secret '$admin_username_secret_noquotes'...\n"
  usage
fi

admin_password_secret_noquotes=${admin_password_secret:1:-1}
printf "Getting secret '$admin_password_secret_noquotes' from key vault '$key_vault_name_noquotes'...\n"
admin_password=$(az keyvault secret show --vault-name $key_vault_name_noquotes --name $admin_password_secret_noquotes --query value --output tsv)

if [ -n "$admin_password" ]
then 
  printf "The length of secret '$admin_password_secret_noquotes' is '${#admin_password}'...\n"
else
  printf "Unable to determine the value of secret '$admin_password_secret_noquotes'...\n"
  usage
fi

# Generate SSH keys
if [ "$skip_ssh_key_gen" = 'no' ]
then
  printf "Generating SSH keys...\n"
  echo -e 'y' | ssh-keygen -m PEM -t rsa -b 4096 -C "${admin_username}local" -f sshkeytemp -N "$admin_password" 
fi

if [ ! -f 'sshkeytemp.pub' ] 
then
  printf "Unable to locate SSH public key file 'sshktemp.pub'...\n"
  usage
fi

if [ ! -f 'sshkeytemp' ] 
then
  printf "Unable to locate SSH private key file 'sshktemp.pub'...\n"
  usage
fi

ssh_public_key_secret_value=$(cat sshkeytemp.pub)
ssh_private_key_secret_value=$(cat sshkeytemp)

# Create secrets for SSH keys
ssh_private_key_secret_name="$admin_username-ssh-key-private"

secret_expiration_date=$(date -u -d "+$secret_expiration_days days" +'%Y-%m-%dT%H:%M:%SZ')
printf "Secrets will expire in '$secret_expiration_days' days on '$secret_expiration_date UTC'...\n"

printf "Setting secret '$ssh_private_key_secret_name' with value length '${#ssh_private_key_secret_value}' in keyvault '$key_vault_name_noquotes'...\n"
az keyvault secret set \
    --vault-name $key_vault_name_noquotes \
    --name $ssh_private_key_secret_name \
    --value="$ssh_private_key_secret_value" \
    --expires "$secret_expiration_date" \
    --output none

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
vm_jumpbox_win_post_deploy_script_uri="https://${storage_account_name:1:-1}.blob.core.windows.net/${storage_container_name:1:-1}/$vm_jumpbox_win_post_deploy_script"
vm_jumpbox_win_configure_storage_script_uri="https://${storage_account_name:1:-1}.blob.core.windows.net/${storage_container_name:1:-1}/$vm_jumpbox_win_configure_storage_script"

for i in {1..12}
do
  printf "Attempt $i: Uploading post-deployment scripts to container '${storage_container_name:1:-1}' in storage account '${storage_account_name:1:-1}'...\n"
  az storage blob upload-batch \
      --account-name ${storage_account_name:1:-1} \
      --auth-mode login \
      --destination ${storage_container_name:1:-1} \
      --source './scripts' \
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

# Bootstrap automation account
printf "Configuring automation account '${automation_account_name:1:-1}'...\n"

./scripts/configure-automation.ps1 \
  -TenantId ${aad_tenant_id:1:-1} \
  -SubscriptionId ${subscription_id:1:-1} \
  -ResourceGroupName ${resource_group_name:1:-1} \
  -AutomationAccountName ${automation_account_name:1:-1} \
  -VmJumpboxWinName $vm_jumpbox_win_name \
  -AppId ${arm_client_id:1:-1} \
  -AppSecret "$TF_VAR_arm_client_secret" 

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id                               = $aad_tenant_id\n"                                   > ./terraform.tfvars
printf "adds_domain_name                            = $adds_domain_name\n"                                >> ./terraform.tfvars
printf "admin_password_secret                       = $admin_password_secret\n"                           >> ./terraform.tfvars
printf "admin_username_secret                       = $admin_username_secret\n"                           >> ./terraform.tfvars
printf "arm_client_id                               = $arm_client_id\n"                                   >> ./terraform.tfvars
printf "automation_account_name                     = $automation_account_name\n"                         >> ./terraform.tfvars
printf "dns_server                                  = $dns_server\n"                                      >> ./terraform.tfvars
printf "firewall_01_route_table_id                  = $firewall_01_route_table_id\n"                      >> ./terraform.tfvars
printf "key_vault_id                                = $key_vault_id\n"                                    >> ./terraform.tfvars
printf "key_vault_name                              = $key_vault_name\n"                                  >> ./terraform.tfvars
printf "location                                    = $location\n"                                        >> ./terraform.tfvars
printf "remote_virtual_network_id                   = $remote_virtual_network_id\n"                       >> ./terraform.tfvars
printf "remote_virtual_network_name                 = $remote_virtual_network_name\n"                     >> ./terraform.tfvars
printf "resource_group_name                         = $resource_group_name\n"                             >> ./terraform.tfvars
printf "ssh_public_key                              = \"$ssh_public_key_secret_value\"\n"                 >> ./terraform.tfvars
printf "storage_account_name                        = $storage_account_name\n"                            >> ./terraform.tfvars
printf "storage_share_name                          = \"$storage_share_name\"\n"                          >> ./terraform.tfvars
printf "subnet_application_address_prefix           = \"$subnet_application_address_prefix\"\n"           >> ./terraform.tfvars
printf "subnet_appservice_address_prefix            = \"$subnet_appservice_address_prefix\"\n"            >> ./terraform.tfvars
printf "subnet_database_address_prefix              = \"$subnet_database_address_prefix\"\n"              >> ./terraform.tfvars
printf "subnet_misc_address_prefix                  = \"$subnet_misc_address_prefix\"\n"                  >> ./terraform.tfvars
printf "subnet_privatelink_address_prefix           = \"$subnet_privatelink_address_prefix\"\n"           >> ./terraform.tfvars
printf "subscription_id                             = $subscription_id\n"                                 >> ./terraform.tfvars
printf "tags                                        = $tags\n"                                            >> ./terraform.tfvars
printf "vm_jumpbox_linux_name                       = \"$vm_jumpbox_linux_name\"\n"                       >> ./terraform.tfvars
printf "vm_jumpbox_linux_size                       = \"$vm_jumpbox_linux_size\"\n"                       >> ./terraform.tfvars
printf "vm_jumpbox_win_configure_storage_script     = \"$vm_jumpbox_win_configure_storage_script\"\n"     >> ./terraform.tfvars
printf "vm_jumpbox_win_configure_storage_script_uri = \"$vm_jumpbox_win_configure_storage_script_uri\"\n" >> ./terraform.tfvars
printf "vm_jumpbox_win_name                         = \"$vm_jumpbox_win_name\"\n"                         >> ./terraform.tfvars
printf "vm_jumpbox_win_post_deploy_script           = \"$vm_jumpbox_win_post_deploy_script\"\n"           >> ./terraform.tfvars
printf "vm_jumpbox_win_post_deploy_script_uri       = \"$vm_jumpbox_win_post_deploy_script_uri\"\n"       >> ./terraform.tfvars
printf "vm_jumpbox_win_size                         = \"$vm_jumpbox_win_size\"\n"                         >> ./terraform.tfvars
printf "vnet_address_space                          = \"$vnet_address_space\"\n"                          >> ./terraform.tfvars
printf "vnet_name                                   = \"$vnet_name\"\n"                                   >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in \"variables.tf\" prior to applying Terraform configurations...\n"
printf "\nBootstrapping complete...\n"

exit 0
#endregion
