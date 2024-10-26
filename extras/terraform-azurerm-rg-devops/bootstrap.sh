#!/bin/bash

# Bootstraps deployment with pre-requisites for applying terraform configurations
# Script is idempotent and can be run multiple times

gen_strong_password () {
    # Define constants
    password_length=12
    password=""
    digit_count=0
    uppercase_count=0
    lowercase_count=0
    symbol_count=0

    # Seed random number generator
    RANDOM=$(date +%s%N)

    for (( i=1; i<=$password_length; i++))
    do
        if [ $i -eq 1 ] || [ $i -eq $password_length ]
        then
          password_category=$(( $RANDOM % 3 ))
        else
          password_category=$(( $RANDOM % 4 ))
        fi

        case $password_category in
            0 )
                # Digits
                if [ $digit_count -le 3 ]
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
                if [ $uppercase_count -le 3 ]
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
                if [ $lowercase_count -le 3 ]
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

# Initialize constants
admin_username_secret="devopsadminuser"
admin_password_secret="devopsadminpassword"

# Initialize defaults
default_aad_tenant_id=$(az account list --query "[? isDefault]|[0].tenantId" --output tsv)
default_admin_username="devopsbootstrapadmin"
default_cost_center="mycostcenter"
default_environment="dev"
default_location="centralus"
default_owner_object_id=$(az account get-access-token --query accessToken --output tsv | tr -d '\n' | python3 -c "import jwt, sys; print(jwt.decode(sys.stdin.read(), algorithms=['RS256'], options={'verify_signature': False})['oid'])")
default_project="myproject"
default_resource_group_name="rg-devops-tf"
default_skip_admin_password_gen="no"
default_skip_ssh_key_gen="no"
default_subnet_id="/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/someresourcegroup/providers/Microsoft.Network/virtualNetworks/somevirtualnetwork/subnets/somesubnet"
default_subscription_id=$(az account list --only-show-errors --query "[? isDefault]|[0].id" --output tsv)
default_vm_name="jumplinux2"

# User input
read -e -i $default_aad_tenant_id           -p "Microsoft Entra tenant id (aad_tenant_id) -------------------------------------------: " aad_tenant_id
read -e -i $default_subscription_id         -p "Subscription id (subscription_id)----------------------------------------------------: " subscription_id
read -e -i $default_owner_object_id         -p "Owner object id (owner_object_id) ---------------------------------------------------: " owner_object_id
read -e -i $default_project                 -p "Project (project) -------------------------------------------------------------------: " project
read -e -i $default_cost_center             -p "Cost center (cost_center) -----------------------------------------------------------: " cost_center
read -e -i $default_environment             -p "Environment (environment) -----------------------------------------------------------: " environment
read -e -i $default_resource_group_name     -p "Resource group (resource_group_name) ------------------------------------------------: " resource_group_name
read -e -i $default_location                -p "location (location) -----------------------------------------------------------------: " location
read -e -i $default_vm_name                 -p "Virtual machine name (vm_name) ------------------------------------------------------: " vm_name
read -e -i $default_subnet_id               -p "Subnet id (subnet_id) ---------------------------------------------------------------: " subnet_id
read -e -i $default_admin_username          -p "Admin username (admin_username) -----------------------------------------------------: " admin_username
read -e -i $default_skip_admin_password_gen -p "Skip 'adminpassword' key vault secret generation (skip_admin_password_gen) yes/no ? -: " skip_admin_password_gen
read -e -i $default_skip_ssh_key_gen        -p "Skip SSH key generation (skip_ssh_key_gen) yes/no ? ---------------------------------: " skip_ssh_key_gen

aad_tenant_id=${aad_tenant_id:-$default_aad_tenant_id}
admin_username=${admin_username:-$default_admin_username}
cost_center=${cost_center:-$default_cost_center}
environment=${environment:-$default_environment}
location=${location:-$default_location}
owner_object_id=${owner_object_id:-$default_owner_object_id}
project=${project:-$default_project}
resource_group_name=${resource_group_name:-$default_resource_group_name}
skip_admin_password_gen=${skip_admin_password_gen:-$default_skip_admin_password_gen}
skip_ssh_key_gen=${skip_ssh_key_gen:-$default_skip_ssh_key_gen}
subnet_id=${subnet_id:-$default_subnet_id}
subscription_id=${subscription_id:-$default_subscription_id}
vm_name=${vm_name:-$default_vm_name}

# Validate subscription
subscription_name=$(az account show --subscription $subscription_id --query name --output tsv)

if [ -n "$subscription_name" ]
then 
  printf "Found subscription '$subscription_name'...\n"
else
  printf "Invalid subscription id '$subscription_id'...\n"
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

# Validate skip_ssh_key_gen input
if [ "$skip_ssh_key_gen" != 'yes' ] && [ "$skip_ssh_key_gen" != 'no' ]
then
  printf "Invalid skip_ssh_key_gen input '$skip_ssh_key_gen'. Valid values are 'yes' or 'no'...\n"
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
    --tags "Cost Center"=$cost_center project=$project environment=$environment provisioner="bootstrap.sh"
