#!/bin/bash

# Bootstraps deployment with pre-requisites for applying Terraform configurations
# Script is idempotent and can be run multiple times

# Functions

gen_strong_password () {
    # Define constants
    password_length=12
    password=""
    digit_count=0
    uppercase_count=0
    lowercase_count=0
    symbol_count=0

    # Seed random number generator
    RANDOM=$(date +%s)

    for (( i=1; i<=$password_length; i++))
    do
        password_category=$(( $RANDOM % 4 ))

        case $password_category in
            0 )
                # Digits
                if [ $digit_count -le 2 ]
                then
                    char_ascii=$(( ( $RANDOM % 10 ) + 48 ))
                    (( digit_count+=1 ))
                else
                    (( i-=1 ))
                    continue
                fi
                ;;

            1 )
                # Uppercase letters
                if [ $uppercase_count -le 2 ]
                then
                    char_ascii=$(( ( $RANDOM % 26 ) + 65 ))
                    (( uppercase_count+=1 ))
                else
                    (( i-=1 ))
                    continue
                fi

                ;;

            2 )
                # Lowercase letters
                if [ $lowercase_count -le 2 ]
                then
                    char_ascii=$(( ( $RANDOM % 26 ) + 97 ))
                    (( lowercase_count+=1 ))
                else
                    (( i-=1 ))
                    continue
                fi
                ;;

            3 )
                # Symbols
                if [ $symbol_count -le 2 ]
                then
                    char_ascii=$(( ( $RANDOM % 2 ) + 94 ))
                    (( symbol_count+=1 ))
                else
                    (( i-=1 ))
                    continue
                fi
                ;;
        esac

        # printf "Character '$i'; Category '$password_category'; Character ASCII '$char_ascii'; Character '$char'\n"
        char=$(printf \\$(printf '%03o' $char_ascii))
        password+=$char
    done 

    echo $password
}

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

# Main

# Get runtime defaults
printf "Retrieving runtime defaults ...\n"

default_subscription_id=$(az account list --only-show-errors --query "[? isDefault]|[0].id" --output tsv)

if [ -z $default_subscription_id ]
then
  printf "Unable to retrieve Azure subscription details. Please run 'az login' first.\n"
  usage
fi

default_owner_object_id=$(az account get-access-token --query accessToken --output tsv | tr -d '\n' | python3 -c "import jwt, sys; print(jwt.decode(sys.stdin.read(), algorithms=['RS256'], options={'verify_signature': False})['oid'])")
default_aad_tenant_id=$(az account show --query tenantId --output tsv)

# Initialize constants
admin_certificate_name='admincert'
admin_password_secret='adminpassword'
admin_username_secret='adminuser'
arm_client_id=''
arm_client_secret=''
storage_container_name='scripts'

# Initialize user defaults
default_adds_domain_name="mysandbox.local"
default_admin_username="bootstrapadmin"
default_costcenter="10177772"
default_dns_server="10.1.1.4"
default_environment="dev"
default_location="eastus"
default_project="#AzureSandbox"
default_resource_group_name="rg-sandbox-01"
default_skip_admin_password_gen="no"
default_subnet_adds_address_prefix="10.1.1.0/24"
default_subnet_AzureBastionSubnet_address_prefix="10.1.0.0/27"
default_vm_adds_name="adds1"
default_vnet_address_space="10.1.0.0/16"
default_vnet_name="vnet-shared-01"

