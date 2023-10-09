#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

# Set these defaults prior to running the script.
default_adds_domain_name="myonprem.local"
default_dns_resolver_cloud="10.1.2.4"
default_dns_server="192.168.2.4"
default_subnet_adds_address_prefix="192.168.2.0/24"
default_subnet_AzureBastionSubnet_address_prefix="192.168.1.0/27"
default_subnet_GatewaySubnet_address_prefix="192.168.0.0/24"
default_subnet_misc_address_prefix="192.168.3.0/24"
default_vnet_address_space="192.168.0.0/16"
default_vm_adds_name="adds2"
default_vm_jumpbox_win_name="jumpwin2"

# Intialize runtime defaults
state_file="../../terraform-azurerm-vnet-shared/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

aad_tenant_id=$(terraform output -state=$state_file aad_tenant_id)
adds_domain_name_cloud=$(terraform output -state=$state_file adds_domain_name)
admin_password_secret=$(terraform output -state=$state_file admin_password_secret)
admin_username_secret=$(terraform output -state=$state_file admin_username_secret)
arm_client_id=$(terraform output -state=$state_file arm_client_id)
automation_account_name=$(terraform output -state=$state_file automation_account_name)
dns_server_cloud=$(terraform output -state=$state_file dns_server)
key_vault_id=$(terraform output -state=$state_file key_vault_id)
key_vault_name=$(terraform output -state=$state_file key_vault_name)
location=$(terraform output -state=$state_file location)
resource_group_name=$(terraform output -state=$state_file resource_group_name)
subscription_id=$(terraform output -state=$state_file subscription_id)
tags=$(terraform output -json -state=$state_file tags)
vnet_shared_01_id=$(terraform output -state=$state_file vnet_shared_01_id)
vnet_shared_01_name=$(terraform output -state=$state_file vnet_shared_01_name)
vnet_shared_01_subnets=$(terraform output -json -state=$state_file vnet_shared_01_subnets)

state_file="../../terraform-azurerm-vnet-app/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

vnet_app_01_id=$(terraform output -state=$state_file vnet_app_01_id)
vnet_app_01_name=$(terraform output -state=$state_file vnet_app_01_name)

state_file="../../terraform-azurerm-vwan/terraform.tfstate"

printf "Retrieving runtime defaults from state file '$state_file'...\n"

if [ ! -f $state_file ]
then
    printf "Unable to locate \"$state_file\"...\n"
    printf "See README.md for configurations that must be deployed first...\n"
    usage
fi

vwan_01_hub_01_id=$(terraform output -state=$state_file vwan_01_hub_01_id)
vwan_01_id=$(terraform output -state=$state_file vwan_01_id)

# User input
read -e -i $default_vnet_address_space                        -p "Virtual network address space (vnet_address_space) -----------------------: " vnet_address_space
read -e -i $default_subnet_GatewaySubnet_address_prefix       -p "Gateway subnet address prefix (subnet_GatewaySubnet_address_prefix) ------: " subnet_GatewaySubnet_address_prefix
read -e -i $default_subnet_AzureBastionSubnet_address_prefix  -p "Bastion subnet address prefix (subnet_AzureBastionSubnet_address_prefix) -: " subnet_AzureBastionSubnet_address_prefix
read -e -i $default_subnet_adds_address_prefix                -p "AD Domain Services subnet address prefix (subnet_adds_address_prefix) ----: " subnet_adds_address_prefix
read -e -i $default_subnet_misc_address_prefix                -p "Miscellaneous subnet address prefix (subnet_misc_address_prefix) ---------: " subnet_misc_address_prefix
read -e -i $default_dns_server                                -p "DNS server ip address (dns_server) ---------------------------------------: " dns_server
read -e -i $default_dns_resolver_cloud                        -p "DNS resolver ip address (dns_resolver_cloud) -----------------------------: " dns_resolver_cloud
read -e -i $default_adds_domain_name                          -p "AD Domain Services domain name (adds_domain_name) ------------------------: " adds_domain_name
read -e -i $default_vm_adds_name                              -p "AD Domain Services virtual machine name (vm_adds_name) -------------------: " vm_adds_name
read -e -i $default_vm_jumpbox_win_name                       -p "Windows jumpbox virtual machine name (vm_jumpbox_win_name) ---------------: " vm_jumpbox_win_name