fi

# bootstrap key vault
keyvault_name=$(az keyvault list --subscription $subscription_id --resource-group $resource_group_name --query "[?tags.provisioner == 'bootstrap.sh'] | [0].name" --output tsv)

if [ -n "$keyvault_name" ]
then
  printf "Found key vault '$keyvault_name'...\n"
else
  keyvault_name=kv-$(tr -dc "[:lower:][:digit:]" < /dev/urandom | head -c 15)
  printf "Creating keyvault '$keyvault_name' in resource group '$resource_group_name'...\n"
  az keyvault create \
    --subscription $subscription_id \
    --name $keyvault_name \
    --resource-group $resource_group_name \
    --location $location \
    --sku standard \
    --no-self-perms \
    --enable-rbac-authorization false \
    --tags "Cost Center"=$cost_center project=$project environment=$environment provisioner="bootstrap.sh"
fi

keyvault_id=$(az keyvault show --subscription $subscription_id --resource-group $resource_group_name --name $keyvault_name --query id --output tsv)
keyvault_uri=$(az keyvault show --subscription $subscription_id --resource-group $resource_group_name --name $keyvault_name --query properties.vaultUri --output tsv)

printf "Setting secret admin permissions for '$owner_object_id' in keyvault '$keyvault_name'...\n"
az keyvault set-policy \
  --subscription $subscription_id \
  --resource-group $resource_group_name \
  --name $keyvault_name \
  --object-id $owner_object_id \
  --secret-permissions get list 'set'

printf "Setting secret '$admin_username_secret' with value '$admin_username' in keyvault '$keyvault_name'...\n"
az keyvault secret set \
  --subscription $subscription_id \
  --vault-name $keyvault_name \
  --name $admin_username_secret \
  --value "$admin_username"

if [ "$skip_admin_password_gen" = 'no' ]
then
  admin_password=$(gen_strong_password)
  printf "Setting secret '$admin_password_secret' with value length '${#admin_password}' in keyvault '$keyvault_name'...\n"
  az keyvault secret set \
    --subscription $subscription_id \
    --vault-name $keyvault_name \
    --name $admin_password_secret \
    --value "$admin_password" \
    --output none
fi

# Generate SSH keys
if [ "$skip_ssh_key_gen" = 'no' ]
then
  printf "Gnerating SSH keys...\n"
  echo -e 'y' | ssh-keygen -m PEM -t rsa -b 4096 -C "$admin_username" -f sshkeytemp -N "$admin_password" 
fi

if [ ! -f 'sshkeytemp.pub' ] 
then
  printf "Unable to locate SSH public key file 'sshktemp.pub'...\n"
  usage
fi

if [ ! -f 'sshkeytemp' ] 
then
  printf "Unable to locate SSH private key file 'sshktemp'...\n"
  usage
fi

ssh_public_key_secret_value=$(cat sshkeytemp.pub)
ssh_private_key_secret_value=$(cat sshkeytemp)
ssh_private_key_secret_name="$admin_username-ssh-key-private"

printf "Setting secret '$ssh_private_key_secret_name' with value length \"${#ssh_private_key_secret_value}\" in keyvault '$default_key_vault_name'...\n"
az keyvault secret set \
    --vault-name $keyvault_name \
    --name $ssh_private_key_secret_name \
    --value "$ssh_private_key_secret_value" \
    --output none

# Build tags map
tags=""
tags="${tags}{\n"
tags="${tags}  project     = \"$project\",\n"
tags="${tags}  \"Cost Center\"  = \"$cost_center\",\n"
tags="${tags}  environment = \"$environment\"\n"
tags="${tags}}"

# Generate terraform.tfvars file
printf "Generating terraform.tfvars file...\n\n"

printf "admin_password_secret = \"$admin_password_secret\"\n"       > ./terraform.tfvars
printf "admin_username_secret = \"$admin_username_secret\"\n"       >> ./terraform.tfvars
printf "key_vault_id          = \"$keyvault_id\"\n"                 >> ./terraform.tfvars
printf "key_vault_name        = \"$keyvault_name\"\n"               >> ./terraform.tfvars
printf "location              = \"$location\"\n"                    >> ./terraform.tfvars
printf "resource_group_name   = \"$resource_group_name\"\n"         >> ./terraform.tfvars
printf "ssh_public_key        = \"$ssh_public_key_secret_value\"\n" >> ./terraform.tfvars
printf "subnet_id             = \"$subnet_id\"\n"                   >> ./terraform.tfvars
printf "subscription_id       = \"$subscription_id\"\n"             >> ./terraform.tfvars
printf "tags                  = $tags\n"                            >> ./terraform.tfvars
printf "vm_name               = \"$vm_name\"\n"                     >> ./terraform.tfvars

cat ./terraform.tfvars

printf "\nReview defaults in 'variables.tf' prior to applying terraform plans...\n"
printf "Bootstrapping complete...\n"
exit 0