# Get user input
read -e                                                       -p "Service principal appId (arm_client_id) ---------------------------------------------: " arm_client_id
read -e -i $default_aad_tenant_id                             -p "Azure AD tenant id (aad_tenant_id) --------------------------------------------------: " aad_tenant_id
read -e -i $default_owner_object_id                           -p "Object id for Azure CLI signed in user (owner_object_id) ----------------------------: " owner_object_id
read -e -i $default_subscription_id                           -p "Azure subscription id (subscription_id) ---------------------------------------------: " subscription_id
read -e -i $default_resource_group_name                       -p "Azure resource group name (resource_group_name) -------------------------------------: " resource_group_name
read -e -i $default_location                                  -p "Azure location (location) -----------------------------------------------------------: " location
read -e -i $default_environment                               -p "Environment tag value (environment) -------------------------------------------------: " environment
read -e -i $default_costcenter                                -p "Cost center tag value (costcenter) --------------------------------------------------: " costcenter
read -e -i $default_project                                   -p "Project tag value (project) ---------------------------------------------------------: " project
read -e -i $default_vnet_address_space                        -p "Virtual network address space (vnet_address_space) ----------------------------------: " vnet_address_space
read -e -i $default_subnet_AzureBastionSubnet_address_prefix  -p "Bastion subnet address prefix (subnet_AzureBastionSubnet_address_prefix) ------------: " subnet_AzureBastionSubnet_address_prefix
read -e -i $default_subnet_adds_address_prefix                -p "AD Domain Services subnet address prefix (subnet_adds_address_prefix) ---------------: " subnet_adds_address_prefix
read -e -i $default_dns_server                                -p "DNS server ip address (dns_server) --------------------------------------------------: " dns_server
read -e -i $default_adds_domain_name                          -p "AD Domain Services domain name (adds_domain_name) -----------------------------------: " adds_domain_name
read -e -i $default_vm_adds_name                              -p "AD Domain Services virtual machine name (vm_adds_name) ------------------------------: " vm_adds_name
read -e -i $default_admin_username                            -p "'adminuser' key vault secret value (admin_username) ---------------------------------: " admin_username
read -e -i $default_skip_admin_password_gen                   -p "Skip 'adminpassword' key vault secret generation (skip_admin_password_gen) yes/no ? -: " skip_admin_password_gen

# Validate user input
aad_tenant_id=${aad_tenant_id:-default_aad_tenant_id}
adds_domain_name=${adds_domain_name:-default_adds_domain_name}
admin_password_secret=${admin_password_secret:-$default_admin_password_secret}
admin_username=${admin_username:-$default_admin_username}
admin_username_secret=${admin_username_secret:-$default_admin_username_secret}
costcenter=${costcenter:-$default_costcenter}
dns_server=${dns_server:-default_dns_server}
environment=${environment:-$default_environment}
location=${location:-$default_location}
owner_object_id=${owner_object_id:-$default_owner_object_id}
project=${project:-$default_project}
resource_group_name=${resource_group_name:-$default_resource_group_name}
skip_admin_password_gen=${skip_admin_password_gen:-$default_skip_admin_password_gen}
subnet_adds_address_prefix=${subnet_adds_address_prefix:-default_subnet_adds_address_prefix}
subnet_AzureBastionSubnet_address_prefix=${subnet_AzureBastionSubnet_address_prefix:-default_subnet_AzureBastionSubnet_address_prefix}
subscription_id=${subscription_id:-$default_subscription_id}
vm_adds_name=${vm_adds_name:-default_vm_adds_name}
vnet_address_space=${vnet_address_space:-default_vnet_address_space}
vnet_name=${vnet_name:=$default_vnet_name}

# Validate arm_client_id
if [ -z "$arm_client_id" ]
then
  printf "arm_client_id is required.\n"
  usage
fi

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Validate service principal
arm_client_display_name=$(az ad sp show --id $arm_client_id --query "appDisplayName" --output tsv)

if [ -n "$arm_client_display_name" ]
then 
  printf "Found service principal '$arm_client_display_name'...\n"
else
  printf "Invalid service principal AppId '$arm_client_id'...\n"
  usage
fi

# Validate subscription
subscription_name=$(az account list --query "[?id=='$subscription_id'].name" --output tsv)

if [ -n "$subscription_name" ]
then 
  printf "Found subscription '$subscription_name'...\n"
else
  printf "Invalid subscription id '$subscription_id'.\n"
  usage
fi

# Validate object id of Azure CLI signed in user
if [ -z "$owner_object_id" ]
then
  printf "Object id for Azure CLI signed in user (owner_object_id) not provided.\n"
  usage
fi

# Validate location
location_id=$(az account list-locations --query "[?name=='$location'].id" --output tsv)