# Validate user input
adds_domain_name=${adds_domain_name:-$default_adds_domain_name}
dns_resolver_cloud=${dns_resolver_cloud:-$default_dns_resolver_cloud}
dns_server=${dns_server:-default_dns_server}
subnet_adds_address_prefix=${subnet_adds_address_prefix:-$default_subnet_adds_address_prefix}
subnet_AzureBastionSubnet_address_prefix=${subnet_AzureBastionSubnet_address_prefix:-$default_subnet_AzureBastionSubnet_address_prefix}
subnet_GatewaySubnet_address_prefix=${subnet_GatewaySubnet_address_prefix:-$default_subnet_GatewaySubnet_address_prefix}
subnet_misc_address_prefix=${subnet_misc_address_prefix:-$default_subnet_misc_address_prefix}
vnet_address_space=${vnet_address_space:-$default_vnet_address_space}
vm_adds_name=${vm_adds_name:-$default_vm_adds_name}
vm_jumpbox_win_name=${vm_jumpbox_win_name:-$default_vm_jumpbox_win_name}

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
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

# Bootstrap auotmation account
printf "Configuring automation account '${automation_account_name:1:-1}'...\n"

./configure-automation.ps1 \
  -TenantId ${aad_tenant_id:1:-1} \
  -SubscriptionId ${subscription_id:1:-1} \
  -ResourceGroupName ${resource_group_name:1:-1} \
  -AutomationAccountName ${automation_account_name:1:-1} \
  -Domain "$adds_domain_name" \
  -VmAddsName "$vm_adds_name" \
  -VmJumpboxWinName "$vm_jumpbox_win_name" \
  -AdminUserName "$admin_username" \
  -AdminPwd "$admin_password" \
  -AppId ${arm_client_id:1:-1} \
  -AppSecret "$TF_VAR_arm_client_secret" \
  -DnsResolverCloud "$dns_resolver_cloud"

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id                             = $aad_tenant_id\n"                                 > ./terraform.tfvars
printf "adds_domain_name                          = \"$adds_domain_name\"\n"                          >> ./terraform.tfvars
printf "adds_domain_name_cloud                    = $adds_domain_name_cloud\n"                        >> ./terraform.tfvars
printf "admin_password_secret                     = $admin_password_secret\n"                         >> ./terraform.tfvars
printf "admin_username_secret                     = $admin_username_secret\n"                         >> ./terraform.tfvars
printf "arm_client_id                             = $arm_client_id\n"                                 >> ./terraform.tfvars
printf "automation_account_name                   = $automation_account_name\n"                       >> ./terraform.tfvars
printf "dns_server                                = \"$dns_server\"\n"                                >> ./terraform.tfvars
printf "dns_server_cloud                          = $dns_server_cloud\n"                              >> ./terraform.tfvars
printf "key_vault_id                              = $key_vault_id\n"                                  >> ./terraform.tfvars
printf "key_vault_name                            = $key_vault_name\n"                                >> ./terraform.tfvars
printf "location                                  = $location\n"                                      >> ./terraform.tfvars
printf "resource_group_name                       = $resource_group_name\n"                           >> ./terraform.tfvars
printf "subnet_adds_address_prefix                = \"$subnet_adds_address_prefix\"\n"                >> ./terraform.tfvars
printf "subnet_AzureBastionSubnet_address_prefix  = \"$subnet_AzureBastionSubnet_address_prefix\"\n"  >> ./terraform.tfvars
printf "subnet_GatewaySubnet_address_prefix       = \"$subnet_GatewaySubnet_address_prefix\"\n"       >> ./terraform.tfvars
printf "subnet_misc_address_prefix                = \"$subnet_misc_address_prefix\"\n"                >> ./terraform.tfvars
printf "subscription_id                           = $subscription_id\n"                               >> ./terraform.tfvars
printf "tags                                      = $tags\n"                                          >> ./terraform.tfvars
printf "vm_adds_name                              = \"$vm_adds_name\"\n"                              >> ./terraform.tfvars
printf "vm_jumpbox_win_name                       = \"$vm_jumpbox_win_name\"\n"                       >> ./terraform.tfvars
printf "vnet_address_space                        = \"$vnet_address_space\"\n"                        >> ./terraform.tfvars
printf "vnet_app_01_id                            = $vnet_app_01_id\n"                                >> ./terraform.tfvars
printf "vnet_app_01_name                          = $vnet_app_01_name\n"                              >> ./terraform.tfvars
printf "vnet_shared_01_id                         = $vnet_shared_01_id\n"                             >> ./terraform.tfvars
printf "vnet_shared_01_name                       = $vnet_shared_01_name\n"                           >> ./terraform.tfvars
printf "vnet_shared_01_subnets                    = $vnet_shared_01_subnets\n"                        >> ./terraform.tfvars
printf "vwan_01_hub_01_id                         = $vwan_01_hub_01_id\n"                             >> ./terraform.tfvars
printf "vwan_01_id                                = $vwan_01_id\n"                                    >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in \"variables.tf\" prior to applying Terraform configurations...\n"
printf "\nBootstrapping complete...\n"

exit 0