if [ -z "$location_id" ]
then
  printf "Invalid location '$location'...\n"
  usage
fi

# Validate skip_admin_password_gen input
if [ "$skip_admin_password_gen" != 'yes' ] && [ "$skip_admin_password_gen" != 'no' ]
then
  printf "Invalid skip_admin_password_gen input '$skip_admin_password_gen'. Valid values are 'yes' or 'no'...\n"
  usage
fi

# Bootstrap resource group
resource_group_id=$(az group list --subscription $subscription_id --query "[?name == '$resource_group_name'] | [0].id" --output tsv)

if [ -n "$resource_group_id" ]
then
  printf "Found resource group '$resource_group_name'...\n"
else
  printf "Creating resource group '$resource_group_name'...\n"
  az group create \
    --subscription $subscription_id \
    --name $resource_group_name \
    --location $location \
    --tags costcenter=$costcenter project=$project environment=$environment provisioner="bootstrap.sh"
fi

# Bootstrap key vault
key_vault_name=$(az keyvault list --subscription $subscription_id --resource-group $resource_group_name --query "[?tags.provisioner == 'bootstrap.sh'] | [0].name" --output tsv)

if [ -n "$key_vault_name" ]
then
  printf "Found key vault '$key_vault_name'...\n"
else
  key_vault_name=kv-$(tr -dc "[:lower:][:digit:]" < /dev/urandom | head -c 15)
  printf "Creating keyvault '$key_vault_name' in resource group '$resource_group_name'...\n"
  az keyvault create \
    --subscription $subscription_id \
    --name $key_vault_name \
    --resource-group $resource_group_name \
    --location $location \
    --sku standard \
    --no-self-perms \
    --tags costcenter=$costcenter project=$project environment=$environment provisioner="bootstrap.sh"
fi

key_vault_id=$(az keyvault show --subscription $subscription_id --name $key_vault_name --query id --output tsv)

printf "Creating key vault secret access policy for Azure CLI logged in user id '$owner_object_id'...\n"
az keyvault set-policy \
  --subscription $subscription_id \
  --name $key_vault_name \
  --resource-group $resource_group_name \
  --secret-permissions get list 'set' \
  --object-id $owner_object_id

printf "Creating key vault secret access policy for service principal AppId '$arm_client_id'...\n"
az keyvault set-policy \
  --subscription $subscription_id \
  --name $key_vault_name \
  --resource-group $resource_group_name \
  --secret-permissions get 'set' \
  --spn $arm_client_id

printf "Setting secret '$admin_username_secret' with value '$admin_username' in keyvault '$key_vault_name'...\n"
az keyvault secret set \
  --subscription $subscription_id \
  --vault-name $key_vault_name \
  --name $admin_username_secret \
  --value "$admin_username"

if [ "$skip_admin_password_gen" = 'no' ]
then
  admin_password=$(gen_strong_password)
  printf "Setting secret '$admin_password_secret' with value length '${#admin_password}' in keyvault '$key_vault_name'...\n"
  az keyvault secret set \
    --subscription $subscription_id \
    --vault-name $key_vault_name \
    --name $admin_password_secret \
    --value "$admin_password" \
    --output none
fi

# Boostrap storage account
storage_account_name=$(az storage account list --subscription $subscription_id --resource-group $resource_group_name --query "[?tags.provisioner == 'bootstrap.sh'] | [0].name" --output tsv)

if [ -n "$storage_account_name" ]
then
  printf "Found storage account '$storage_account_name' in '$resource_group_name'...\n"
else
  storage_account_name=st$(tr -dc "[:lower:][:digit:]" < /dev/urandom | head -c 13)
  printf "Creating storage account '$storage_account_name' in '$resource_group_name'...\n"
  az storage account create \
    --subscription $subscription_id \
    --name $storage_account_name \
    --resource-group $resource_group_name \
    --location $location \
    --kind StorageV2 \
    --sku Standard_LRS \
    --tags costcenter=$costcenter project=$project environment=$environment provisioner="bootstrap.sh"
fi

storage_account_id=$(az storage account show --subscription $subscription_id --name $storage_account_name --query id --output tsv)
storage_account_key=$(az storage account keys list --subscription $subscription_id --account-name $storage_account_name --output tsv --query "[0].value")

printf "Setting storage account secret '$storage_account_name' with value length '${#storage_account_key}' to keyvault '$key_vault_name'...\n"
az keyvault secret set \
  --subscription $subscription_id \
  --vault-name $key_vault_name \
  --name $storage_account_name \
  --value "$storage_account_key" \
  --output none

# Create Kerberos key
printf "Creating kerberos key for storage account '$storage_account_name'...\n"
storage_account_key_kerb1=$(az storage account keys renew --subscription $subscription_id --resource-group $resource_group_name --account-name $storage_account_name --key key1 --key-type kerb --query "[?keyName == 'kerb1'].value" --output tsv)

printf "Setting storage account secret '$storage_account_name-kerb1' with value length '${#storage_account_key_kerb1}' to keyvault '$key_vault_name'...\n"
az keyvault secret set \
  --subscription $subscription_id \
  --vault-name $key_vault_name \
  --name "$storage_account_name-kerb1" \
  --value "$storage_account_key_kerb1" \
  --output none

# Bootstrap storage account container
jmespath_query="[? name == '$storage_container_name']|[0].name"
storage_container_name_temp=$(az storage container list --subscription $subscription_id --account-name $storage_account_name --account-key $storage_account_key --query "$jmespath_query" --output tsv)

if [ -n "$storage_container_name_temp" ]
then
  printf "Found container '$storage_container_name' in storage account '$storage_account_name'...\n"
else
  printf "Creating storage container '$storage_container_name' in storage account '$storage_account_name'...\n"
  az storage container create \
  --subscription $subscription_id \
  --name $storage_container_name \
  --account-name $storage_account_name \
  --account-key $storage_account_key
fi

# Build tags map
tags=""
tags="${tags}{\n"
tags="${tags}  project     = \"$project\",\n"
tags="${tags}  costcenter  = \"$costcenter\",\n"
tags="${tags}  environment = \"$environment\"\n"
tags="${tags}}"

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id                             = \"$aad_tenant_id\"\n"                             > ./terraform.tfvars
printf "adds_domain_name                          = \"$adds_domain_name\"\n"                          >> ./terraform.tfvars
printf "arm_client_id                             = \"$arm_client_id\"\n"                             >> ./terraform.tfvars
printf "dns_server                                = \"$dns_server\"\n"                                >> ./terraform.tfvars
printf "key_vault_id                              = \"$key_vault_id\"\n"                              >> ./terraform.tfvars
printf "key_vault_name                            = \"$key_vault_name\"\n"                            >> ./terraform.tfvars
printf "location                                  = \"$location\"\n"                                  >> ./terraform.tfvars
printf "resource_group_name                       = \"$resource_group_name\"\n"                       >> ./terraform.tfvars
printf "storage_account_key_kerb_secret           = \"$storage_account_name-kerb1\"\n"                >> ./terraform.tfvars
printf "storage_account_name                      = \"$storage_account_name\"\n"                      >> ./terraform.tfvars
printf "storage_container_name                    = \"$storage_container_name\"\n"                    >> ./terraform.tfvars
printf "subnet_adds_address_prefix                = \"$subnet_adds_address_prefix\"\n"                >> ./terraform.tfvars
printf "subnet_AzureBastionSubnet_address_prefix  = \"$subnet_AzureBastionSubnet_address_prefix\"\n"  >> ./terraform.tfvars
printf "subscription_id                           = \"$subscription_id\"\n"                           >> ./terraform.tfvars
printf "tags                                      = $tags\n"                                          >> ./terraform.tfvars
printf "vm_adds_name                              = \"$vm_adds_name\"\n"                              >> ./terraform.tfvars
printf "vnet_address_space                        = \"$vnet_address_space\"\n"                        >> ./terraform.tfvars
printf "vnet_name                                 = \"$vnet_name\"\n"                                 >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in \"variables.tf\" prior to applying Terraform configurations...\n"
printf "\nBootstrapping complete...\n"
exit 0
